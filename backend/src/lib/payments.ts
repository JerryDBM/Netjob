import crypto from 'node:crypto';
import type { Payment, PaymentStatus } from '@prisma/client';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { checkoutUrl, wompiConfigured } from './wompi.js';
import { notify } from './notify.js';
import { emitToRequest } from './socket.js';
import { rewardReferrer } from './rewards.js';

export function newReference(prefix: 'SRV' | 'DGN' | 'SUB' | 'PRO') {
  return `NJ-${prefix}-${Date.now().toString(36).toUpperCase()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
}

/** Datos que el cliente necesita para pagar: URL del Web Checkout o modo simulado en desarrollo. */
export function checkoutInfo(payment: Payment, email?: string) {
  if (wompiConfigured()) {
    return {
      mode: 'wompi' as const,
      checkoutUrl: checkoutUrl({
        reference: payment.reference,
        amountCop: payment.totalAmount,
        email,
        redirectUrl: `${config.paymentRedirectUrl}?paymentId=${payment.id}`,
      }),
    };
  }
  if (config.paymentsMock) return { mode: 'mock' as const, checkoutUrl: null };
  throw new Error('La pasarela de pagos no está configurada');
}

const FINAL: PaymentStatus[] = ['APPROVED', 'DECLINED', 'VOIDED', 'ERROR'];

/**
 * Aplica el resultado reportado por la pasarela. Es idempotente: un pago en estado
 * final no se vuelve a modificar. Valida que el monto coincida con lo registrado.
 */
export async function applyGatewayResult(
  paymentId: string,
  result: { status: PaymentStatus; transactionId?: string; amountInCents?: number; method?: string; raw?: unknown },
) {
  const payment = await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
  if (FINAL.includes(payment.status)) return payment;

  let status = result.status;
  if (result.amountInCents !== undefined && result.amountInCents !== payment.totalAmount * 100) {
    console.warn(`[pagos] monto no coincide para ${payment.reference}: ${result.amountInCents} vs ${payment.totalAmount * 100}`);
    status = 'ERROR';
  }
  if (status === 'PENDING') return payment;

  // Solo el dinero de servicios y visitas es del profesional: el servicio queda retenido
  // hasta la doble confirmación; la visita de diagnóstico se libera de una vez.
  const payout =
    status !== 'APPROVED'
      ? {}
      : payment.kind === 'SERVICE'
        ? { payoutStatus: 'HELD' as const }
        : payment.kind === 'DIAGNOSTIC'
          ? { payoutStatus: 'RELEASED' as const, payoutReleasedAt: new Date() }
          : {};
  const updated = await prisma.payment.update({
    where: { id: payment.id },
    data: {
      ...payout,
      status,
      gatewayTransactionId: result.transactionId ?? payment.gatewayTransactionId,
      paymentMethod: result.method ?? payment.paymentMethod,
      gatewayResponse: (result.raw ?? undefined) as any,
    },
  });

  if ((updated.kind === 'SERVICE' || updated.kind === 'DIAGNOSTIC') && updated.requestId) await onServicePayment(updated);
  if (updated.kind === 'SUBSCRIPTION' && updated.subscriptionId) await onSubscriptionPayment(updated);
  if (updated.kind === 'PROMOTION') await onPromotionPayment(updated);
  // El beneficio de tarifa reducida se consume cuando el pago queda aprobado
  if (updated.status === 'APPROVED' && updated.loyaltyApplied) {
    await prisma.user.updateMany({ where: { id: updated.payerId, commissionCredits: { gt: 0 } }, data: { commissionCredits: { decrement: 1 } } });
  }
  return updated;
}

const cop = (n: number) => `$${n.toLocaleString('es-CO')}`;

async function onServicePayment(p: Payment) {
  const r = await prisma.serviceRequest.findUniqueOrThrow({
    where: { id: p.requestId! },
    include: { professional: { select: { userId: true } }, service: { select: { title: true } } },
  });
  const data = { requestId: r.id, paymentId: p.id };
  if (p.status === 'APPROVED' && p.kind === 'DIAGNOSTIC') {
    await notify(p.payerId, 'PAYMENT', 'Visita de diagnóstico pagada', `Pagaste ${cop(p.totalAmount)} por la visita. El profesional irá a revisar y te enviará la cotización.`, data, { email: true });
    await notify(r.professional.userId, 'PAYMENT', 'Visita de diagnóstico confirmada', `El cliente pagó la visita de "${r.service.title}". Ve a diagnosticar y envía la cotización desde la app.`, data, { email: true });
  } else if (p.status === 'APPROVED') {
    await notify(p.payerId, 'PAYMENT', 'Pago confirmado', `Tu pago de ${cop(p.totalAmount)} por "${r.service.title}" fue aprobado.`, data, { email: true });
    await notify(r.professional.userId, 'PAYMENT', 'El cliente pagó el servicio', `Se confirmó el pago de "${r.service.title}". Tus ${cop(p.serviceAmount)} quedan retenidos por NetJob y se liberan cuando tú y el cliente confirmen que el trabajo terminó. Ya puedes iniciar.`, data, { email: true });
  } else {
    await notify(p.payerId, 'PAYMENT', 'Pago no aprobado', `Tu pago por "${r.service.title}" no fue aprobado. Puedes intentarlo de nuevo.`, { requestId: r.id, paymentId: p.id });
  }
  emitToRequest(r.id, 'request:updated', { id: r.id });
}

async function onSubscriptionPayment(p: Payment) {
  const sub = await prisma.subscription.findUniqueOrThrow({ where: { id: p.subscriptionId! }, include: { plan: true, professional: true } });
  if (p.status !== 'APPROVED') {
    await prisma.subscription.update({ where: { id: sub.id }, data: { status: 'CANCELLED' } });
    await notify(p.payerId, 'SUBSCRIPTION', 'Pago de suscripción no aprobado', `No se pudo activar el plan ${sub.plan.name}.`, { subscriptionId: sub.id });
    return;
  }
  const now = new Date();
  const days = config.subscriptionDays * 24 * 3600 * 1000;
  const current = await prisma.subscription.findFirst({
    where: { professionalId: sub.professionalId, status: 'ACTIVE', endsAt: { gte: now }, id: { not: sub.id } },
    orderBy: { endsAt: 'desc' },
  });
  // Renovación del mismo plan: se suma al tiempo restante. Cambio de plan: inicia hoy.
  const base = current && current.planId === sub.planId && current.endsAt ? current.endsAt : now;
  await prisma.$transaction([
    prisma.subscription.updateMany({
      where: { professionalId: sub.professionalId, status: 'ACTIVE', id: { not: sub.id } },
      data: { status: 'CANCELLED' },
    }),
    prisma.subscription.update({
      where: { id: sub.id },
      data: { status: 'ACTIVE', startsAt: now, endsAt: new Date(base.getTime() + days) },
    }),
  ]);
  // Beneficio del plan: días de perfil destacado incluidos en cada activación o renovación
  let extra = '';
  if (sub.plan.featuredDays > 0) {
    const from = sub.professional.featuredUntil && sub.professional.featuredUntil > now ? sub.professional.featuredUntil : now;
    await prisma.professionalProfile.update({
      where: { id: sub.professionalId },
      data: { featuredUntil: new Date(from.getTime() + sub.plan.featuredDays * 24 * 3600 * 1000) },
    });
    extra = ` Incluye ${sub.plan.featuredDays} días de perfil destacado.`;
  }
  await notify(p.payerId, 'SUBSCRIPTION', 'Suscripción activa', `Tu plan ${sub.plan.name} está activo. ¡Ya puedes recibir solicitudes!${extra}`, { subscriptionId: sub.id }, { email: true });

  // Referidos: la primera activación de un profesional invitado premia a quien lo invitó
  const payer = await prisma.user.findUnique({ where: { id: p.payerId }, select: { id: true, name: true, referredById: true, referralRewarded: true } });
  if (payer?.referredById && !payer.referralRewarded) {
    await prisma.user.update({ where: { id: payer.id }, data: { referralRewarded: true } });
    await rewardReferrer(payer.referredById, payer.name);
  }
}

/** Perfil destacado comprado: suma los días a la vigencia actual. */
async function onPromotionPayment(p: Payment) {
  if (p.status !== 'APPROVED' || !p.promoDays) return;
  const pro = await prisma.professionalProfile.findUnique({ where: { userId: p.payerId } });
  if (!pro) return;
  const now = new Date();
  const from = pro.featuredUntil && pro.featuredUntil > now ? pro.featuredUntil : now;
  const until = new Date(from.getTime() + p.promoDays * 24 * 3600 * 1000);
  await prisma.professionalProfile.update({ where: { id: pro.id }, data: { featuredUntil: until } });
  await notify(
    p.payerId,
    'SUBSCRIPTION',
    'Tu perfil está destacado',
    `Apareces primero en las búsquedas de tu zona hasta el ${until.toLocaleDateString('es-CO', { day: 'numeric', month: 'long', timeZone: 'America/Bogota' })}.`,
    { paymentId: p.id },
    { email: true },
  );
}
