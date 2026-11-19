import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, notFound, planRequired } from '../lib/errors.js';
import { requireAuth, optionalAuth, proId } from '../middleware/auth.js';
import { distanceKm } from '../lib/geo.js';
import { activeSubscriptionFilter, getActiveSubscription, planUsage } from '../lib/subscriptions.js';
import { upload, storePublic } from '../lib/upload.js';
import type { Prisma } from '@prisma/client';
import { config } from '../config.js';
import { completeProfileFilter, profileMissing } from '../lib/profile.js';
import { availabilityStatus, inSchedule } from '../lib/availability.js';

export const professionalsRouter = Router();

const bool = z
  .union([z.boolean(), z.enum(['true', 'false', '1', '0'])])
  .transform((v) => v === true || v === 'true' || v === '1');

const searchSchema = z.object({
  q: z.string().trim().max(100).optional(),
  categoryId: z.string().optional(),
  city: z.string().trim().max(80).optional(),
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
  radiusKm: z.coerce.number().positive().optional(),
  minPrice: z.coerce.number().int().nonnegative().optional(),
  maxPrice: z.coerce.number().int().positive().optional(),
  minRating: z.coerce.number().min(0).max(5).optional(),
  available: bool.optional(),
  day: z.coerce.number().int().min(0).max(6).optional(),
  sort: z.enum(['relevance', 'rating', 'price', 'distance']).default('relevance'),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(50).default(20),
});

/** Puntos extra en el orden de búsqueda por el potenciador de recomendación. */
const BOOST_POINTS = 15;

type SearchFilters = z.infer<typeof searchSchema>;

/**
 * Profesionales alrededor de un punto. Solo aparecen quienes tienen suscripción vigente,
 * perfil completo (incluida la capacitación) y están a máximo SEARCH_RADIUS_KM (12 km).
 */
async function findNearby(f: SearchFilters, extra: Prisma.ProfessionalProfileWhereInput[] = []) {
  const now = new Date();
  const maxRadius = Math.min(f.radiusKm ?? config.searchRadiusKm, config.searchRadiusKm);

  const serviceWhere: Prisma.ServiceWhereInput = { active: true };
  if (f.categoryId) serviceWhere.categoryId = f.categoryId;
  if (f.minPrice !== undefined || f.maxPrice !== undefined) {
    serviceWhere.price = { gte: f.minPrice, lte: f.maxPrice };
  }

  const where: Prisma.ProfessionalProfileWhereInput = {
    user: { status: 'ACTIVE' },
    ...activeSubscriptionFilter(),
    ...completeProfileFilter(),
    services: { some: serviceWhere },
  };
  const and: Prisma.ProfessionalProfileWhereInput[] = [...extra];
  if (f.city) and.push({ city: { contains: f.city, mode: 'insensitive' } });
  if (f.minRating !== undefined) and.push({ ratingAvg: { gte: f.minRating } });
  if (f.available) and.push({ isAvailable: true, availability: { some: {} } });
  if (f.day !== undefined) and.push({ availability: { some: { dayOfWeek: f.day } } });
  if (f.q) {
    const c = { contains: f.q, mode: 'insensitive' as const };
    and.push({
      OR: [
        { headline: c },
        { bio: c },
        { user: { name: c } },
        { services: { some: { active: true, OR: [{ title: c }, { description: c }] } } },
        { categories: { some: { name: c } } },
      ],
    });
  }
  if (and.length) where.AND = and;

  const pros = await prisma.professionalProfile.findMany({
    where,
    include: {
      user: { select: { name: true, avatarUrl: true } },
      _count: { select: { portfolio: true } },
      availability: { select: { dayOfWeek: true, startTime: true, endTime: true } },
      categories: { select: { id: true, name: true } },
      services: { where: serviceWhere, select: { price: true, priceUnit: true } },
      subscriptions: {
        where: { status: 'ACTIVE', endsAt: { gte: now } },
        select: { plan: { select: { searchBoost: true, name: true, badge: true, recommendationPriority: true } } },
        orderBy: { endsAt: 'desc' },
        take: 1,
      },
    },
    take: 500,
  });

  const rows = pros
    .filter((p) => p._count.portfolio >= config.minPortfolio)
    .map((p) => {
      const distance = distanceKm(f.lat!, f.lng!, p.lat!, p.lng!);
      const plan = p.subscriptions[0]?.plan;
      const recommended = !!p.boostUntil && p.boostUntil > now;
      return {
        id: p.id,
        name: p.user.name,
        avatarUrl: p.user.avatarUrl,
        headline: p.headline,
        city: p.city,
        coverageArea: p.coverageArea,
        ratingAvg: p.ratingAvg,
        ratingCount: p.ratingCount,
        verified: p.verified,
        // Disponible = interruptor del profesional + dentro de su horario en este momento
        isAvailable: p.isAvailable && inSchedule(p.availability),
        featured: !!p.featuredUntil && p.featuredUntil > now,
        // Insignia del plan visible para el cliente ("Plus", "Premium") y potenciador ganado
        planBadge: plan?.badge ?? null,
        recommended,
        categories: p.categories,
        minPrice: Math.min(...p.services.map((s) => s.price)),
        diagnosticFee: Math.min(p.diagnosticFee, config.maxDiagnosticFee),
        servicesCount: p.services.length,
        distanceKm: Math.round(distance * 10) / 10,
        // Punto de la zona del profesional (≈100 m de precisión) para el mapa
        lat: Math.round(p.lat! * 1000) / 1000,
        lng: Math.round(p.lng! * 1000) / 1000,
        boost: (plan?.searchBoost ?? 0) + (recommended ? BOOST_POINTS : 0),
        recommendationPriority: plan?.recommendationPriority ?? false,
      };
    })
    .filter((r) => r.distanceKm <= maxRadius && (!f.available || r.isAvailable));
  return { rows, maxRadius };
}

type Row = Awaited<ReturnType<typeof findNearby>>['rows'][number];
const byRating = (a: Row, b: Row) => b.ratingAvg - a.ratingAvg || b.ratingCount - a.ratingCount;
/** Lo que no debe salir del backend: los pesos internos del orden. */
const publicRow = ({ boost, recommendationPriority, ...r }: Row) => r;

/**
 * Búsqueda de profesionales alrededor de la ubicación actual del cliente.
 * Orden por relevancia: destacados pagados, luego plan + potenciador, luego calificación.
 * Sin ubicación no se devuelve nadie.
 */
professionalsRouter.get('/', async (req, res) => {
  const f = parse(searchSchema, req.query);
  if (f.lat === undefined || f.lng === undefined) {
    const maxRadius = Math.min(f.radiusKm ?? config.searchRadiusKm, config.searchRadiusKm);
    return res.json({ total: 0, page: f.page, pageSize: f.pageSize, radiusKm: maxRadius, needsLocation: true, items: [] });
  }
  const { rows, maxRadius } = await findNearby(f);
  const sorters: Record<typeof f.sort, (a: Row, b: Row) => number> = {
    relevance: (a, b) => Number(b.featured) - Number(a.featured) || b.boost - a.boost || byRating(a, b),
    rating: byRating,
    price: (a, b) => a.minPrice - b.minPrice,
    distance: (a, b) => a.distanceKm - b.distanceKm,
  };
  rows.sort(sorters[f.sort]);

  res.json({
    total: rows.length,
    page: f.page,
    pageSize: f.pageSize,
    radiusKm: maxRadius,
    items: rows.slice((f.page - 1) * f.pageSize, f.page * f.pageSize).map(publicRow),
  });
});

/**
 * "Recomendados para ti": profesionales cercanos según lo que el cliente ya contrató.
 * Primero los que ya le trabajaron (para volver a contratarlos) y luego otros de las
 * mismas categorías; dentro de cada grupo, los planes con prioridad de recomendación.
 */
professionalsRouter.get('/recommended', requireAuth, async (req, res) => {
  const f = parse(searchSchema, req.query);
  if (req.user!.role !== 'CLIENT' || f.lat === undefined || f.lng === undefined) return res.json({ basedOn: [], items: [] });
  const past = await prisma.serviceRequest.findMany({
    where: { clientId: req.user!.id, status: 'COMPLETED' },
    select: { professionalId: true, service: { select: { categoryId: true, category: { select: { name: true } } } } },
    orderBy: { updatedAt: 'desc' },
    take: 30,
  });
  if (!past.length) return res.json({ basedOn: [], items: [] });
  const hired = new Set(past.map((p) => p.professionalId));
  const categoryIds = [...new Set(past.map((p) => p.service.categoryId))];
  const basedOn = [...new Set(past.map((p) => p.service.category.name))].slice(0, 3);
  const { rows } = await findNearby(f, [
    { OR: [{ id: { in: [...hired] } }, { services: { some: { active: true, categoryId: { in: categoryIds } } } }] },
  ]);
  rows.sort(
    (a, b) =>
      Number(hired.has(b.id)) - Number(hired.has(a.id)) ||
      Number(b.recommendationPriority) - Number(a.recommendationPriority) ||
      b.boost - a.boost ||
      byRating(a, b),
  );
  res.json({ basedOn, items: rows.slice(0, 8).map((r) => ({ ...publicRow(r), hiredBefore: hired.has(r.id) })) });
});

// ---------- Gestión del propio perfil (profesional) ----------
const me = Router();
me.use(requireAuth);

async function fullProfile(id: string) {
  const p = await prisma.professionalProfile.findUnique({
    where: { id },
    include: {
      user: { select: { id: true, name: true, avatarUrl: true, phone: true, city: true, createdAt: true } },
      categories: true,
      services: { where: { active: true }, include: { category: true }, orderBy: { createdAt: 'asc' } },
      portfolio: { orderBy: { createdAt: 'desc' } },
      availability: { orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }] },
    },
  });
  if (!p) throw notFound('Profesional no encontrado');
  return p;
}

/** Los nombres de archivo de los documentos de identidad nunca salen en el perfil. */
function withoutDocs<T extends Record<string, unknown>>(p: T) {
  const { idFrontFile, idBackFile, selfieFile, backgroundCheckFile, verificationNote, ...rest } = p;
  return rest;
}

async function ownProfile(id: string) {
  const [profile, subscription, missing, usage] = await Promise.all([fullProfile(id), getActiveSubscription(id), profileMissing(id), planUsage(id)]);
  return {
    ...withoutDocs(profile),
    verificationNote: profile.verificationNote,
    verificationRequired: config.requireVerification,
    subscription,
    missing,
    usage,
    minPortfolio: config.minPortfolio,
    maxDiagnosticFee: config.maxDiagnosticFee,
    availabilityNow: availabilityStatus(profile.availability, profile.isAvailable),
  };
}

me.get('/profile', async (req, res) => {
  res.json(await ownProfile(proId(req)));
});

me.patch('/profile', async (req, res) => {
  const id = proId(req);
  const b = parse(
    z.object({
      headline: z.string().trim().max(120).nullable().optional(),
      bio: z.string().trim().max(2000).nullable().optional(),
      yearsExperience: z.number().int().min(0).max(70).optional(),
      city: z.string().trim().max(80).nullable().optional(),
      coverageArea: z.string().trim().max(300).nullable().optional(),
      lat: z.number().min(-90).max(90).nullable().optional(),
      lng: z.number().min(-180).max(180).nullable().optional(),
      coverageRadiusKm: z.number().int().min(1).max(200).optional(),
      isAvailable: z.boolean().optional(),
      categoryIds: z.array(z.string()).max(10).optional(),
      diagnosticFee: z.number().int().min(0, 'el valor no puede ser negativo').optional(),
    }),
    req.body,
  );
  if (b.diagnosticFee !== undefined && b.diagnosticFee > config.maxDiagnosticFee) {
    throw badRequest(`La visita de diagnóstico puede costar máximo $${config.maxDiagnosticFee.toLocaleString('es-CO')}`);
  }
  if (b.diagnosticFee !== undefined && b.diagnosticFee > 0 && b.diagnosticFee < 1000) {
    throw badRequest('Si cobras la visita, el valor mínimo es $1.000 (o déjala en $0 para que sea gratis)');
  }
  const { categoryIds, ...data } = b;
  await prisma.professionalProfile.update({
    where: { id },
    data: { ...data, categories: categoryIds ? { set: categoryIds.map((cid) => ({ id: cid })) } : undefined },
  });
  res.json(await ownProfile(id));
});

const hhmm = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'formato HH:mm');
me.put('/availability', async (req, res) => {
  const id = proId(req);
  const { slots } = parse(
    z.object({
      slots: z
        .array(z.object({ dayOfWeek: z.number().int().min(0).max(6), startTime: hhmm, endTime: hhmm }))
        .max(50)
        .refine((s) => s.every((x) => x.startTime < x.endTime), 'la hora de inicio debe ser menor que la de fin'),
    }),
    req.body,
  );
  await prisma.$transaction([
    prisma.availabilitySlot.deleteMany({ where: { professionalId: id } }),
    prisma.availabilitySlot.createMany({ data: slots.map((s) => ({ ...s, professionalId: id })) }),
  ]);
  res.json(
    await prisma.availabilitySlot.findMany({
      where: { professionalId: id },
      orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }],
    }),
  );
});

me.post('/portfolio', upload.single('file'), async (req, res) => {
  const id = proId(req);
  if (!req.file) throw badRequest('Adjunta una imagen en el campo "file"');
  const b = parse(
    z.object({ title: z.string().trim().min(2).max(120), description: z.string().trim().max(500).optional() }),
    req.body,
  );
  // Antes de suscribirse, el profesional puede subir hasta el límite del plan más pequeño
  // (las fotos son obligatorias para completar el perfil).
  const sub = await getActiveSubscription(id);
  const limit = sub
    ? sub.plan.maxPortfolio
    : ((await prisma.subscriptionPlan.aggregate({ where: { active: true }, _min: { maxPortfolio: true } }))._min.maxPortfolio ?? 6);
  if (limit != null) {
    const count = await prisma.portfolioItem.count({ where: { professionalId: id } });
    if (count >= limit) {
      throw planRequired(sub ? `Tu plan ${sub.plan.name} permite máximo ${limit} fotos en el portafolio` : `Puedes subir hasta ${limit} fotos; con un plan superior puedes subir más`);
    }
  }
  const item = await prisma.portfolioItem.create({
    data: { professionalId: id, title: b.title, description: b.description, imageUrl: await storePublic(req.file) },
  });
  res.status(201).json(item);
});

me.delete('/portfolio/:itemId', async (req, res) => {
  const id = proId(req);
  const r = await prisma.portfolioItem.deleteMany({ where: { id: req.params.itemId, professionalId: id } });
  if (!r.count) throw notFound();
  res.status(204).end();
});

/** Resumen para el panel del profesional: solicitudes por estado, ingresos y calificación. */
me.get('/stats', async (req, res) => {
  const id = proId(req);
  const base = { kind: { in: ['SERVICE' as const, 'DIAGNOSTIC' as const] }, status: 'APPROVED' as const, request: { professionalId: id } };
  const [byStatus, income, held, profile] = await Promise.all([
    prisma.serviceRequest.groupBy({ by: ['status'], where: { professionalId: id }, _count: true }),
    prisma.payment.aggregate({ where: { ...base, payoutStatus: 'RELEASED' }, _sum: { serviceAmount: true }, _count: true }),
    prisma.payment.aggregate({ where: { ...base, payoutStatus: 'HELD' }, _sum: { serviceAmount: true }, _count: true }),
    prisma.professionalProfile.findUniqueOrThrow({ where: { id }, select: { ratingAvg: true, ratingCount: true } }),
  ]);
  res.json({
    requests: Object.fromEntries(byStatus.map((s) => [s.status, s._count])),
    income: {
      total: income._sum.serviceAmount ?? 0,
      payments: income._count,
      held: held._sum.serviceAmount ?? 0,
      heldPayments: held._count,
    },
    rating: profile,
  });
});

/**
 * Estadísticas detalladas de ingresos (beneficio de los planes con `hasStats`):
 * ingresos por mes, servicios más contratados, conversión de solicitudes y visitas al perfil.
 */
me.get('/insights', async (req, res) => {
  const id = proId(req);
  const sub = await getActiveSubscription(id);
  if (!sub?.plan.hasStats) {
    throw planRequired('Las estadísticas detalladas de ingresos están incluidas desde el plan Intermedio.', 'PLAN_REQUIRED');
  }
  const since = new Date();
  since.setUTCDate(1);
  since.setUTCHours(0, 0, 0, 0);
  since.setUTCMonth(since.getUTCMonth() - 5);
  const [payments, requests, views] = await Promise.all([
    prisma.payment.findMany({
      where: { status: 'APPROVED', kind: { in: ['SERVICE', 'DIAGNOSTIC'] }, payoutStatus: { not: 'REFUNDED' }, createdAt: { gte: since }, request: { professionalId: id } },
      select: { serviceAmount: true, createdAt: true, kind: true, request: { select: { service: { select: { title: true } } } } },
    }),
    prisma.serviceRequest.groupBy({ by: ['status'], where: { professionalId: id, createdAt: { gte: since } }, _count: true }),
    prisma.profileView.count({ where: { professionalId: id, createdAt: { gte: since } } }),
  ]);
  const months: { key: string; income: number; payments: number }[] = [];
  for (let i = 0; i < 6; i++) {
    const d = new Date(since);
    d.setUTCMonth(since.getUTCMonth() + i);
    months.push({ key: d.toISOString().slice(0, 7), income: 0, payments: 0 });
  }
  const byService = new Map<string, { title: string; income: number; count: number }>();
  for (const p of payments) {
    const m = months.find((x) => x.key === p.createdAt.toISOString().slice(0, 7));
    if (m) {
      m.income += p.serviceAmount;
      m.payments += 1;
    }
    if (p.kind === 'SERVICE') {
      const title = p.request?.service.title ?? 'Servicio';
      const s = byService.get(title) ?? { title, income: 0, count: 0 };
      s.income += p.serviceAmount;
      s.count += 1;
      byService.set(title, s);
    }
  }
  const count = (st: string) => requests.find((r) => r.status === st)?._count ?? 0;
  const received = requests.reduce((n, r) => n + r._count, 0);
  const won = count('COMPLETED') + count('IN_PROGRESS') + count('ACCEPTED');
  res.json({
    months,
    topServices: [...byService.values()].sort((a, b) => b.income - a.income).slice(0, 5),
    requests: { received, won, completed: count('COMPLETED'), rejected: count('REJECTED'), cancelled: count('CANCELLED') },
    conversion: received ? Math.round((won / received) * 100) : 0,
    views,
    total: payments.reduce((n, p) => n + p.serviceAmount, 0),
  });
});

professionalsRouter.use('/me', me);

/** Perfil público de un profesional. */
professionalsRouter.get('/:id', optionalAuth, async (req, res) => {
  const profile = await fullProfile(req.params.id as string);
  // Visitas de clientes: alimentan "lo que tu plan te trajo" (no cuenta el propio profesional)
  if (req.user?.role === 'CLIENT') {
    await prisma.profileView.create({ data: { professionalId: profile.id } }).catch((e) => console.error('[visitas]', e));
  }
  const now = new Date();
  const [reviews, sub, blocks] = await Promise.all([
    prisma.review.findMany({
      where: { professionalId: profile.id, hidden: false },
      include: { author: { select: { name: true, avatarUrl: true } } },
      orderBy: { createdAt: 'desc' },
      take: 30,
    }),
    getActiveSubscription(profile.id),
    // Días sin agenda (sin el motivo, que es privado) para que el cliente elija otra fecha
    prisma.calendarBlock.findMany({
      where: { professionalId: profile.id, endsAt: { gt: now }, startsAt: { lt: new Date(now.getTime() + 90 * 864e5) } },
      select: { startsAt: true, endsAt: true },
      orderBy: { startsAt: 'asc' },
    }),
  ]);
  const { phone, ...user } = profile.user; // el teléfono no se expone públicamente
  res.json({
    ...withoutDocs(profile),
    user,
    reviews,
    blocks,
    diagnosticFee: Math.min(profile.diagnosticFee, config.maxDiagnosticFee),
    featured: !!profile.featuredUntil && profile.featuredUntil > new Date(),
    recommended: !!profile.boostUntil && profile.boostUntil > new Date(),
    trained: !!profile.trainingPassedAt,
    plan: sub ? sub.plan.name : null,
    planBadge: sub?.plan.badge ?? null,
    canReceiveRequests: !!sub && (!config.requireVerification || profile.verified),
    availabilityNow: availabilityStatus(profile.availability, profile.isAvailable),
    isAvailable: profile.isAvailable && inSchedule(profile.availability),
  });
});
