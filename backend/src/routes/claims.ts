import { Router } from 'express';
import { z } from 'zod';
import type { ClaimType } from '@prisma/client';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { requireAuth } from '../middleware/auth.js';
import { notify } from '../lib/notify.js';
import { emitToRequest } from '../lib/socket.js';
import { upload, storePublic } from '../lib/upload.js';
import { afterCompleted } from '../lib/completion.js';

/**
 * Reclamaciones entre cliente y profesional. Mientras una reclamación esté abierta, el
 * dinero del servicio sigue retenido; el administrador decide si se devuelve o se libera.
 */
export const claimsRouter = Router();
claimsRouter.use(requireAuth);

export const CLAIM_TYPES = ['QUALITY', 'NO_SHOW', 'EXTRA_CHARGE', 'BEHAVIOR', 'DAMAGE', 'WARRANTY', 'PAYMENT', 'OTHER'] as const;

export const CLAIM_LABEL: Record<ClaimType, string> = {
  QUALITY: 'Trabajo mal hecho o incompleto',
  NO_SHOW: 'No llegó o incumplió la cita',
  EXTRA_CHARGE: 'Cobros no pactados',
  BEHAVIOR: 'Conducta inapropiada',
  DAMAGE: 'Daños en el domicilio',
  WARRANTY: 'Garantía: el arreglo falló',
  PAYMENT: 'Problema con un pago o cancelación',
  OTHER: 'Otro motivo',
};

export const claimInclude = {
  openedBy: { select: { id: true, name: true, role: true, avatarUrl: true } },
  against: { select: { id: true, name: true, role: true, avatarUrl: true } },
  request: {
    select: {
      id: true, status: true, address: true, scheduledAt: true, agreedPrice: true, warrantyUntil: true,
      service: { select: { title: true } },
      payments: { where: { status: 'APPROVED' as const }, select: { kind: true, totalAmount: true, serviceAmount: true, payoutStatus: true } },
    },
  },
};

claimsRouter.post('/', async (req, res) => {
  const body = parse(
    z.object({
      requestId: z.string().min(1),
      type: z.enum(CLAIM_TYPES),
      description: z.string().trim().min(20, 'cuéntanos qué pasó con al menos 20 caracteres').max(3000),
    }),
    req.body,
  );
  const r = await prisma.serviceRequest.findUnique({
    where: { id: body.requestId },
    include: { professional: { select: { userId: true } }, service: { select: { title: true } } },
  });
  if (!r) throw notFound('Solicitud no encontrada');
  const isClient = r.clientId === req.user!.id;
  const isPro = r.professional.userId === req.user!.id;
  if (!isClient && !isPro) throw forbidden();
  if (!['ACCEPTED', 'IN_PROGRESS', 'COMPLETED'].includes(r.status)) {
    throw conflict('Solo se puede reclamar sobre una solicitud aceptada, en proceso o finalizada');
  }
  if (r.status === 'COMPLETED') {
    if (r.warrantyUntil && r.warrantyUntil < new Date()) throw conflict('El periodo de garantía de este servicio ya terminó');
  } else if (body.type === 'WARRANTY') {
    throw badRequest('La garantía aplica cuando el servicio ya está finalizado');
  }
  if (body.type === 'WARRANTY' && !isClient) throw forbidden('La garantía la solicita el cliente');
  const open = await prisma.claim.count({ where: { requestId: r.id, openedById: req.user!.id, status: { in: ['OPEN', 'IN_REVIEW'] } } });
  if (open) throw conflict('Ya tienes una reclamación abierta sobre esta solicitud');

  const againstId = isClient ? r.professional.userId : r.clientId;
  const claim = await prisma.claim.create({
    data: { ...body, openedById: req.user!.id, againstId },
    include: claimInclude,
  });
  await prisma.requestStatusHistory.create({
    data: { requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: req.user!.id, note: `Reclamación abierta: ${CLAIM_LABEL[body.type]}` },
  });
  await notify(
    againstId,
    'CLAIM',
    'Abrieron una reclamación',
    `${isClient ? 'El cliente' : 'El profesional'} abrió una reclamación sobre "${r.service.title}": ${CLAIM_LABEL[body.type]}. El equipo de NetJob la revisará y los contactará.`,
    { requestId: r.id, claimId: claim.id },
    { email: true },
  );
  const admins = await prisma.user.findMany({ where: { role: 'ADMIN' }, select: { id: true } });
  for (const a of admins) {
    await notify(a.id, 'CLAIM', 'Nueva reclamación', `${CLAIM_LABEL[body.type]} · "${r.service.title}"`, { claimId: claim.id });
  }
  emitToRequest(r.id, 'request:updated', { id: r.id });
  res.status(201).json(claim);
});

async function ownClaim(id: string, userId: string, role: string) {
  const c = await prisma.claim.findUnique({ where: { id }, include: claimInclude });
  if (!c) throw notFound('Reclamación no encontrada');
  if (role !== 'ADMIN' && c.openedById !== userId && c.againstId !== userId) throw notFound('Reclamación no encontrada');
  return c;
}

claimsRouter.post('/:id/photos', upload.array('files', 6), async (req, res) => {
  const c = await ownClaim(req.params.id as string, req.user!.id, req.user!.role);
  if (c.openedById !== req.user!.id) throw forbidden('Solo quien abrió la reclamación puede adjuntar fotos');
  const files = (req.files as Express.Multer.File[]) ?? [];
  if (!files.length) throw badRequest('Adjunta al menos una imagen en el campo "files"');
  const photos = [...c.photos, ...(await Promise.all(files.map(storePublic)))].slice(0, 10);
  res.json(await prisma.claim.update({ where: { id: c.id }, data: { photos }, include: claimInclude }));
});

/** Mis reclamaciones: las que abrí y las que me abrieron. */
claimsRouter.get('/', async (req, res) => {
  const requestId = typeof req.query.requestId === 'string' ? req.query.requestId : undefined;
  res.json(
    await prisma.claim.findMany({
      where: { requestId, OR: [{ openedById: req.user!.id }, { againstId: req.user!.id }] },
      include: claimInclude,
      orderBy: { createdAt: 'desc' },
      take: 100,
    }),
  );
});

claimsRouter.get('/:id', async (req, res) => {
  res.json(await ownClaim(req.params.id as string, req.user!.id, req.user!.role));
});

// ---------- Resolución (administrador) ----------

export const resolveSchema = z.object({
  status: z.enum(['IN_REVIEW', 'RESOLVED', 'REJECTED']),
  action: z.enum(['NONE', 'REFUND_CLIENT', 'RELEASE_PRO', 'WARRANTY_VISIT', 'INSURANCE']).default('NONE'),
  resolution: z.string().trim().max(2000).optional(),
});

const ACTION_TEXT = {
  NONE: '',
  REFUND_CLIENT: 'Se devuelve al cliente el valor del servicio que estaba retenido.',
  RELEASE_PRO: 'Se libera el pago al profesional y el servicio queda finalizado.',
  WARRANTY_VISIT: 'El profesional debe volver a revisar el trabajo sin costo, por garantía.',
  INSURANCE: 'El caso se remite a la aseguradora aliada para evaluar la cobertura.',
} as const;

export async function resolveClaim(claimId: string, adminId: string, input: z.infer<typeof resolveSchema>) {
  const c = await prisma.claim.findUnique({ where: { id: claimId }, include: { request: { include: { professional: { select: { userId: true } } } } } });
  if (!c) throw notFound('Reclamación no encontrada');
  if (c.status === 'RESOLVED' || c.status === 'REJECTED') throw conflict('Esta reclamación ya fue cerrada');
  const r = c.request;

  if (input.status === 'IN_REVIEW') {
    return prisma.claim.update({ where: { id: c.id }, data: { status: 'IN_REVIEW' }, include: claimInclude });
  }
  if (!input.resolution || input.resolution.length < 10) throw badRequest('Explica la decisión (mín. 10 caracteres)');
  const action = input.status === 'REJECTED' ? 'NONE' : input.action;

  if (action === 'REFUND_CLIENT') {
    const held = await prisma.payment.count({ where: { requestId: r.id, kind: 'SERVICE', status: 'APPROVED', payoutStatus: 'HELD' } });
    if (!held) throw conflict('No hay dinero retenido en esta solicitud: ya fue liberado o no se pagó. Elige otra acción.');
  }
  if (action === 'RELEASE_PRO' && r.status !== 'IN_PROGRESS') {
    throw conflict('Solo se puede liberar el pago de un servicio en proceso');
  }

  // Se cierra primero la reclamación: así deja de bloquear la finalización del servicio
  const updated = await prisma.claim.update({
    where: { id: c.id },
    data: { status: input.status, action, resolution: input.resolution, resolvedAt: new Date() },
    include: claimInclude,
  });

  if (action === 'REFUND_CLIENT') {
    await prisma.$transaction([
      prisma.payment.updateMany({
        where: { requestId: r.id, kind: 'SERVICE', status: 'APPROVED', payoutStatus: 'HELD' },
        data: { payoutStatus: 'REFUNDED', payoutReleasedAt: new Date() },
      }),
      prisma.serviceRequest.update({
        where: { id: r.id },
        data: { status: 'CANCELLED', cancelReason: 'Reclamación resuelta a favor del cliente', enRouteAt: null, proLat: null, proLng: null },
      }),
      prisma.requestStatusHistory.create({
        data: { requestId: r.id, fromStatus: r.status, toStatus: 'CANCELLED', changedById: adminId, note: 'Reclamación resuelta: devolución al cliente' },
      }),
    ]);
  } else if (action === 'RELEASE_PRO') {
    await prisma.$transaction([
      prisma.serviceRequest.update({ where: { id: r.id }, data: { status: 'COMPLETED' } }),
      prisma.requestStatusHistory.create({
        data: { requestId: r.id, fromStatus: r.status, toStatus: 'COMPLETED', changedById: adminId, note: 'Reclamación resuelta: pago liberado al profesional' },
      }),
    ]);
    await afterCompleted(r.id);
  } else {
    await prisma.requestStatusHistory.create({
      data: {
        requestId: r.id, fromStatus: r.status, toStatus: r.status, changedById: adminId,
        note: input.status === 'REJECTED' ? 'Reclamación cerrada sin cambios' : `Reclamación resuelta${action === 'NONE' ? '' : ': ' + ACTION_TEXT[action]}`,
      },
    });
  }

  const title = input.status === 'REJECTED' ? 'Reclamación cerrada' : 'Reclamación resuelta';
  const body = [ACTION_TEXT[action], input.resolution].filter(Boolean).join(' ');
  for (const uid of [c.openedById, c.againstId]) {
    await notify(uid, 'CLAIM', title, body, { requestId: r.id, claimId: c.id }, { email: true });
  }
  emitToRequest(r.id, 'request:updated', { id: r.id });
  return updated;
}
