import { prisma } from '../db.js';
import { notify } from './notify.js';

/**
 * Suscripción vigente de un profesional (con su plan). Marca como EXPIRED
 * las suscripciones activas cuya fecha de vencimiento ya pasó.
 */
export async function getActiveSubscription(professionalId: string) {
  const now = new Date();
  await prisma.subscription.updateMany({
    where: { professionalId, status: 'ACTIVE', endsAt: { lt: now } },
    data: { status: 'EXPIRED' },
  });
  return prisma.subscription.findFirst({
    where: { professionalId, status: 'ACTIVE', endsAt: { gte: now } },
    include: { plan: true },
    orderBy: { endsAt: 'desc' },
  });
}

/** Filtro Prisma: profesionales con suscripción activa y vigente. */
export const activeSubscriptionFilter = () => ({
  subscriptions: { some: { status: 'ACTIVE' as const, endsAt: { gte: new Date() } } },
});

/**
 * Uso frente a los límites del plan: "2 de 3 servicios", "5 de 6 fotos".
 * `max: null` significa ilimitado. Sin plan se muestran los límites del plan más pequeño.
 */
export async function planUsage(professionalId: string) {
  const [sub, services, portfolio, smallest] = await Promise.all([
    getActiveSubscription(professionalId),
    prisma.service.count({ where: { professionalId, active: true } }),
    prisma.portfolioItem.count({ where: { professionalId } }),
    prisma.subscriptionPlan.findFirst({ where: { active: true }, orderBy: { sortOrder: 'asc' } }),
  ]);
  const plan = sub?.plan ?? smallest;
  const item = (used: number, max: number | null | undefined) => ({
    used,
    max: max ?? null,
    reached: max != null && used >= max,
    near: max != null && used >= max - 1,
  });
  return { services: item(services, plan?.maxServices), portfolio: item(portfolio, plan?.maxPortfolio) };
}

/** Lo que el plan le ha traído al profesional desde que empezó el periodo actual. */
export async function planValue(professionalId: string, since: Date) {
  const [requests, completed, income, views] = await Promise.all([
    prisma.serviceRequest.count({ where: { professionalId, createdAt: { gte: since } } }),
    prisma.serviceRequest.count({ where: { professionalId, status: 'COMPLETED', updatedAt: { gte: since } } }),
    prisma.payment.aggregate({
      where: { status: 'APPROVED', kind: { in: ['SERVICE', 'DIAGNOSTIC'] }, payoutStatus: { not: 'REFUNDED' }, createdAt: { gte: since }, request: { professionalId } },
      _sum: { serviceAmount: true },
    }),
    prisma.profileView.count({ where: { professionalId, createdAt: { gte: since } } }),
  ]);
  return { since, requests, completed, income: income._sum.serviceAmount ?? 0, views };
}

const REMINDER_DAYS = 5;

/**
 * Avisos de renovación: una vez por suscripción, cuando faltan 5 días o menos.
 * Se ejecuta al arrancar el servidor y cada hora.
 */
export async function sendRenewalReminders() {
  const now = new Date();
  const soon = new Date(now.getTime() + REMINDER_DAYS * 864e5);
  const subs = await prisma.subscription.findMany({
    where: { status: 'ACTIVE', reminderSentAt: null, endsAt: { gte: now, lte: soon } },
    include: { plan: { select: { name: true } }, professional: { select: { userId: true } } },
    take: 500,
  });
  for (const s of subs) {
    const days = Math.max(1, Math.ceil((s.endsAt!.getTime() - now.getTime()) / 864e5));
    await prisma.subscription.update({ where: { id: s.id }, data: { reminderSentAt: now } });
    await notify(
      s.professional.userId,
      'SUBSCRIPTION',
      days === 1 ? 'Tu plan vence mañana' : `Tu plan vence en ${days} días`,
      `Renueva tu plan ${s.plan.name} para seguir apareciendo en las búsquedas y recibiendo solicitudes. Al renovar se suman 30 días a tu fecha actual.`,
      { subscriptionId: s.id, renew: true },
      { email: true },
    );
  }
  return subs.length;
}
