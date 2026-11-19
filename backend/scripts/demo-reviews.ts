/**
 * Solo desarrollo: crea reseñas de ejemplo para los profesionales demo (@netjob.co) que
 * aún no tienen reseñas reales. Cada reseña sale de un servicio finalizado de un cliente
 * demo, como en la app. Luego recalcula el promedio con las reseñas reales.
 *
 *   npm run demo:reviews
 */
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

const clients = ['Daniela Herrera', 'Andrés Castillo', 'Paola Vergara', 'Julián Ortega', 'Marcela Ríos', 'Camilo Salgado'];
const comments: Record<number, string[]> = {
  5: [
    'Excelente trabajo, llegó puntual y dejó todo limpio. Lo recomiendo.',
    'Muy profesional, explicó qué tenía el daño antes de cobrar. Quedé feliz.',
    'Rápido y con buen precio. Ya lo guardé para la próxima.',
    'Súper amable y cuidadoso con la casa. 10 de 10.',
  ],
  4: [
    'Buen trabajo, solo se demoró un poco en llegar.',
    'Resolvió el problema, aunque tuvo que volver por un material.',
    'Cumplió con lo cotizado. Recomendado.',
  ],
  3: ['El trabajo quedó bien pero la comunicación pudo ser mejor.'],
  2: ['Tardó más de lo acordado.'],
  1: ['No quedé satisfecho con el resultado.'],
};

/** Notas que se acercan al promedio sembrado (p. ej. 4.7 → 5,5,5,4,5,4). */
function ratingsFor(avg: number, n: number): number[] {
  const out: number[] = [];
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const target = Math.round(avg * (i + 1) - sum);
    const r = Math.min(5, Math.max(1, target));
    out.push(r);
    sum += r;
  }
  return out;
}

const passwordHash = await bcrypt.hash('NetJob2026!', 10);
const authors = [];
for (const [i, name] of clients.entries()) {
  const email = `demo-cliente-${i + 1}@netjob.co`;
  authors.push(
    await prisma.user.upsert({
      where: { email },
      update: {},
      create: { email, name, role: 'CLIENT', passwordHash },
    }),
  );
}

const pros = await prisma.professionalProfile.findMany({
  where: { user: { email: { endsWith: '@netjob.co' } }, reviews: { none: {} } },
  include: { user: true, services: { where: { active: true }, take: 3 } },
});

let created = 0;
for (const p of pros) {
  if (!p.services.length) continue;
  const n = Math.min(Math.max(p.ratingCount, 3), 6);
  const ratings = ratingsFor(p.ratingAvg || 4.6, n);
  for (const [i, rating] of ratings.entries()) {
    const author = authors[i % authors.length];
    const service = p.services[i % p.services.length];
    const when = new Date(Date.now() - (i * 9 + 2) * 864e5);
    const request = await prisma.serviceRequest.create({
      data: {
        clientId: author.id,
        professionalId: p.id,
        serviceId: service.id,
        description: `Servicio de ${service.title.toLowerCase()}`,
        address: `${p.city ?? 'Ciudad'} (demo)`,
        scheduledAt: when,
        status: 'COMPLETED',
        agreedPrice: service.price,
        createdAt: when,
        history: {
          create: [
            { toStatus: 'PENDING', changedById: author.id, createdAt: when },
            { fromStatus: 'IN_PROGRESS', toStatus: 'COMPLETED', changedById: p.userId, createdAt: when },
          ],
        },
      },
    });
    const pool = comments[rating];
    await prisma.review.create({
      data: {
        requestId: request.id,
        authorId: author.id,
        professionalId: p.id,
        rating,
        comment: pool[i % pool.length],
        createdAt: new Date(when.getTime() + 3 * 3600e3),
      },
    });
    created++;
  }
  const agg = await prisma.review.aggregate({ where: { professionalId: p.id, hidden: false }, _avg: { rating: true }, _count: true });
  await prisma.professionalProfile.update({
    where: { id: p.id },
    data: { ratingAvg: Math.round((agg._avg.rating ?? 0) * 10) / 10, ratingCount: agg._count },
  });
  console.log(`${p.user.name}: ${ratings.join(', ')}`);
}
console.log(`${created} reseñas creadas`);

// ---- Reseñas de los profesionales a los clientes ----
const clientComments: Record<number, string[]> = {
  5: [
    'Muy amable, explicó bien el problema y pagó a tiempo.',
    'Excelente cliente, todo listo para trabajar cuando llegué.',
    'Puntual y respetuosa. Con gusto vuelvo a atenderla.',
  ],
  4: ['Buena comunicación, solo hubo que esperar un rato para entrar.', 'Todo bien, recomendado.'],
  3: ['Cambió el horario a última hora.'],
};

// Laura (cliente demo) también tiene servicios finalizados para ver su perfil como cliente
const laura = await prisma.user.findUnique({ where: { email: 'cliente@netjob.co' } });
if (laura && (await prisma.clientReview.count({ where: { clientId: laura.id } })) === 0) {
  const somePros = await prisma.professionalProfile.findMany({
    where: { user: { email: { endsWith: '@netjob.co' } }, services: { some: { active: true } } },
    include: { services: { where: { active: true }, take: 1 } },
    take: 4,
  });
  for (const [i, p] of somePros.entries()) {
    const when = new Date(Date.now() - (i * 11 + 5) * 864e5);
    await prisma.serviceRequest.create({
      data: {
        clientId: laura.id, professionalId: p.id, serviceId: p.services[0].id,
        description: `Servicio de ${p.services[0].title.toLowerCase()}`, address: 'Dirección demo',
        scheduledAt: when, status: 'COMPLETED', agreedPrice: p.services[0].price, createdAt: when,
        history: { create: [{ toStatus: 'COMPLETED', changedById: p.userId, createdAt: when }] },
      },
    });
  }
}

const pending = await prisma.serviceRequest.findMany({
  where: { status: 'COMPLETED', clientReview: null, client: { email: { endsWith: '@netjob.co' } } },
  include: { professional: { select: { userId: true } } },
});
const ratingsSeq = [5, 5, 4, 5, 5, 4, 5, 3];
for (const [i, r] of pending.entries()) {
  const rating = ratingsSeq[i % ratingsSeq.length];
  const pool = clientComments[rating];
  await prisma.clientReview.create({
    data: {
      requestId: r.id, authorId: r.professional.userId, clientId: r.clientId, rating,
      comment: pool[i % pool.length], createdAt: new Date(r.scheduledAt.getTime() + 4 * 3600e3),
    },
  });
}
const reviewedClients = [...new Set(pending.map((r) => r.clientId))];
for (const clientId of reviewedClients) {
  const agg = await prisma.clientReview.aggregate({ where: { clientId, hidden: false }, _avg: { rating: true }, _count: true });
  await prisma.user.update({
    where: { id: clientId },
    data: { clientRatingAvg: Math.round((agg._avg.rating ?? 0) * 10) / 10, clientRatingCount: agg._count },
  });
}
console.log(`${pending.length} reseñas a clientes creadas`);
await prisma.$disconnect();
