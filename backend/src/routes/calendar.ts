import { Router } from 'express';
import { z } from 'zod';
import type { Prisma } from '@prisma/client';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import { requireAuth, proId } from '../middleware/auth.js';
import { BLOCK_HOURS, bogotaDateTime } from '../lib/calendar.js';
import { requestStage } from './requests.js';

/**
 * Agenda de citas para clientes y profesionales: las solicitudes con fecha (pendientes,
 * aceptadas, en curso y finalizadas), las notas privadas de cada uno y, para el
 * profesional, sus bloqueos de agenda.
 */
export const calendarRouter = Router();
calendarRouter.use(requireAuth);

const DAY = 864e5;
const rangeSchema = z
  .object({
    from: z.coerce.date().optional(),
    to: z.coerce.date().optional(),
    // Por defecto no se muestran canceladas ni rechazadas
    all: z.enum(['true', 'false']).optional(),
  })
  .transform((q) => {
    const from = q.from ?? new Date(Date.now() - 31 * DAY);
    const to = q.to ?? new Date(from.getTime() + 93 * DAY);
    return { from, to, all: q.all === 'true' };
  })
  .refine((q) => q.to > q.from, 'el final del rango debe ser posterior al inicio')
  .refine((q) => q.to.getTime() - q.from.getTime() <= 200 * DAY, 'el rango máximo es de 200 días');

calendarRouter.get('/', async (req, res) => {
  const q = parse(rangeSchema, req.query);
  const u = req.user!;
  const who: Prisma.ServiceRequestWhereInput =
    u.role === 'PROFESSIONAL' ? { professionalId: u.professionalId ?? '__none__' } : u.role === 'CLIENT' ? { clientId: u.id } : { id: '__none__' };
  const rows = await prisma.serviceRequest.findMany({
    where: {
      ...who,
      status: q.all ? undefined : { in: ['PENDING', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED'] },
      // Una cita con propuesta de cambio aparece en su fecha actual y en la propuesta
      OR: [{ scheduledAt: { gte: q.from, lt: q.to } }, { rescheduleAt: { gte: q.from, lt: q.to } }],
    },
    include: {
      service: { select: { id: true, title: true, category: { select: { name: true, icon: true } } } },
      client: { select: { id: true, name: true, avatarUrl: true, phone: true } },
      professional: { select: { id: true, userId: true, user: { select: { name: true, avatarUrl: true } } } },
      payments: { where: { status: 'APPROVED' }, select: { kind: true } },
      notes: { where: { userId: u.id }, select: { note: true } },
    },
    orderBy: { scheduledAt: 'asc' },
    take: 500,
  });

  const isPro = u.role === 'PROFESSIONAL';
  const appointments = rows.map((r) => {
    const paid = r.payments.some((p) => p.kind === 'SERVICE');
    const diagnosticPaid = r.diagnosticFee === 0 || r.payments.some((p) => p.kind === 'DIAGNOSTIC');
    const counterpart = isPro
      ? { id: r.client.id, name: r.client.name, avatarUrl: r.client.avatarUrl, role: 'CLIENT' }
      : { id: r.professional.id, name: r.professional.user.name, avatarUrl: r.professional.user.avatarUrl, role: 'PROFESSIONAL' };
    return {
      id: r.id,
      status: r.status,
      stage: requestStage(r, diagnosticPaid, paid),
      scheduledAt: r.scheduledAt,
      endsAt: new Date(r.scheduledAt.getTime() + BLOCK_HOURS * 3600 * 1000),
      service: { id: r.service.id, title: r.service.title, category: r.service.category.name, icon: r.service.category.icon },
      description: r.description,
      additionalInfo: r.additionalInfo,
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      diagnosticFee: r.diagnosticFee,
      agreedPrice: r.agreedPrice,
      quoteNote: r.quoteNote,
      counterpart,
      myNote: r.notes[0]?.note ?? null,
      reschedule: r.rescheduleAt
        ? { at: r.rescheduleAt, byMe: r.rescheduleById === u.id, note: r.rescheduleNote }
        : null,
    };
  });

  const blocks = isPro
    ? await prisma.calendarBlock.findMany({
        where: { professionalId: u.professionalId ?? '__none__', startsAt: { lt: q.to }, endsAt: { gt: q.from } },
        orderBy: { startsAt: 'asc' },
      })
    : [];

  res.json({ from: q.from, to: q.to, appointments, blocks });
});

// ---------- Bloqueos de agenda (solo profesionales) ----------

calendarRouter.get('/blocks', async (req, res) => {
  const id = proId(req);
  res.json(
    await prisma.calendarBlock.findMany({
      where: { professionalId: id, endsAt: { gt: new Date() } },
      orderBy: { startsAt: 'asc' },
    }),
  );
});

calendarRouter.post('/blocks', async (req, res) => {
  const id = proId(req);
  const b = parse(
    z.object({
      startsAt: z.coerce.date(),
      endsAt: z.coerce.date(),
      reason: z.string().trim().max(200).optional(),
    }),
    req.body,
  );
  if (b.endsAt <= b.startsAt) throw badRequest('El final del bloqueo debe ser posterior al inicio');
  if (b.endsAt.getTime() < Date.now()) throw badRequest('El bloqueo ya pasó');
  if (b.endsAt.getTime() - b.startsAt.getTime() > 90 * DAY) throw badRequest('Un bloqueo puede durar máximo 90 días');
  // No se puede bloquear encima de citas ya aceptadas: primero hay que moverlas
  const taken = await prisma.serviceRequest.findFirst({
    where: { professionalId: id, status: { in: ['ACCEPTED', 'IN_PROGRESS'] }, scheduledAt: { gte: b.startsAt, lt: b.endsAt } },
    include: { service: { select: { title: true } } },
    orderBy: { scheduledAt: 'asc' },
  });
  if (taken) {
    throw conflict(`Tienes una cita aceptada el ${bogotaDateTime(taken.scheduledAt)} (${taken.service.title}). Reprográmala antes de bloquear ese rango.`);
  }
  const pending = await prisma.serviceRequest.count({
    where: { professionalId: id, status: 'PENDING', scheduledAt: { gte: b.startsAt, lt: b.endsAt } },
  });
  const block = await prisma.calendarBlock.create({ data: { professionalId: id, ...b } });
  res.status(201).json({ ...block, pendingInside: pending });
});

calendarRouter.delete('/blocks/:blockId', async (req, res) => {
  const id = proId(req);
  const r = await prisma.calendarBlock.deleteMany({ where: { id: req.params.blockId as string, professionalId: id } });
  if (!r.count) throw notFound('Bloqueo no encontrado');
  res.status(204).end();
});
