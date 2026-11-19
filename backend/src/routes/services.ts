import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, forbidden, notFound, planRequired } from '../lib/errors.js';
import { requireAuth, proId } from '../middleware/auth.js';
import { getActiveSubscription } from '../lib/subscriptions.js';
import { upload, storePublic } from '../lib/upload.js';

export const servicesRouter = Router();

const serviceSchema = z.object({
  categoryId: z.string().min(1),
  title: z.string().trim().min(3).max(120),
  description: z.string().trim().min(10).max(2000),
  price: z.number().int().min(1000, 'el precio mínimo es $1.000').max(100_000_000),
  priceUnit: z.enum(['FIXED', 'HOUR', 'VISIT']).default('FIXED'),
  conditions: z.string().trim().max(1000).nullable().optional(),
  coverageArea: z.string().trim().max(300).nullable().optional(),
});

/** Detalle público de un servicio. */
servicesRouter.get('/:id', async (req, res) => {
  const s = await prisma.service.findFirst({
    where: { id: req.params.id, active: true },
    include: { category: true, professional: { include: { user: { select: { name: true, avatarUrl: true } } } } },
  });
  if (!s) throw notFound('Servicio no encontrado');
  res.json(s);
});

servicesRouter.use(requireAuth);

/** Servicios del profesional autenticado. */
servicesRouter.get('/', async (req, res) => {
  const id = proId(req);
  res.json(
    await prisma.service.findMany({
      where: { professionalId: id, active: true },
      include: { category: true },
      orderBy: { createdAt: 'asc' },
    }),
  );
});

servicesRouter.post('/', async (req, res) => {
  const id = proId(req);
  const body = parse(serviceSchema, req.body);
  const sub = await getActiveSubscription(id);
  if (!sub) throw forbidden('Necesitas una suscripción activa para publicar servicios');
  if (sub.plan.maxServices != null) {
    const count = await prisma.service.count({ where: { professionalId: id, active: true } });
    if (count >= sub.plan.maxServices) {
      throw planRequired(`Tu plan ${sub.plan.name} permite máximo ${sub.plan.maxServices} servicios publicados`);
    }
  }
  const category = await prisma.category.findFirst({ where: { id: body.categoryId, active: true } });
  if (!category) throw badRequest('Categoría inválida');

  const service = await prisma.service.create({
    data: {
      ...body,
      professionalId: id,
    },
    include: { category: true },
  });
  // La categoría del servicio queda asociada automáticamente a las especialidades del perfil
  await prisma.professionalProfile.update({
    where: { id },
    data: { categories: { connect: { id: body.categoryId } } },
  });
  res.status(201).json(service);
});

async function ownService(serviceId: string, professionalId: string) {
  const s = await prisma.service.findFirst({ where: { id: serviceId, professionalId, active: true } });
  if (!s) throw notFound('Servicio no encontrado');
  return s;
}

servicesRouter.patch('/:id', async (req, res) => {
  const id = proId(req);
  await ownService(req.params.id as string, id);
  const body = parse(serviceSchema.partial(), req.body);
  if (body.categoryId) {
    const category = await prisma.category.findFirst({ where: { id: body.categoryId, active: true } });
    if (!category) throw badRequest('Categoría inválida');
  }
  res.json(
    await prisma.service.update({ where: { id: req.params.id as string }, data: body, include: { category: true } }),
  );
});

/** Baja lógica: se conserva para el historial de solicitudes. */
servicesRouter.delete('/:id', async (req, res) => {
  const id = proId(req);
  await ownService(req.params.id as string, id);
  await prisma.service.update({ where: { id: req.params.id as string }, data: { active: false } });
  res.status(204).end();
});

servicesRouter.post('/:id/photos', upload.array('files', 6), async (req, res) => {
  const id = proId(req);
  const s = await ownService(req.params.id as string, id);
  const files = (req.files as Express.Multer.File[]) ?? [];
  if (!files.length) throw badRequest('Adjunta al menos una imagen en el campo "files"');
  const photos = [...s.photos, ...(await Promise.all(files.map(storePublic)))].slice(0, 10);
  res.json(await prisma.service.update({ where: { id: s.id }, data: { photos }, include: { category: true } }));
});
