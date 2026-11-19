import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, notFound } from '../lib/errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { notify } from '../lib/notify.js';
import { claimInclude, resolveClaim, resolveSchema } from './claims.js';
import { getPromotions, promotionSchema, savePromotions } from './promotions.js';
import { baseSchema, currentSettings, saveSettings } from '../lib/settings.js';
import type { Prisma } from '@prisma/client';

// ---------- Notificaciones ----------
export const notificationsRouter = Router();
notificationsRouter.use(requireAuth);

notificationsRouter.get('/', async (req, res) => {
  const [items, unread] = await Promise.all([
    prisma.notification.findMany({ where: { userId: req.user!.id }, orderBy: { createdAt: 'desc' }, take: 100 }),
    prisma.notification.count({ where: { userId: req.user!.id, readAt: null } }),
  ]);
  res.json({ unread, items });
});

notificationsRouter.post('/read', async (req, res) => {
  const { ids } = parse(z.object({ ids: z.array(z.string()).optional() }), req.body ?? {});
  const r = await prisma.notification.updateMany({
    where: { userId: req.user!.id, readAt: null, id: ids ? { in: ids } : undefined },
    data: { readAt: new Date() },
  });
  res.json({ updated: r.count });
});

// ---------- Reseñas ----------
export const reviewsRouter = Router();

reviewsRouter.get('/professional/:professionalId', async (req, res) => {
  res.json(
    await prisma.review.findMany({
      where: { professionalId: req.params.professionalId, hidden: false },
      include: { author: { select: { name: true, avatarUrl: true } } },
      orderBy: { createdAt: 'desc' },
      take: 100,
    }),
  );
});

/**
 * Reseñas de un cliente (las dejan los profesionales). Las ven el mismo cliente y los
 * profesionales, para decidir si aceptan una solicitud.
 */
reviewsRouter.get('/client/:userId', requireAuth, async (req, res) => {
  const u = req.user!;
  const userId = req.params.userId as string;
  if (u.id !== userId && u.role === 'CLIENT') throw notFound('Reseñas no encontradas');
  const client = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, name: true, avatarUrl: true, role: true, clientRatingAvg: true, clientRatingCount: true },
  });
  if (!client || client.role !== 'CLIENT') throw notFound('Cliente no encontrado');
  const reviews = await prisma.clientReview.findMany({
    where: { clientId: userId, hidden: false },
    include: { author: { select: { name: true, avatarUrl: true } } },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  res.json({ client, reviews });
});

/** El profesional (o cualquier usuario) puede reportar una reseña para revisión del administrador. */
reviewsRouter.post('/:id/report', requireAuth, async (req, res) => {
  const { reason } = parse(z.object({ reason: z.string().trim().min(5).max(500) }), req.body);
  const r = await prisma.review.updateMany({ where: { id: req.params.id as string }, data: { reported: true, reportReason: reason } });
  if (!r.count) throw notFound('Reseña no encontrada');
  res.json({ ok: true });
});

// ---------- Administración ----------
export const adminRouter = Router();
adminRouter.use(requireAuth, requireRole('ADMIN'));

adminRouter.get('/stats', async (_req, res) => {
  const [users, pros, requests, payments, activeSubs] = await Promise.all([
    prisma.user.groupBy({ by: ['role'], _count: true }),
    prisma.professionalProfile.count(),
    prisma.serviceRequest.groupBy({ by: ['status'], _count: true }),
    prisma.payment.groupBy({
      by: ['kind'],
      where: { status: 'APPROVED' },
      _sum: { totalAmount: true, commissionAmount: true, serviceAmount: true },
      _count: true,
    }),
    prisma.subscription.count({ where: { status: 'ACTIVE', endsAt: { gte: new Date() } } }),
  ]);
  const [pendingVerifications, openClaims, underReview, reportedReviews, suspended] = await Promise.all([
    prisma.professionalProfile.count({ where: { verificationStatus: 'PENDING' } }),
    prisma.claim.count({ where: { status: { in: ['OPEN', 'IN_REVIEW'] } } }),
    prisma.user.count({ where: { underReview: true } }),
    prisma.review.count({ where: { reported: true, hidden: false } }),
    prisma.user.count({ where: { status: 'SUSPENDED' } }),
  ]);
  const sub = payments.find((p) => p.kind === 'SUBSCRIPTION');
  const srv = payments.find((p) => p.kind === 'SERVICE');
  const promo = payments.find((p) => p.kind === 'PROMOTION');
  res.json({
    pending: { verifications: pendingVerifications, claims: openClaims, underReview, reportedReviews, suspended },
    users: Object.fromEntries(users.map((u) => [u.role, u._count])),
    professionals: pros,
    activeSubscriptions: activeSubs,
    requests: Object.fromEntries(requests.map((r) => [r.status, r._count])),
    revenue: {
      commissions: srv?._sum.commissionAmount ?? 0,
      subscriptions: sub?._sum.totalAmount ?? 0,
      promotions: promo?._sum.totalAmount ?? 0,
      servicesVolume: srv?._sum.serviceAmount ?? 0,
    },
  });
});

adminRouter.get('/users', async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q : undefined;
  const filter = typeof req.query.filter === 'string' ? req.query.filter : undefined;
  res.json(
    await prisma.user.findMany({
      where: {
        ...(q ? { OR: [{ name: { contains: q, mode: 'insensitive' } }, { email: { contains: q, mode: 'insensitive' } }] } : {}),
        ...(filter === 'review' ? { underReview: true } : filter === 'suspended' ? { status: 'SUSPENDED' } : {}),
      },
      select: {
        id: true, name: true, email: true, role: true, status: true, city: true, createdAt: true, avatarUrl: true,
        underReview: true, reviewNote: true, suspendedUntil: true, suspensionReason: true,
        clientRatingAvg: true, clientRatingCount: true,
        professional: { select: { id: true, verified: true, verificationStatus: true, ratingAvg: true, ratingCount: true, featuredUntil: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 200,
    }),
  );
});

/**
 * Suspender (temporal con `days`, o indefinida), reactivar o sacar de revisión una cuenta.
 * Aplica igual a clientes y profesionales.
 */
adminRouter.patch('/users/:id', async (req, res) => {
  const b = parse(
    z.object({
      status: z.enum(['ACTIVE', 'SUSPENDED']).optional(),
      days: z.number().int().min(1).max(365).nullable().optional(),
      reason: z.string().trim().max(500).optional(),
      underReview: z.boolean().optional(),
    }),
    req.body,
  );
  const target = await prisma.user.findUnique({ where: { id: req.params.id as string }, select: { id: true, role: true } });
  if (!target) throw notFound('Usuario no encontrado');
  if (target.role === 'ADMIN' && b.status === 'SUSPENDED') throw badRequest('No se puede suspender a un administrador');
  const data: Record<string, unknown> = {};
  if (b.status === 'SUSPENDED') {
    data.status = 'SUSPENDED';
    data.suspendedUntil = b.days ? new Date(Date.now() + b.days * 864e5) : null;
    data.suspensionReason = b.reason ?? null;
  } else if (b.status === 'ACTIVE') {
    data.status = 'ACTIVE';
    data.suspendedUntil = null;
    data.suspensionReason = null;
  }
  if (b.underReview !== undefined) {
    data.underReview = b.underReview;
    if (!b.underReview) data.reviewNote = null;
    else if (b.reason) data.reviewNote = b.reason;
  }
  const user = await prisma.user.update({
    where: { id: target.id },
    data,
    select: { id: true, status: true, suspendedUntil: true, suspensionReason: true, underReview: true },
  });
  if (b.status === 'ACTIVE') await notify(target.id, 'ACCOUNT', 'Tu cuenta fue reactivada', 'Ya puedes volver a usar NetJob con normalidad.');
  res.json(user);
});

// ---- Verificación de identidad y antecedentes ----

adminRouter.get('/verifications', async (req, res) => {
  const status = z.enum(['PENDING', 'APPROVED', 'REJECTED']).catch('PENDING').parse(req.query.status);
  const now = new Date();
  const rows = await prisma.professionalProfile.findMany({
    where: { verificationStatus: status },
    select: {
      id: true, headline: true, city: true, verificationStatus: true, verificationNote: true,
      verificationSubmittedAt: true, verificationReviewedAt: true,
      idFrontFile: true, idBackFile: true, selfieFile: true, backgroundCheckFile: true, trainingPassedAt: true,
      user: { select: { id: true, name: true, email: true, phone: true, avatarUrl: true } },
      subscriptions: {
        where: { status: 'ACTIVE', endsAt: { gte: now } },
        select: { plan: { select: { name: true, verificationPriority: true } } },
        take: 1,
      },
    },
    orderBy: { verificationSubmittedAt: 'asc' },
    take: 200,
  });
  // Los planes con prioridad de verificación van primero en la cola
  const out = rows.map(({ subscriptions, ...r }) => ({
    ...r,
    plan: subscriptions[0]?.plan.name ?? null,
    priority: subscriptions[0]?.plan.verificationPriority ?? false,
  }));
  out.sort((a, b) => Number(b.priority) - Number(a.priority));
  res.json(out);
});

adminRouter.patch('/verifications/:professionalId', async (req, res) => {
  const b = parse(z.object({ approve: z.boolean(), note: z.string().trim().max(500).optional() }), req.body);
  const p = await prisma.professionalProfile.findUnique({ where: { id: req.params.professionalId as string } });
  if (!p) throw notFound('Profesional no encontrado');
  if (!b.approve && (!b.note || b.note.length < 5)) throw badRequest('Indica qué debe corregir el profesional (mín. 5 caracteres)');
  const updated = await prisma.professionalProfile.update({
    where: { id: p.id },
    data: {
      verificationStatus: b.approve ? 'APPROVED' : 'REJECTED',
      verified: b.approve,
      verificationNote: b.approve ? null : b.note,
      verificationReviewedAt: new Date(),
    },
    select: { id: true, verificationStatus: true, verified: true },
  });
  await notify(
    p.userId,
    'VERIFICATION',
    b.approve ? 'Identidad verificada' : 'Revisa tus documentos',
    b.approve
      ? 'Validamos tu identidad y tus antecedentes. Tu perfil ya muestra la insignia de verificado.'
      : `No pudimos validar tus documentos: ${b.note}. Súbelos de nuevo desde tu cuenta.`,
    undefined,
    { email: true },
  );
  res.json(updated);
});

// ---- Reclamaciones ----

adminRouter.get('/claims', async (req, res) => {
  const open = req.query.status !== 'closed';
  res.json(
    await prisma.claim.findMany({
      where: { status: { in: open ? ['OPEN', 'IN_REVIEW'] : ['RESOLVED', 'REJECTED'] } },
      include: claimInclude,
      orderBy: { createdAt: open ? 'asc' : 'desc' },
      take: 200,
    }),
  );
});

adminRouter.patch('/claims/:id', async (req, res) => {
  res.json(await resolveClaim(req.params.id as string, req.user!.id, parse(resolveSchema, req.body)));
});

// ---- Promociones y perfiles destacados ----

adminRouter.get('/promotions', async (_req, res) => {
  const [options, featured] = await Promise.all([
    getPromotions(),
    prisma.professionalProfile.findMany({
      where: { featuredUntil: { gt: new Date() } },
      select: { id: true, featuredUntil: true, city: true, user: { select: { name: true, avatarUrl: true } } },
      orderBy: { featuredUntil: 'desc' },
      take: 100,
    }),
  ]);
  res.json({ options, featured });
});

adminRouter.put('/promotions', async (req, res) => {
  const { options } = parse(z.object({ options: z.array(promotionSchema).min(1).max(6) }), req.body);
  res.json({ options: await savePromotions(options) });
});

adminRouter.patch('/professionals/:id', async (req, res) => {
  const b = parse(z.object({ verified: z.boolean().optional(), featuredUntil: z.coerce.date().nullable().optional() }), req.body);
  res.json(await prisma.professionalProfile.update({ where: { id: req.params.id as string }, data: b }));
});

const categorySchema = z.object({
  name: z.string().trim().min(2).max(60),
  slug: z.string().trim().regex(/^[a-z0-9-]+$/),
  icon: z.string().max(60).optional(),
  active: z.boolean().optional(),
  sortOrder: z.number().int().optional(),
});
adminRouter.get('/categories', async (_req, res) => {
  res.json(await prisma.category.findMany({ orderBy: { sortOrder: 'asc' } }));
});
adminRouter.post('/categories', async (req, res) => {
  res.status(201).json(await prisma.category.create({ data: parse(categorySchema, req.body) }));
});
adminRouter.patch('/categories/:id', async (req, res) => {
  res.json(await prisma.category.update({ where: { id: req.params.id as string }, data: parse(categorySchema.partial(), req.body) }));
});

adminRouter.get('/plans', async (_req, res) => {
  res.json(await prisma.subscriptionPlan.findMany({ orderBy: { sortOrder: 'asc' } }));
});
adminRouter.patch('/plans/:id', async (req, res) => {
  const b = parse(
    z.object({
      name: z.string().min(2).optional(),
      priceMonthly: z.number().int().positive().optional(),
      description: z.string().max(500).nullable().optional(),
      features: z.array(z.string().max(120)).max(20).optional(),
      maxServices: z.number().int().positive().nullable().optional(),
      maxPortfolio: z.number().int().positive().nullable().optional(),
      searchBoost: z.number().int().min(0).max(100).optional(),
      badge: z.string().trim().max(20).nullable().optional(),
      popular: z.boolean().optional(),
      hasStats: z.boolean().optional(),
      prioritySupport: z.boolean().optional(),
      featuredDays: z.number().int().min(0).max(30).optional(),
      recommendationPriority: z.boolean().optional(),
      verificationPriority: z.boolean().optional(),
      active: z.boolean().optional(),
    }),
    req.body,
  );
  res.json(await prisma.subscriptionPlan.update({ where: { id: req.params.id as string }, data: b }));
});

/** Pagos y transacciones con filtros, y los totales de lo filtrado (solo pagos aprobados). */
adminRouter.get('/payments', async (req, res) => {
  const q = parse(
    z.object({
      kind: z.enum(['DIAGNOSTIC', 'SERVICE', 'SUBSCRIPTION', 'PROMOTION']).optional(),
      status: z.enum(['PENDING', 'APPROVED', 'DECLINED', 'VOIDED', 'ERROR']).optional(),
      payout: z.enum(['NONE', 'HELD', 'RELEASED', 'REFUNDED']).optional(),
      q: z.string().trim().max(100).optional(),
      from: z.coerce.date().optional(),
      to: z.coerce.date().optional(),
    }),
    req.query,
  );
  const where: Prisma.PaymentWhereInput = {
    kind: q.kind,
    status: q.status,
    payoutStatus: q.payout,
    createdAt: q.from || q.to ? { gte: q.from, lt: q.to } : undefined,
    OR: q.q
      ? [
          { reference: { contains: q.q, mode: 'insensitive' } },
          { payer: { name: { contains: q.q, mode: 'insensitive' } } },
          { payer: { email: { contains: q.q, mode: 'insensitive' } } },
        ]
      : undefined,
  };
  const [items, totals, byKind, held] = await Promise.all([
    prisma.payment.findMany({
      where,
      select: {
        id: true, kind: true, reference: true, status: true, serviceAmount: true, commissionAmount: true,
        totalAmount: true, discountAmount: true, commissionRate: true, loyaltyApplied: true, paymentMethod: true,
        payoutStatus: true, payoutReleasedAt: true, createdAt: true, requestId: true,
        payer: { select: { name: true, email: true } },
        request: { select: { service: { select: { title: true } }, professional: { select: { user: { select: { name: true } } } } } },
      },
      orderBy: { createdAt: 'desc' },
      take: 300,
    }),
    prisma.payment.aggregate({
      where: { ...where, status: 'APPROVED' },
      _sum: { totalAmount: true, commissionAmount: true, serviceAmount: true },
      _count: true,
    }),
    prisma.payment.groupBy({ by: ['kind'], where: { ...where, status: 'APPROVED' }, _sum: { totalAmount: true, commissionAmount: true }, _count: true }),
    prisma.payment.aggregate({ where: { ...where, status: 'APPROVED', payoutStatus: 'HELD' }, _sum: { serviceAmount: true }, _count: true }),
  ]);
  res.json({
    items,
    totals: {
      approved: totals._count,
      collected: totals._sum.totalAmount ?? 0,
      commissions: totals._sum.commissionAmount ?? 0,
      held: held._sum.serviceAmount ?? 0,
      heldCount: held._count,
    },
    byKind: Object.fromEntries(byKind.map((k) => [k.kind, { count: k._count, total: k._sum.totalAmount ?? 0, commissions: k._sum.commissionAmount ?? 0 }])),
  });
});

// ---------- Configuración general ----------
adminRouter.get('/settings', (_req, res) => {
  res.json(currentSettings());
});

adminRouter.put('/settings', async (req, res) => {
  const patch = parse(baseSchema.partial(), req.body);
  try {
    res.json(await saveSettings(patch));
  } catch (e) {
    if (e instanceof z.ZodError) throw badRequest(e.issues.map((i) => i.message).join('. '));
    throw e;
  }
});

adminRouter.get('/reviews/reported', async (_req, res) => {
  res.json(
    await prisma.review.findMany({
      where: { reported: true },
      include: { author: { select: { name: true } }, professional: { select: { user: { select: { name: true } } } } },
      orderBy: { createdAt: 'desc' },
    }),
  );
});

adminRouter.patch('/reviews/:id', async (req, res) => {
  const b = parse(z.object({ hidden: z.boolean(), reported: z.boolean().optional() }), req.body);
  const review = await prisma.review.update({ where: { id: req.params.id as string }, data: b });
  const agg = await prisma.review.aggregate({ where: { professionalId: review.professionalId, hidden: false }, _avg: { rating: true }, _count: true });
  await prisma.professionalProfile.update({
    where: { id: review.professionalId },
    data: { ratingAvg: Math.round((agg._avg.rating ?? 0) * 10) / 10, ratingCount: agg._count },
  });
  res.json(review);
});
