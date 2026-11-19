import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { parse } from '../lib/validate.js';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { requireAuth } from '../middleware/auth.js';
import { computeServiceCharge } from '../lib/money.js';
import { applyGatewayResult, checkoutInfo, newReference } from '../lib/payments.js';
import { fetchTransaction, findTransactionByReference, verifyEventChecksum } from '../lib/wompi.js';
import { commissionFor } from '../lib/rewards.js';

export const paymentsRouter = Router();

const STATUSES = ['PENDING', 'APPROVED', 'DECLINED', 'VOIDED', 'ERROR'] as const;

/**
 * Webhook de Wompi (evento transaction.updated). Configurar en el panel de Wompi:
 *   {PUBLIC_URL}/payments/webhooks/wompi
 */
paymentsRouter.post('/webhooks/wompi', async (req, res) => {
  const event = req.body;
  if (!verifyEventChecksum(event)) {
    console.warn('[wompi] evento con firma inválida descartado');
    return res.status(401).json({ error: 'Firma inválida' });
  }
  const tx = event?.data?.transaction;
  if (event.event === 'transaction.updated' && tx?.reference) {
    const payment = await prisma.payment.findUnique({ where: { reference: tx.reference } });
    if (payment && STATUSES.includes(tx.status)) {
      await applyGatewayResult(payment.id, {
        status: tx.status,
        transactionId: tx.id,
        amountInCents: tx.amount_in_cents,
        method: tx.payment_method_type,
        raw: tx,
      });
    }
  }
  res.json({ ok: true }); // Wompi espera 200 para no reintentar
});

/** Página a la que Wompi redirige al terminar el checkout. */
paymentsRouter.get('/return', (req, res) => {
  const id = String(req.query.id ?? '').replace(/[^\w-]/g, '');
  res.type('html').send(`<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NetJob – Pago</title><body style="font-family:system-ui;text-align:center;padding:48px">
<h2>Estamos confirmando tu pago</h2><p>Vuelve a la app de NetJob para ver el resultado.</p>
<p style="color:#888;font-size:12px">Transacción: ${id || '—'}</p></body></html>`);
});

paymentsRouter.use(requireAuth);

/**
 * Inicia el siguiente pago pendiente de una solicitud aceptada:
 *   1. Visita de diagnóstico (valor que fija el profesional, sin comisión; se omite si es gratis).
 *   2. Después de la cotización del profesional: valor final + 3 % NetJob.
 */
paymentsRouter.post('/service/:requestId/checkout', async (req, res) => {
  const r = await prisma.serviceRequest.findUnique({ where: { id: req.params.requestId as string } });
  if (!r) throw notFound('Solicitud no encontrada');
  if (r.clientId !== req.user!.id) throw forbidden('Solo el cliente de la solicitud puede pagarla');
  if (r.status !== 'ACCEPTED') throw conflict('Solo puedes pagar una solicitud aceptada por el profesional');
  const approved = await prisma.payment.findMany({ where: { requestId: r.id, status: 'APPROVED' }, select: { kind: true } });
  // Visita gratis (valor 0): se pasa directo al pago del valor cotizado
  const kind = r.diagnosticFee === 0 || approved.some((p) => p.kind === 'DIAGNOSTIC') ? 'SERVICE' : 'DIAGNOSTIC';
  if (kind === 'SERVICE') {
    if (approved.some((p) => p.kind === 'SERVICE')) throw conflict('Esta solicitud ya fue pagada');
    if (!r.agreedPrice) throw conflict('El profesional aún no ha enviado la cotización del servicio');
  }

  // Los intentos anteriores sin terminar se anulan para que solo haya un checkout vigente
  await prisma.payment.updateMany({
    where: { requestId: r.id, kind, status: 'PENDING', gatewayTransactionId: null },
    data: { status: 'VOIDED' },
  });
  // Tarifa NetJob: 3 % normal, 1 % si el cliente tiene un beneficio (frecuente o referido)
  const fee = await commissionFor(req.user!.id);
  const charge =
    kind === 'DIAGNOSTIC'
      ? { serviceAmount: r.diagnosticFee, commissionAmount: 0, totalAmount: r.diagnosticFee }
      : computeServiceCharge(r.agreedPrice!, fee.rate);
  const payment = await prisma.payment.create({
    data: {
      kind,
      reference: newReference(kind === 'DIAGNOSTIC' ? 'DGN' : 'SRV'),
      payerId: req.user!.id,
      requestId: r.id,
      ...charge,
      commissionRate: kind === 'SERVICE' ? fee.rate : 0,
      loyaltyApplied: kind === 'SERVICE' && fee.reduced,
      discountNote: kind === 'SERVICE' && fee.reduced ? 'Tarifa reducida por cliente frecuente o referido' : null,
    },
  });
  const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id }, select: { email: true } });
  res.status(201).json({
    payment,
    charge,
    commission: { rate: kind === 'SERVICE' ? fee.rate : 0, standardRate: fee.standardRate, reduced: kind === 'SERVICE' && fee.reduced },
    ...checkoutInfo(payment, user.email),
  });
});

async function ownPayment(id: string, userId: string) {
  const p = await prisma.payment.findUnique({ where: { id } });
  if (!p || p.payerId !== userId) throw notFound('Pago no encontrado');
  return p;
}

/**
 * Confirma el resultado consultando a Wompi con el id de transacción que llega en el redirect.
 * Nunca se confía en el estado enviado por la app: siempre se consulta a la pasarela.
 */
paymentsRouter.post('/:id/confirm', async (req, res) => {
  const p = await ownPayment(req.params.id as string, req.user!.id);
  const { transactionId } = parse(z.object({ transactionId: z.string().min(3) }), req.body);
  const tx = await fetchTransaction(transactionId);
  if (tx.reference !== p.reference) throw badRequest('La transacción no corresponde a este pago');
  const updated = await applyGatewayResult(p.id, {
    status: tx.status,
    transactionId: tx.id,
    amountInCents: tx.amount_in_cents,
    method: tx.payment_method_type,
    raw: tx,
  });
  res.json(updated);
});

/**
 * Sincroniza un pago pendiente consultando a Wompi por su referencia. La app lo llama al
 * volver del checkout (el webhook también actualiza el pago; esto es un respaldo).
 */
paymentsRouter.post('/:id/sync', async (req, res) => {
  const p = await ownPayment(req.params.id as string, req.user!.id);
  if (p.status !== 'PENDING') return res.json(p);
  const tx = await findTransactionByReference(p.reference);
  if (!tx) return res.json(p);
  res.json(
    await applyGatewayResult(p.id, {
      status: tx.status,
      transactionId: tx.id,
      amountInCents: tx.amount_in_cents,
      method: tx.payment_method_type,
      raw: tx,
    }),
  );
});

/** Solo desarrollo (PAYMENTS_MOCK=true y sin llaves de Wompi): simula la respuesta de la pasarela. */
paymentsRouter.post('/:id/simulate', async (req, res) => {
  if (!config.paymentsMock) throw forbidden('Simulación de pagos deshabilitada');
  const p = await ownPayment(req.params.id as string, req.user!.id);
  const { status } = parse(z.object({ status: z.enum(['APPROVED', 'DECLINED']) }), req.body);
  res.json(
    await applyGatewayResult(p.id, {
      status,
      transactionId: `MOCK-${Date.now()}`,
      amountInCents: p.totalAmount * 100,
      method: 'MOCK',
    }),
  );
});

/**
 * Comprobante de pago: lo ven quien pagó, el profesional del servicio y el administrador.
 * No es una factura electrónica: es el soporte de la transacción dentro de NetJob.
 */
paymentsRouter.get('/:id/receipt', async (req, res) => {
  const p = await prisma.payment.findUnique({
    where: { id: req.params.id as string },
    include: {
      payer: { select: { name: true, email: true } },
      subscription: { select: { plan: { select: { name: true } }, startsAt: true, endsAt: true } },
      request: {
        select: {
          id: true, address: true, scheduledAt: true, warrantyUntil: true, status: true, quoteNote: true,
          service: { select: { title: true, category: { select: { name: true } } } },
          professional: { select: { userId: true, user: { select: { name: true } } } },
        },
      },
    },
  });
  if (!p) throw notFound('Pago no encontrado');
  const isPro = p.request?.professional.userId === req.user!.id;
  if (p.payerId !== req.user!.id && !isPro && req.user!.role !== 'ADMIN') throw notFound('Pago no encontrado');
  if (p.status !== 'APPROVED') throw conflict('El comprobante se genera cuando el pago está aprobado');
  const concept =
    p.kind === 'SUBSCRIPTION'
      ? `Suscripción ${p.subscription?.plan.name ?? ''} (30 días)`
      : p.kind === 'PROMOTION'
        ? `Perfil destacado por ${p.promoDays} días`
        : p.kind === 'DIAGNOSTIC'
          ? `Visita de diagnóstico · ${p.request?.service.title ?? ''}`
          : (p.request?.service.title ?? 'Servicio');
  res.json({
    number: p.reference,
    issuedAt: p.updatedAt,
    kind: p.kind,
    concept,
    payer: p.payer.name,
    payerEmail: p.payerId === req.user!.id || req.user!.role === 'ADMIN' ? p.payer.email : undefined,
    professional: p.request?.professional.user.name ?? null,
    category: p.request?.service.category.name ?? null,
    address: p.request?.address ?? null,
    scheduledAt: p.request?.scheduledAt ?? null,
    detail: p.kind === 'SERVICE' ? p.request?.quoteNote : null,
    // El profesional ve lo que recibe; la tarifa NetJob la paga el cliente
    lines: isPro
      ? [{ label: p.kind === 'DIAGNOSTIC' ? 'Visita de diagnóstico' : 'Valor del servicio', amount: p.serviceAmount }]
      : [
          { label: p.kind === 'SERVICE' ? 'Valor del servicio' : concept, amount: p.serviceAmount },
          ...(p.discountAmount > 0 ? [{ label: p.discountNote ?? 'Descuento', amount: -p.discountAmount }] : []),
          ...(p.kind === 'SERVICE'
            ? [{ label: `Tarifa NetJob (${Math.round((p.commissionRate ?? config.commissionRate) * 1000) / 10} %)`, amount: p.commissionAmount }]
            : []),
        ],
    total: isPro ? p.serviceAmount : p.totalAmount,
    note: p.loyaltyApplied ? p.discountNote : null,
    paymentMethod: p.paymentMethod,
    transactionId: p.gatewayTransactionId,
    payout:
      p.kind === 'SERVICE'
        ? { HELD: 'Retenido por NetJob hasta que ambas partes confirmen', RELEASED: 'Liberado al profesional', REFUNDED: 'Devuelto al cliente', NONE: '' }[p.payoutStatus]
        : null,
    warrantyUntil: p.kind === 'SERVICE' ? (p.request?.warrantyUntil ?? null) : null,
    warrantyDays: p.kind === 'SERVICE' ? config.warrantyDays : null,
    requestId: p.request?.id ?? null,
  });
});

paymentsRouter.get('/:id', async (req, res) => {
  const p = await prisma.payment.findUnique({
    where: { id: req.params.id as string },
    include: { request: { include: { professional: { select: { userId: true } } } } },
  });
  if (!p) throw notFound('Pago no encontrado');
  const allowed = p.payerId === req.user!.id || p.request?.professional.userId === req.user!.id || req.user!.role === 'ADMIN';
  if (!allowed) throw notFound('Pago no encontrado');
  const { gatewayResponse, ...safe } = p;
  res.json(safe);
});

/**
 * Historial: el cliente ve lo que pagó; el profesional ve los pagos de sus servicios
 * (valor del servicio, sin la comisión de NetJob) y sus pagos de suscripción.
 */
paymentsRouter.get('/', async (req, res) => {
  const u = req.user!;
  const select = {
    id: true, kind: true, reference: true, serviceAmount: true, commissionAmount: true, totalAmount: true,
    status: true, paymentMethod: true, createdAt: true, payoutStatus: true, payoutReleasedAt: true,
    commissionRate: true, loyaltyApplied: true, discountAmount: true, discountNote: true, promoDays: true,
    request: {
      select: {
        id: true,
        photos: true,
        service: { select: { title: true, category: { select: { name: true, icon: true } } } },
        client: { select: { name: true, avatarUrl: true } },
        professional: { select: { user: { select: { name: true, avatarUrl: true } } } },
      },
    },
    subscription: { select: { plan: { select: { name: true } } } },
  };
  const where =
    u.role === 'PROFESSIONAL'
      ? { OR: [{ payerId: u.id }, { kind: { in: ['SERVICE' as const, 'DIAGNOSTIC' as const] }, request: { professionalId: u.professionalId ?? '' } }] }
      : { payerId: u.id };
  res.json(await prisma.payment.findMany({ where, select, orderBy: { createdAt: 'desc' }, take: 200 }));
});
