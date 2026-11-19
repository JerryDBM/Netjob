import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { conflict, notFound } from '../lib/errors.js';
import { requireAuth, proId } from '../middleware/auth.js';
import { getActiveSubscription, planUsage, planValue } from '../lib/subscriptions.js';
import { checkoutInfo, newReference } from '../lib/payments.js';
import { proPerformance } from '../lib/rewards.js';

export const subscriptionsRouter = Router();

/** Planes disponibles (público) para comparar características. */
subscriptionsRouter.get('/plans', async (_req, res) => {
  res.json(await prisma.subscriptionPlan.findMany({ where: { active: true }, orderBy: { sortOrder: 'asc' } }));
});

subscriptionsRouter.use(requireAuth);

/**
 * Estado de la suscripción del profesional, con todo lo que hace visibles los beneficios:
 * uso frente a los límites, lo que el plan le ha traído y el premio por buen desempeño.
 */
subscriptionsRouter.get('/me', async (req, res) => {
  const id = proId(req);
  const [active, history, usage, performance, profile] = await Promise.all([
    getActiveSubscription(id),
    prisma.subscription.findMany({
      where: { professionalId: id, status: { not: 'PENDING' } },
      include: { plan: { select: { name: true, priceMonthly: true } } },
      orderBy: { createdAt: 'desc' },
      take: 24,
    }),
    planUsage(id),
    proPerformance(id),
    prisma.professionalProfile.findUniqueOrThrow({ where: { id }, select: { featuredUntil: true } }),
  ]);
  const now = new Date();
  const daysLeft = active?.endsAt ? Math.max(0, Math.ceil((active.endsAt.getTime() - now.getTime()) / 864e5)) : null;
  res.json({
    active,
    history,
    usage,
    daysLeft,
    expiringSoon: daysLeft != null && daysLeft <= 5,
    value: active?.startsAt ? await planValue(id, active.startsAt) : null,
    performance,
    featuredUntil: profile.featuredUntil && profile.featuredUntil > now ? profile.featuredUntil : null,
  });
});

/** Seleccionar, renovar o cambiar de plan: crea la suscripción pendiente y su pago. */
subscriptionsRouter.post('/checkout', async (req, res) => {
  const id = proId(req);
  const { planId } = parse(z.object({ planId: z.string().min(1) }), req.body);
  const plan = await prisma.subscriptionPlan.findFirst({ where: { id: planId, active: true } });
  if (!plan) throw notFound('Plan no encontrado');

  // Al bajar de plan no se pueden exceder sus límites: primero hay que retirar lo que sobra
  const usage = await planUsage(id);
  if (plan.maxServices != null && usage.services.used > plan.maxServices) {
    throw conflict(`El plan ${plan.name} permite ${plan.maxServices} servicios y tienes ${usage.services.used} publicados. Retira algunos antes de cambiar.`);
  }

  // Premio por desempeño: calificación ≥ 4,8 y actividad reciente → 10 % o 12 % de descuento
  const perf = await proPerformance(id);
  const discountAmount = Math.round((plan.priceMonthly * perf.discountPct) / 100);

  // Limpia intentos previos que nunca se pagaron
  await prisma.subscription.updateMany({ where: { professionalId: id, status: 'PENDING' }, data: { status: 'CANCELLED' } });
  const sub = await prisma.subscription.create({ data: { professionalId: id, planId: plan.id } });
  const payment = await prisma.payment.create({
    data: {
      kind: 'SUBSCRIPTION',
      reference: newReference('SUB'),
      payerId: req.user!.id,
      subscriptionId: sub.id,
      serviceAmount: plan.priceMonthly,
      discountAmount,
      discountNote: discountAmount > 0 ? `Descuento del ${perf.discountPct} % por tu calificación y actividad` : null,
      totalAmount: plan.priceMonthly - discountAmount,
    },
  });
  const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id }, select: { email: true } });
  res.status(201).json({ subscription: sub, plan, payment, discountPct: perf.discountPct, ...checkoutInfo(payment, user.email) });
});
