import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { forbidden, notFound } from '../lib/errors.js';
import { requireAuth, proId } from '../middleware/auth.js';
import { getActiveSubscription } from '../lib/subscriptions.js';
import { checkoutInfo, newReference } from '../lib/payments.js';

/**
 * Promoción y perfiles destacados: el profesional paga por aparecer primero en las
 * búsquedas de su zona. Los precios los administra el panel (/admin/promotions).
 */
export const promotionsRouter = Router();

export const promotionSchema = z.object({
  id: z.string().regex(/^[A-Z0-9_]{2,12}$/),
  label: z.string().trim().min(2).max(40),
  days: z.number().int().min(1).max(90),
  price: z.number().int().min(1000).max(5_000_000),
});
export type PromotionOption = z.infer<typeof promotionSchema>;

const DEFAULTS: PromotionOption[] = [
  { id: 'D7', label: '1 semana', days: 7, price: 14_900 },
  { id: 'D15', label: '15 días', days: 15, price: 24_900 },
  { id: 'D30', label: '1 mes', days: 30, price: 39_900 },
];

export async function getPromotions(): Promise<PromotionOption[]> {
  const s = await prisma.setting.findUnique({ where: { key: 'promotions' } });
  if (!s) return DEFAULTS;
  try {
    return z.array(promotionSchema).parse(JSON.parse(s.value));
  } catch {
    return DEFAULTS;
  }
}

export async function savePromotions(options: PromotionOption[]) {
  const value = JSON.stringify(options);
  await prisma.setting.upsert({ where: { key: 'promotions' }, update: { value }, create: { key: 'promotions', value } });
  return options;
}

promotionsRouter.use(requireAuth);

promotionsRouter.get('/', async (req, res) => {
  const id = proId(req);
  const [options, profile, sub] = await Promise.all([
    getPromotions(),
    prisma.professionalProfile.findUniqueOrThrow({ where: { id }, select: { featuredUntil: true } }),
    getActiveSubscription(id),
  ]);
  const now = new Date();
  res.json({
    options,
    featuredUntil: profile.featuredUntil && profile.featuredUntil > now ? profile.featuredUntil : null,
    includedDays: sub?.plan.featuredDays ?? 0,
    planName: sub?.plan.name ?? null,
  });
});

promotionsRouter.post('/checkout', async (req, res) => {
  const id = proId(req);
  const { optionId } = parse(z.object({ optionId: z.string().min(1) }), req.body);
  const option = (await getPromotions()).find((o) => o.id === optionId);
  if (!option) throw notFound('Promoción no encontrada');
  if (!(await getActiveSubscription(id))) throw forbidden('Necesitas una suscripción activa para destacar tu perfil');
  const payment = await prisma.payment.create({
    data: {
      kind: 'PROMOTION',
      reference: newReference('PRO'),
      payerId: req.user!.id,
      serviceAmount: option.price,
      totalAmount: option.price,
      promoDays: option.days,
    },
  });
  const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id }, select: { email: true } });
  res.status(201).json({ option, payment, ...checkoutInfo(payment, user.email) });
});
