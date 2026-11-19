import { Router, type Request } from 'express';
import { z } from 'zod';
import type { RequestStatus, ServiceRequest } from '@prisma/client';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { requireAuth } from '../middleware/auth.js';
import { getActiveSubscription } from '../lib/subscriptions.js';
import { computeServiceCharge } from '../lib/money.js';
import { config } from '../config.js';
import { notify } from '../lib/notify.js';
import { emitToRequest, emitToUser } from '../lib/socket.js';
import { upload, storePublic } from '../lib/upload.js';
import { afterCompleted, hasOpenClaim } from '../lib/completion.js';
import { checkQuality, commissionFor } from '../lib/rewards.js';
import { blockAt, blockedMessage, bogotaDateTime, clashAt } from '../lib/calendar.js';

export const requestsRouter = Router();
requestsRouter.use(requireAuth);

export const STATUS_LABEL: Record<RequestStatus, string> = {
  PENDING: 'Pendiente',
  ACCEPTED: 'Aceptada',
  REJECTED: 'Rechazada',
  IN_PROGRESS: 'En proceso',
  COMPLETED: 'Finalizada',
  CANCELLED: 'Cancelada',
};

const listInclude = {
  service: { select: { id: true, title: true, price: true, priceUnit: true, category: { select: { name: true } } } },
  client: { select: { id: true, name: true, avatarUrl: true, clientRatingAvg: true, clientRatingCount: true } },
  professional: { select: { id: true, userId: true, user: { select: { name: true, avatarUrl: true } } } },
  payments: { select: { id: true, kind: true, status: true, totalAmount: true, createdAt: true }, orderBy: { createdAt: 'desc' as const } },
  review: { select: { id: true, rating: true } },
  clientReview: { select: { id: true, rating: true } },
};

type Loaded = ServiceRequest & { professional: { userId: string } };

/** Carga la solicitud y verifica que el usuario sea participante (o admin). */
async function loadForParticipant(req: Request): Promise<Loaded & { isClient: boolean; isPro: boolean }> {
  const r = await prisma.serviceRequest.findUnique({
    where: { id: req.params.id as string },
    include: { professional: { select: { userId: true } } },
  });
  if (!r) throw notFound('Solicitud no encontrada');
  const isClient = r.clientId === req.user!.id;
  const isPro = r.professional.userId === req.user!.id;
  if (!isClient && !isPro && req.user!.role !== 'ADMIN') throw forbidden();
  return { ...r, isClient, isPro };
}

const hasApprovedPayment = (requestId: string, kind: 'SERVICE' | 'DIAGNOSTIC' = 'SERVICE') =>
  prisma.payment.count({ where: { requestId, kind, status: 'APPROVED' } }).then((c) => c > 0);

/** La visita de diagnóstico está cubierta: es gratis (valor 0) o el cliente ya la pagó. */
const diagnosticDone = async (r: { id: string; diagnosticFee: number }) =>
  r.diagnosticFee === 0 || (await hasApprovedPayment(r.id, 'DIAGNOSTIC'));

/**
 * Etapa del flujo de contratación (para la app):
 *   PENDING → (profesional acepta) → PAY_DIAGNOSTIC → (cliente paga la póliza) → DIAGNOSIS
 *   → (profesional visita y cotiza) → PAY_SERVICE → (cliente paga valor + 3 %) → READY_TO_START
 *   → IN_PROGRESS → COMPLETED
 */
export function requestStage(r: { status: RequestStatus; agreedPrice: number | null }, diagnosticPaid: boolean, paid: boolean) {
  if (r.status !== 'ACCEPTED') return r.status;
  if (!diagnosticPaid) return 'PAY_DIAGNOSTIC';
  if (!r.agreedPrice) return 'DIAGNOSIS';
  if (!paid) return 'PAY_SERVICE';
  return 'READY_TO_START';
}

/**
 * Cambia el estado de forma atómica (solo si sigue en `from`), registra el historial
 * y notifica a la contraparte.
 */
async function transition(
  r: Loaded,
  from: RequestStatus[],
  to: RequestStatus,
  actorId: string,
  note?: string,
  extra: Partial<Pick<ServiceRequest, 'cancelReason'>> = {},
) {
  if (!from.includes(r.status)) {
    throw conflict(`No se puede pasar de "${STATUS_LABEL[r.status]}" a "${STATUS_LABEL[to]}"`);
  }
  await prisma.$transaction(async (tx) => {
    const updated = await tx.serviceRequest.updateMany({
      where: { id: r.id, status: { in: from } },
      data: { status: to, ...extra },
    });
    if (updated.count === 0) throw conflict('La solicitud cambió de estado; recarga e intenta de nuevo');
    await tx.requestStatusHistory.create({
      data: { requestId: r.id, fromStatus: r.status, toStatus: to, changedById: actorId, note },
    });
  });

  const counterpart = actorId === r.clientId ? r.professional.userId : r.clientId;
  await notify(
    counterpart,
    'REQUEST_STATUS',
    `Solicitud ${STATUS_LABEL[to].toLowerCase()}`,
    note ? `Tu solicitud pasó a "${STATUS_LABEL[to]}": ${note}` : `Tu solicitud pasó a "${STATUS_LABEL[to]}".`,
    { requestId: r.id, status: to },
    { email: ['ACCEPTED', 'REJECTED', 'CANCELLED'].includes(to) },
  );
  emitToRequest(r.id, 'request:updated', { id: r.id, status: to });
  return detail(r.id, actorId);
}

async function detail(id: string, viewerId?: string) {
  const r = await prisma.serviceRequest.findUniqueOrThrow({
    where: { id },
    include: {
      ...listInclude,
      service: { include: { category: true } },
      history: { orderBy: { createdAt: 'asc' }, include: { changedBy: { select: { name: true } } } },
      payments: { orderBy: { createdAt: 'desc' } },
      review: true,
      clientReview: true,
      claims: { orderBy: { createdAt: 'desc' }, select: { id: true, type: true, status: true, action: true, resolution: true, description: true, photos: true, openedById: true, createdAt: true } },
      notes: viewerId ? { where: { userId: viewerId }, select: { note: true, updatedAt: true } } : false,
    },
  });
  const servicePayment = r.payments.find((p) => p.kind === 'SERVICE' && p.status === 'APPROVED');
  const paid = !!servicePayment;
  const diagnosticPaid = r.diagnosticFee === 0 || r.payments.some((p) => p.kind === 'DIAGNOSTIC' && p.status === 'APPROVED');
  // Ya pagado: se muestra lo que realmente se cobró. Si no, la tarifa vigente del cliente
  // (3 % normal o 1 % si tiene un beneficio de cliente frecuente / referido).
  const fee = await commissionFor(r.clientId);
  const rate = servicePayment?.commissionRate ?? fee.rate;
  const charge = servicePayment
    ? { serviceAmount: servicePayment.serviceAmount, commissionAmount: servicePayment.commissionAmount, totalAmount: servicePayment.totalAmount }
    : r.agreedPrice
      ? computeServiceCharge(r.agreedPrice, rate)
      : null;
  const { proLat, proLng, proLocationAt, notes, ...rest } = r;
  const enRoute = !!r.enRouteAt && !r.arrivedAt;
  return {
    ...rest,
    charge,
    commission: { rate, standardRate: fee.standardRate, reduced: rate < fee.standardRate },
    paid,
    diagnosticPaid,
    diagnosticFree: r.diagnosticFee === 0,
    myNote: (notes as { note: string }[] | undefined)?.[0]?.note ?? null,
    reschedule: r.rescheduleAt
      ? { at: r.rescheduleAt, byId: r.rescheduleById, byMe: !!viewerId && r.rescheduleById === viewerId, note: r.rescheduleNote }
      : null,
    stage: requestStage(r, diagnosticPaid, paid),
    // La ubicación del profesional solo viaja mientras va en camino
    trip: {
      enRoute,
      enRouteAt: r.enRouteAt,
      arrivedAt: r.arrivedAt,
      lat: enRoute ? proLat : null,
      lng: enRoute ? proLng : null,
      at: enRoute ? proLocationAt : null,
    },
    openClaim: r.claims.some((c) => c.status === 'OPEN' || c.status === 'IN_REVIEW'),
    canClaim: ['ACCEPTED', 'IN_PROGRESS'].includes(r.status) || (r.status === 'COMPLETED' && (!r.warrantyUntil || r.warrantyUntil > new Date())),
  };
}

// ---------- Crear y consultar ----------

const createSchema = z.object({
  serviceId: z.string().min(1),
  description: z.string().trim().min(10, 'describe el problema con al menos 10 caracteres').max(2000),
  address: z.string().trim().min(5).max(300),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
  scheduledAt: z.coerce.date(),
  additionalInfo: z.string().trim().max(1000).optional(),
});

requestsRouter.post('/', async (req, res) => {
  if (req.user!.role !== 'CLIENT') throw forbidden('Solo los clientes pueden solicitar servicios');
  const body = parse(createSchema, req.body);
  if (body.scheduledAt.getTime() < Date.now() + 30 * 60 * 1000) {
    throw badRequest('La fecha deseada debe ser al menos 30 minutos en el futuro');
  }
  const service = await prisma.service.findFirst({
    where: { id: body.serviceId, active: true },
    include: { professional: { select: { id: true, userId: true, verified: true, diagnosticFee: true, user: { select: { status: true } } } } },
  });
  if (!service) throw notFound('Servicio no encontrado');
  if (service.professional.user.status !== 'ACTIVE') throw badRequest('El profesional no está disponible');
  if (config.requireVerification && !service.professional.verified) {
    throw badRequest('Este profesional aún no ha sido verificado por NetJob');
  }
  if (!(await getActiveSubscription(service.professionalId))) {
    throw badRequest('Este profesional no está recibiendo solicitudes en este momento');
  }
  const block = await blockAt(service.professionalId, body.scheduledAt);
  if (block) throw conflict(blockedMessage(block));

  const created = await prisma.serviceRequest.create({
    data: {
      ...body,
      // El valor que fijó el profesional en su perfil (con el tope vigente)
      diagnosticFee: Math.min(service.professional.diagnosticFee, config.maxDiagnosticFee),
      clientId: req.user!.id,
      professionalId: service.professionalId,
      history: { create: { toStatus: 'PENDING', changedById: req.user!.id, note: 'Solicitud creada' } },
    },
  });
  await notify(
    service.professional.userId,
    'REQUEST_NEW',
    'Nueva solicitud de servicio',
    `Tienes una nueva solicitud para "${service.title}" el ${bogotaDateTime(body.scheduledAt)}.`,
    { requestId: created.id },
    { email: true },
  );
  res.status(201).json(await detail(created.id, req.user!.id));
});

requestsRouter.post('/:id/photos', upload.array('files', 6), async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient) throw forbidden();
  const files = (req.files as Express.Multer.File[]) ?? [];
  if (!files.length) throw badRequest('Adjunta al menos una imagen en el campo "files"');
  const photos = [...r.photos, ...(await Promise.all(files.map(storePublic)))].slice(0, 10);
  await prisma.serviceRequest.update({ where: { id: r.id }, data: { photos } });
  res.json(await detail(r.id, req.user!.id));
});

const STATUS_VALUES = ['PENDING', 'ACCEPTED', 'REJECTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'] as const;

/** Listado (historial) del usuario: como cliente o como profesional según su rol. */
requestsRouter.get('/', async (req, res) => {
  const q = parse(
    z.object({
      status: z
        .string()
        .optional()
        .transform((s) => (s ? s.split(',') : undefined))
        .pipe(z.array(z.enum(STATUS_VALUES)).optional()),
    }),
    req.query,
  );
  const u = req.user!;
  const where =
    u.role === 'PROFESSIONAL'
      ? { professionalId: u.professionalId ?? '__none__' }
      : u.role === 'CLIENT'
        ? { clientId: u.id }
        : {};
  const rows = await prisma.serviceRequest.findMany({
    where: { ...where, status: q.status ? { in: q.status } : undefined },
    include: listInclude,
    orderBy: { updatedAt: 'desc' },
    take: 200,
  });
  // El listado no expone la ubicación del profesional; solo si va en camino
  res.json(rows.map(({ proLat, proLng, proLocationAt, ...r }) => ({ ...r, enRoute: !!r.enRouteAt && !r.arrivedAt })));
});

requestsRouter.get('/:id', async (req, res) => {
  const r = await loadForParticipant(req);
  res.json(await detail(r.id, req.user!.id));
});

// ---------- Ciclo de vida ----------

requestsRouter.post('/:id/accept', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden('Solo el profesional puede aceptar');
  const body = parse(z.object({ note: z.string().max(500).optional() }), req.body ?? {});
  if (!(await getActiveSubscription(r.professionalId))) {
    throw forbidden('Tu suscripción no está activa. Renuévala para aceptar solicitudes.');
  }
  // Evita servicios simultáneos y citas dentro de los bloqueos de la agenda
  if (await clashAt(r.professionalId, r.scheduledAt, r.id)) {
    throw conflict('Ya tienes otro servicio aceptado en ese horario. Propón otra hora desde la cita o coordínala por el chat.');
  }
  if (await blockAt(r.professionalId, r.scheduledAt)) {
    throw conflict('Esa hora cae en un bloqueo de tu agenda. Propón otra hora al cliente o quita el bloqueo.');
  }
  res.json(await transition(r, ['PENDING'], 'ACCEPTED', req.user!.id, body.note));
});

requestsRouter.post('/:id/reject', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden('Solo el profesional puede rechazar');
  const body = parse(z.object({ note: z.string().max(500).optional() }), req.body ?? {});
  res.json(await transition(r, ['PENDING'], 'REJECTED', req.user!.id, body.note));
});

/**
 * Cotización del valor final, después de la visita de diagnóstico. Se puede corregir
 * mientras el cliente no haya pagado; un checkout pendiente con el valor anterior se anula.
 */
requestsRouter.post('/:id/quote', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden('Solo el profesional puede cotizar');
  if (r.status !== 'ACCEPTED') throw conflict('Solo se puede cotizar una solicitud aceptada');
  if (!(await diagnosticDone(r))) {
    throw conflict('El cliente aún no ha pagado la visita de diagnóstico');
  }
  if (await hasApprovedPayment(r.id)) throw conflict('El cliente ya pagó el servicio; el valor no se puede cambiar');
  const inFlight = await prisma.payment.count({
    where: { requestId: r.id, kind: 'SERVICE', status: 'PENDING', gatewayTransactionId: { not: null } },
  });
  if (inFlight) throw conflict('El cliente tiene un pago en curso. Espera a que termine para cambiar el valor.');
  const body = parse(
    z.object({
      agreedPrice: z.number().int().min(1000, 'el valor mínimo es $1.000').max(100_000_000),
      quoteNote: z.string().trim().min(10, 'explica al cliente qué incluye (mín. 10 caracteres)').max(2000),
    }),
    req.body,
  );
  await prisma.$transaction([
    prisma.payment.updateMany({ where: { requestId: r.id, kind: 'SERVICE', status: 'PENDING' }, data: { status: 'VOIDED' } }),
    prisma.serviceRequest.update({ where: { id: r.id }, data: { ...body, quotedAt: new Date() } }),
    prisma.requestStatusHistory.create({
      data: {
        requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: req.user!.id,
        note: `Cotización tras el diagnóstico: $${body.agreedPrice.toLocaleString('es-CO')}`,
      },
    }),
  ]);
  await notify(
    r.clientId,
    'REQUEST_QUOTE',
    'Recibiste la cotización',
    `El profesional cotizó el servicio en $${body.agreedPrice.toLocaleString('es-CO')}. Revísala y paga para que empiece el trabajo.`,
    { requestId: r.id },
    { email: true },
  );
  emitToRequest(r.id, 'request:updated', { id: r.id });
  res.json(await detail(r.id, req.user!.id));
});

requestsRouter.post('/:id/cancel', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient && !r.isPro) throw forbidden();
  const { reason } = parse(z.object({ reason: z.string().trim().min(3).max(500) }), req.body ?? {});
  // Con el servicio ya pagado el dinero está retenido: la cancelación se tramita con una
  // reclamación para que NetJob decida la devolución. La visita de diagnóstico no se reembolsa.
  if (await hasApprovedPayment(r.id)) {
    throw conflict('Este servicio ya fue pagado. Para cancelarlo abre una reclamación desde la solicitud y NetJob revisará la devolución.');
  }
  await transition(r, ['PENDING', 'ACCEPTED'], 'CANCELLED', req.user!.id, reason, { cancelReason: reason });
  await prisma.serviceRequest.update({ where: { id: r.id }, data: { enRouteAt: null, proLat: null, proLng: null, proLocationAt: null, rescheduleAt: null, rescheduleById: null, rescheduleNote: null } });
  res.json(await detail(r.id, req.user!.id));
});

requestsRouter.post('/:id/start', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden('Solo el profesional puede iniciar el servicio');
  if (!(await hasApprovedPayment(r.id))) throw conflict('El cliente aún no ha pagado el valor cotizado');
  res.json(await transition(r, ['ACCEPTED'], 'IN_PROGRESS', req.user!.id));
});

// ---------- Trayecto: "voy en camino" y ubicación en vivo ----------

/** El profesional solo puede ir en camino a una visita pagada o a un trabajo en curso. */
async function assertCanTravel(r: Loaded) {
  if (r.status === 'IN_PROGRESS') return;
  if (r.status === 'ACCEPTED' && (await diagnosticDone(r))) return;
  throw conflict('Podrás avisar que vas en camino cuando el cliente pague la visita de diagnóstico');
}

const lat = z.number().min(-90).max(90);
const lng = z.number().min(-180).max(180);

/**
 * El profesional indica que va en camino (start), que llegó (arrive) o que dejó de ir (stop).
 * Solo entre start y arrive/stop el cliente puede ver su ubicación.
 */
requestsRouter.post('/:id/trip', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden('Solo el profesional puede actualizar el trayecto');
  const body = parse(z.object({ action: z.enum(['start', 'arrive', 'stop']), lat: lat.optional(), lng: lng.optional() }), req.body);
  const me = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id }, select: { name: true } });
  const name = me.name.split(' ')[0];
  const now = new Date();
  const clear = { proLat: null, proLng: null, proLocationAt: null };
  const log = (note: string) =>
    prisma.requestStatusHistory.create({
      data: { requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: req.user!.id, note },
    });

  if (body.action === 'start') {
    await assertCanTravel(r);
    const already = !!r.enRouteAt && !r.arrivedAt;
    const hasPos = body.lat !== undefined && body.lng !== undefined;
    await prisma.serviceRequest.update({
      where: { id: r.id },
      data: {
        enRouteAt: already ? r.enRouteAt : now,
        arrivedAt: null,
        ...(hasPos ? { proLat: body.lat, proLng: body.lng, proLocationAt: now } : {}),
      },
    });
    if (!already) {
      await log('El profesional va en camino');
      await notify(r.clientId, 'TRIP', `${name} va en camino`, 'Tu profesional salió hacia tu dirección. Toca para ver por dónde va.', { requestId: r.id, track: true });
    }
  } else if (body.action === 'arrive') {
    if (!r.enRouteAt || r.arrivedAt) throw conflict('Primero indica que vas en camino');
    await prisma.serviceRequest.update({ where: { id: r.id }, data: { arrivedAt: now, ...clear } });
    await log('El profesional llegó al domicilio');
    await notify(r.clientId, 'TRIP', `${name} llegó`, 'Tu profesional ya está en la dirección del servicio.', { requestId: r.id });
  } else if (r.enRouteAt && !r.arrivedAt) {
    await prisma.serviceRequest.update({ where: { id: r.id }, data: { enRouteAt: null, ...clear } });
    await log('El profesional pausó el trayecto');
    await notify(r.clientId, 'TRIP', 'El profesional pausó el trayecto', 'Dejó de compartir su ubicación. Escríbele por el chat si necesitas confirmar la hora.', { requestId: r.id });
  }
  emitToRequest(r.id, 'request:updated', { id: r.id });
  res.json(await detail(r.id, req.user!.id));
});

/** Posición del profesional mientras va en camino. Se reenvía en vivo al cliente. */
requestsRouter.post('/:id/trip/location', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden();
  if (!r.enRouteAt || r.arrivedAt) throw conflict('No estás compartiendo tu ubicación en este momento');
  const body = parse(z.object({ lat, lng }), req.body);
  const at = new Date();
  await prisma.serviceRequest.update({ where: { id: r.id }, data: { proLat: body.lat, proLng: body.lng, proLocationAt: at } });
  emitToRequest(r.id, 'request:location', { id: r.id, lat: body.lat, lng: body.lng, at });
  res.json({ ok: true });
});

/**
 * Fin del servicio con doble confirmación: cada parte confirma por su lado. Solo cuando
 * ambos confirman, la solicitud pasa a Finalizada y el dinero retenido se libera al
 * profesional. La comisión de NetJob ya se cobró al momento del pago.
 */
requestsRouter.post('/:id/complete', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro && !r.isClient) throw forbidden();
  if (r.status !== 'IN_PROGRESS') throw conflict('Solo se puede confirmar el fin de un servicio en proceso');
  if (await hasOpenClaim(r.id)) {
    throw conflict('Hay una reclamación abierta sobre este servicio. El pago sigue retenido hasta que NetJob la resuelva.');
  }
  const field = r.isClient ? 'clientConfirmedAt' : 'proConfirmedAt';
  if (r[field]) throw conflict('Ya confirmaste que el servicio terminó; falta la otra parte');
  const updated = await prisma.serviceRequest.update({ where: { id: r.id }, data: { [field]: new Date() } });
  await prisma.requestStatusHistory.create({
    data: {
      requestId: r.id, fromStatus: 'IN_PROGRESS', toStatus: 'IN_PROGRESS', changedById: req.user!.id,
      note: r.isClient ? 'El cliente confirmó que el trabajo terminó' : 'El profesional confirmó que el trabajo terminó',
    },
  });

  if (!updated.clientConfirmedAt || !updated.proConfirmedAt) {
    const other = r.isClient ? r.professional.userId : r.clientId;
    await notify(
      other,
      'REQUEST_STATUS',
      'Confirma que el servicio terminó',
      r.isClient
        ? 'El cliente confirmó que el trabajo terminó. Confírmalo tú también para recibir tu dinero.'
        : 'El profesional marcó el trabajo como terminado. Si todo quedó bien, confírmalo para finalizar.',
      { requestId: r.id },
      { email: true },
    );
    emitToRequest(r.id, 'request:updated', { id: r.id });
    return res.json(await detail(r.id, req.user!.id));
  }

  await transition({ ...r, status: 'IN_PROGRESS' }, ['IN_PROGRESS'], 'COMPLETED', req.user!.id, 'Ambas partes confirmaron');
  await afterCompleted(r.id);
  res.json(await detail(r.id, req.user!.id));
});

// ---------- Agenda: reprogramar la cita y notas privadas ----------

/** Estados en los que la cita todavía se puede mover. */
const RESCHEDULABLE: RequestStatus[] = ['PENDING', 'ACCEPTED'];

/** Verifica que el profesional pueda atender a esa hora (bloqueos y otras citas aceptadas). */
async function assertSlotFree(r: Loaded, at: Date, byPro: boolean) {
  const block = await blockAt(r.professionalId, at);
  if (block) throw conflict(byPro ? 'Esa hora cae en un bloqueo de tu agenda.' : blockedMessage(block));
  if (await clashAt(r.professionalId, at, r.id)) {
    throw conflict(byPro ? 'Ya tienes otro servicio aceptado a esa hora.' : 'El profesional ya tiene otra cita a esa hora. Propón otra.');
  }
}

/**
 * Una parte propone una nueva fecha y hora; la otra la acepta o la rechaza. Solo hay una
 * propuesta vigente a la vez (una nueva reemplaza la anterior del mismo usuario).
 */
requestsRouter.post('/:id/reschedule', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient && !r.isPro) throw forbidden();
  if (!RESCHEDULABLE.includes(r.status)) throw conflict('Esta cita ya no se puede reprogramar');
  if (r.rescheduleAt && r.rescheduleById !== req.user!.id) {
    throw conflict('La otra parte ya propuso una nueva hora. Respóndela primero.');
  }
  const body = parse(
    z.object({ scheduledAt: z.coerce.date(), note: z.string().trim().max(300).optional() }),
    req.body,
  );
  if (body.scheduledAt.getTime() < Date.now() + 30 * 60 * 1000) {
    throw badRequest('La nueva hora debe ser al menos 30 minutos en el futuro');
  }
  if (Math.abs(body.scheduledAt.getTime() - r.scheduledAt.getTime()) < 60 * 1000) {
    throw badRequest('Elige una hora distinta a la actual');
  }
  await assertSlotFree(r, body.scheduledAt, r.isPro);
  await prisma.serviceRequest.update({
    where: { id: r.id },
    data: { rescheduleAt: body.scheduledAt, rescheduleById: req.user!.id, rescheduleNote: body.note ?? null },
  });
  await prisma.requestStatusHistory.create({
    data: {
      requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: req.user!.id,
      note: `${r.isClient ? 'El cliente' : 'El profesional'} propuso cambiar la cita al ${bogotaDateTime(body.scheduledAt)}`,
    },
  });
  const other = r.isClient ? r.professional.userId : r.clientId;
  await notify(
    other,
    'REQUEST_STATUS',
    'Proponen cambiar la hora de la cita',
    `Nueva hora propuesta: ${bogotaDateTime(body.scheduledAt)} (antes: ${bogotaDateTime(r.scheduledAt)}).${body.note ? ` "${body.note}"` : ''} Acéptala o recházala desde tu agenda.`,
    { requestId: r.id, calendar: true },
    { email: true },
  );
  emitToRequest(r.id, 'request:updated', { id: r.id });
  res.json(await detail(r.id, req.user!.id));
});

/** La contraparte acepta (cambia la cita) o rechaza la propuesta. Quien propuso puede retirarla. */
requestsRouter.post('/:id/reschedule/respond', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient && !r.isPro) throw forbidden();
  if (!r.rescheduleAt) throw conflict('No hay ninguna propuesta de cambio de hora');
  const { accept } = parse(z.object({ accept: z.boolean() }), req.body);
  const mine = r.rescheduleById === req.user!.id;
  if (mine && accept) throw forbidden('La propuesta la debe aceptar la otra parte');
  const clear = { rescheduleAt: null, rescheduleById: null, rescheduleNote: null };
  const other = r.isClient ? r.professional.userId : r.clientId;
  const who = r.isClient ? 'El cliente' : 'El profesional';

  if (!accept) {
    await prisma.serviceRequest.update({ where: { id: r.id }, data: clear });
    await prisma.requestStatusHistory.create({
      data: {
        requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: req.user!.id,
        note: mine ? `${who} retiró su propuesta de cambio de hora` : `${who} rechazó el cambio de hora`,
      },
    });
    await notify(
      other,
      'REQUEST_STATUS',
      mine ? 'Retiraron la propuesta de cambio' : 'No aceptaron el cambio de hora',
      `La cita sigue el ${bogotaDateTime(r.scheduledAt)}. Si necesitas otra hora, escríbele por el chat o propón una distinta.`,
      { requestId: r.id, calendar: true },
    );
  } else {
    if (!RESCHEDULABLE.includes(r.status)) throw conflict('Esta cita ya no se puede reprogramar');
    if (r.rescheduleAt.getTime() < Date.now()) throw conflict('La hora propuesta ya pasó. Pide una nueva.');
    await assertSlotFree(r, r.rescheduleAt, r.isPro);
    await prisma.serviceRequest.update({
      where: { id: r.id },
      data: { ...clear, scheduledAt: r.rescheduleAt, reminderDaySentAt: null, reminderHourSentAt: null },
    });
    await prisma.requestStatusHistory.create({
      data: {
        requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: req.user!.id,
        note: `Cita reprogramada para el ${bogotaDateTime(r.rescheduleAt)}`,
      },
    });
    await notify(
      other,
      'REQUEST_STATUS',
      'Cita reprogramada',
      `${who} aceptó el cambio. La cita queda para el ${bogotaDateTime(r.rescheduleAt)}.`,
      { requestId: r.id, calendar: true },
      { email: true },
    );
  }
  emitToRequest(r.id, 'request:updated', { id: r.id });
  res.json(await detail(r.id, req.user!.id));
});

/** Nota privada sobre la cita (ej. "llevar escalera"). Vacía = se borra. */
requestsRouter.put('/:id/note', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient && !r.isPro) throw forbidden();
  const { note } = parse(z.object({ note: z.string().trim().max(1000) }), req.body);
  const key = { requestId_userId: { requestId: r.id, userId: req.user!.id } };
  if (!note) await prisma.appointmentNote.deleteMany({ where: { requestId: r.id, userId: req.user!.id } });
  else await prisma.appointmentNote.upsert({ where: key, update: { note }, create: { requestId: r.id, userId: req.user!.id, note } });
  res.json({ note: note || null });
});

// ---------- Chat asociado a la solicitud ----------

const CHAT_OPEN: RequestStatus[] = ['PENDING', 'ACCEPTED', 'IN_PROGRESS'];

requestsRouter.get('/:id/messages', async (req, res) => {
  const r = await loadForParticipant(req);
  const messages = await prisma.message.findMany({
    where: { requestId: r.id },
    orderBy: { createdAt: 'asc' },
    include: { sender: { select: { id: true, name: true, avatarUrl: true } } },
    take: 500,
  });
  res.json({ open: CHAT_OPEN.includes(r.status), messages });
});

requestsRouter.post('/:id/messages', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient && !r.isPro) throw forbidden();
  if (!CHAT_OPEN.includes(r.status)) throw conflict('El chat está cerrado para esta solicitud');
  const { content } = parse(z.object({ content: z.string().trim().min(1).max(2000) }), req.body);
  const msg = await prisma.message.create({
    data: { requestId: r.id, senderId: req.user!.id, content },
    include: { sender: { select: { id: true, name: true, avatarUrl: true } } },
  });
  emitToRequest(r.id, 'message:new', msg);
  const to = r.isClient ? r.professional.userId : r.clientId;
  emitToUser(to, 'message:new', msg);
  await notify(to, 'MESSAGE_NEW', `Nuevo mensaje de ${msg.sender.name}`, content.slice(0, 120), { requestId: r.id });
  res.status(201).json(msg);
});

requestsRouter.post('/:id/messages/read', async (req, res) => {
  const r = await loadForParticipant(req);
  const { count } = await prisma.message.updateMany({
    where: { requestId: r.id, senderId: { not: req.user!.id }, readAt: null },
    data: { readAt: new Date() },
  });
  res.json({ updated: count });
});

// ---------- Calificación (solo servicios realmente finalizados) ----------

requestsRouter.post('/:id/review', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isClient) throw forbidden('Solo el cliente que contrató puede calificar');
  if (r.status !== 'COMPLETED') throw conflict('Solo puedes calificar servicios finalizados');
  const body = parse(
    z.object({ rating: z.number().int().min(1).max(5), comment: z.string().trim().max(1000).optional() }),
    req.body,
  );
  const review = await prisma.$transaction(async (tx) => {
    const created = await tx.review.create({
      data: { requestId: r.id, authorId: req.user!.id, professionalId: r.professionalId, ...body },
    });
    const agg = await tx.review.aggregate({
      where: { professionalId: r.professionalId, hidden: false },
      _avg: { rating: true },
      _count: true,
    });
    const ratingAvg = Math.round((agg._avg.rating ?? 0) * 10) / 10;
    await tx.professionalProfile.update({
      where: { id: r.professionalId },
      data: { ratingAvg, ratingCount: agg._count },
    });
    return { created, ratingAvg, ratingCount: agg._count };
  });
  await checkQuality(r.professional.userId, review.ratingAvg, review.ratingCount, 'profesional');
  await notify(r.professional.userId, 'REVIEW_NEW', 'Recibiste una calificación', `Un cliente te calificó con ${body.rating} de 5 estrellas.`, { requestId: r.id });
  res.status(201).json(review.created);
});

/** El profesional califica al cliente (puntualidad, trato, pago) una vez finalizado el servicio. */
requestsRouter.post('/:id/client-review', async (req, res) => {
  const r = await loadForParticipant(req);
  if (!r.isPro) throw forbidden('Solo el profesional del servicio puede calificar al cliente');
  if (r.status !== 'COMPLETED') throw conflict('Solo puedes calificar al cliente de un servicio finalizado');
  const body = parse(
    z.object({ rating: z.number().int().min(1).max(5), comment: z.string().trim().max(1000).optional() }),
    req.body,
  );
  const review = await prisma.$transaction(async (tx) => {
    const created = await tx.clientReview.create({
      data: { requestId: r.id, authorId: req.user!.id, clientId: r.clientId, ...body },
    });
    const agg = await tx.clientReview.aggregate({ where: { clientId: r.clientId, hidden: false }, _avg: { rating: true }, _count: true });
    const ratingAvg = Math.round((agg._avg.rating ?? 0) * 10) / 10;
    await tx.user.update({
      where: { id: r.clientId },
      data: { clientRatingAvg: ratingAvg, clientRatingCount: agg._count },
    });
    return { created, ratingAvg, ratingCount: agg._count };
  });
  await checkQuality(r.clientId, review.ratingAvg, review.ratingCount, 'cliente');
  await notify(r.clientId, 'REVIEW_NEW', 'Te calificaron como cliente', `El profesional te calificó con ${body.rating} de 5 estrellas.`, { requestId: r.id });
  res.status(201).json(review.created);
});
