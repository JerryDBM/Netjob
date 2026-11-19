/**
 * Datos iniciales: categorías, planes de suscripción y cuentas de demostración.
 * Contraseña de todas las cuentas demo: NetJob2026!
 */
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
import { demoImage } from './demo-images.js';

const prisma = new PrismaClient();
const DEMO_PASSWORD = 'NetJob2026!';

const categories = [
  ['Plomería', 'plomeria', 'plumbing'],
  ['Electricidad', 'electricidad', 'electrical_services'],
  ['Carpintería', 'carpinteria', 'carpenter'],
  ['Reparaciones y mantenimiento', 'reparaciones', 'build'],
  ['Instalaciones', 'instalaciones', 'handyman'],
  ['Servicios técnicos', 'servicios-tecnicos', 'devices'],
  ['Pintura', 'pintura', 'format_paint'],
  ['Cerrajería', 'cerrajeria', 'key'],
  ['Otros servicios', 'otros', 'more_horiz'],
] as const;

// Beneficios de cada plan. Los límites y las banderas los aplica el backend (no son solo texto)
// y todos son editables desde el panel de administración (/admin/plans).
const plans = [
  {
    code: 'BASIC', name: 'Básico', priceMonthly: 24_900, sortOrder: 1, maxServices: 3, maxPortfolio: 6, searchBoost: 0,
    badge: null, popular: false, hasStats: false, prioritySupport: false, featuredDays: 0, recommendationPriority: false, verificationPriority: false,
    description: 'Para empezar a recibir clientes en NetJob.',
    features: ['Perfil profesional público', 'Hasta 3 servicios publicados', 'Hasta 6 fotos de portafolio', 'Chat con clientes', 'Pagos dentro de la app'],
  },
  {
    code: 'INTERMEDIATE', name: 'Intermedio', priceMonthly: 44_900, sortOrder: 2, maxServices: 10, maxPortfolio: 20, searchBoost: 10,
    badge: 'Plus', popular: true, hasStats: true, prioritySupport: false, featuredDays: 0, recommendationPriority: false, verificationPriority: false,
    description: 'Más servicios y mejor posición en las búsquedas.',
    features: ['Todo lo del plan Básico', 'Hasta 10 servicios publicados', 'Hasta 20 fotos de portafolio', 'Prioridad media en resultados de búsqueda', 'Insignia Plus visible para los clientes', 'Estadísticas detalladas de ingresos'],
  },
  {
    code: 'PREMIUM', name: 'Premium', priceMonthly: 69_900, sortOrder: 3, maxServices: null, maxPortfolio: null, searchBoost: 25,
    badge: 'Premium', popular: false, hasStats: true, prioritySupport: true, featuredDays: 7, recommendationPriority: true, verificationPriority: true,
    description: 'Máxima visibilidad para crecer tu negocio.',
    features: ['Todo lo del plan Intermedio', 'Servicios y portafolio ilimitados', 'Máxima prioridad en búsquedas', 'Insignia Premium en el perfil', '7 días de perfil destacado cada mes', 'Primero en "Recomendados para ti"', 'Verificación de identidad prioritaria', 'Soporte prioritario por WhatsApp'],
  },
];

async function main() {
  for (const [i, [name, slug, icon]] of categories.entries()) {
    await prisma.category.upsert({ where: { slug }, update: { name, icon }, create: { name, slug, icon, sortOrder: i } });
  }
  for (const p of plans) {
    // Los beneficios se actualizan también en planes ya creados; el precio y los límites que
    // el admin haya cambiado se respetan.
    const { code, name, priceMonthly, sortOrder, maxServices, maxPortfolio, searchBoost, ...benefits } = p;
    await prisma.subscriptionPlan.upsert({ where: { code }, update: benefits, create: p });
  }

  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 10);
  const cat = Object.fromEntries((await prisma.category.findMany()).map((c) => [c.slug, c.id]));
  const planBy = Object.fromEntries((await prisma.subscriptionPlan.findMany()).map((p) => [p.code, p.id]));

  await prisma.user.upsert({
    where: { email: 'admin@netjob.co' },
    update: {},
    create: { email: 'admin@netjob.co', name: 'Administrador NetJob', role: 'ADMIN', passwordHash },
  });
  await prisma.user.upsert({
    where: { email: 'cliente@netjob.co' },
    update: {},
    create: { email: 'cliente@netjob.co', name: 'Laura Gómez', role: 'CLIENT', city: 'Bogotá', phone: '3001234567', passwordHash },
  });

  const pros = [
    {
      email: 'plomero@netjob.co', name: 'Carlos Rodríguez', plan: 'PREMIUM', city: 'Bogotá', lat: 4.676, lng: -74.048,
      headline: 'Plomero certificado con 12 años de experiencia', years: 12, rating: [5, 5, 4],
      bio: 'Reparo fugas, destapo cañerías e instalo griferías y calentadores. Trabajo limpio y garantizado.',
      area: 'Chapinero, Usaquén, Suba', cats: ['plomeria', 'instalaciones'],
      services: [
        ['plomeria', 'Reparación de fugas', 'Detección y reparación de fugas en tuberías, sanitarios y lavamanos.', 80_000, 'FIXED'],
        ['plomeria', 'Destape de cañerías', 'Destape de lavaplatos, sifones y desagües con equipo profesional.', 70_000, 'FIXED'],
        ['instalaciones', 'Instalación de calentador', 'Instalación de calentador de paso a gas o eléctrico.', 150_000, 'FIXED'],
      ],
    },
    {
      email: 'electricista@netjob.co', name: 'Andrés Martínez', plan: 'INTERMEDIATE', city: 'Bogotá', lat: 4.61, lng: -74.08,
      headline: 'Electricista residencial y comercial', years: 8, rating: [5, 4],
      bio: 'Instalaciones eléctricas, cambio de tableros, tomas e iluminación LED. Técnico con matrícula CONTE.',
      area: 'Teusaquillo, Chapinero, Centro', cats: ['electricidad'],
      services: [
        ['electricidad', 'Visita de diagnóstico eléctrico', 'Revisión de cortos, breakers que se disparan y fallas eléctricas.', 50_000, 'VISIT'],
        ['electricidad', 'Instalación de lámparas', 'Instalación de lámparas, apliques y luces LED.', 35_000, 'FIXED'],
      ],
    },
    {
      email: 'carpintero@netjob.co', name: 'María Fernanda López', plan: 'BASIC', city: 'Medellín', lat: 6.2442, lng: -75.5812,
      headline: 'Carpintería y muebles a la medida', years: 6, rating: [4],
      bio: 'Diseño y reparo muebles, closets y puertas. También hago pintura de interiores.',
      area: 'El Poblado, Laureles, Envigado', cats: ['carpinteria', 'pintura'],
      services: [
        ['carpinteria', 'Reparación de muebles', 'Ajuste de bisagras, cajones, puertas y reparación de muebles de madera.', 60_000, 'HOUR'],
        ['pintura', 'Pintura de habitación', 'Pintura de habitación estándar (hasta 12 m²), incluye resanes menores.', 250_000, 'FIXED'],
      ],
    },
  ] as const;

  const now = new Date();
  for (const p of pros) {
    const existing = await prisma.user.findUnique({ where: { email: p.email } });
    if (existing) continue;
    const user = await prisma.user.create({
      data: {
        email: p.email, name: p.name, role: 'PROFESSIONAL', city: p.city, passwordHash,
        professional: {
          create: {
            headline: p.headline, bio: p.bio, yearsExperience: p.years, city: p.city, coverageArea: p.area,
            lat: p.lat, lng: p.lng, coverageRadiusKm: 15, verified: true, verificationStatus: 'APPROVED',
            rulesAcceptedAt: now, trainingPassedAt: now, trainingScore: 25,
            ratingAvg: Math.round((p.rating.reduce((a, b) => a + b, 0) / p.rating.length) * 10) / 10,
            ratingCount: p.rating.length,
            categories: { connect: p.cats.map((c) => ({ id: cat[c] })) },
            availability: {
              create: [1, 2, 3, 4, 5].map((d) => ({ dayOfWeek: d, startTime: '08:00', endTime: '17:00' })).concat([{ dayOfWeek: 6, startTime: '08:00', endTime: '13:00' }]),
            },
            subscriptions: {
              create: { planId: planBy[p.plan], status: 'ACTIVE', startsAt: now, endsAt: new Date(now.getTime() + 30 * 864e5) },
            },
          },
        },
      },
      include: { professional: true },
    });
    for (const [c, title, description, price, unit] of p.services) {
      await prisma.service.create({
        data: {
          professionalId: user.professional!.id, categoryId: cat[c], title, description, price, priceUnit: unit,
          conditions: 'Materiales no incluidos salvo que se indique. Garantía de 30 días sobre la mano de obra.',
          coverageArea: p.area,
        },
      });
    }
  }
  // Las cuentas demo ya creadas quedan con la capacitación aprobada: sin ella no aparecen en búsquedas.
  await prisma.professionalProfile.updateMany({
    where: { trainingPassedAt: null, user: { email: { endsWith: '@netjob.co' } } },
    data: { rulesAcceptedAt: now, trainingPassedAt: now, trainingScore: 25 },
  });
  // La verificación es obligatoria para aparecer en búsquedas: las cuentas demo quedan verificadas
  await prisma.professionalProfile.updateMany({
    where: { user: { email: { endsWith: '@netjob.co' } }, verificationStatus: { in: ['NONE', 'APPROVED'] } },
    data: { verified: true, verificationStatus: 'APPROVED' },
  });

  // Las suscripciones demo duran 30 días: si ya vencieron, se renuevan con el mismo plan
  // para que las cuentas de demostración sigan apareciendo en las búsquedas.
  const demoPros = await prisma.professionalProfile.findMany({
    where: { user: { email: { endsWith: '@netjob.co' } }, subscriptions: { none: { status: 'ACTIVE', endsAt: { gte: now } } } },
    select: { id: true, subscriptions: { orderBy: { createdAt: 'desc' }, take: 1, select: { planId: true } } },
  });
  for (const d of demoPros) {
    await prisma.subscription.updateMany({ where: { professionalId: d.id, status: 'ACTIVE' }, data: { status: 'EXPIRED' } });
    await prisma.subscription.create({
      data: { professionalId: d.id, planId: d.subscriptions[0]?.planId ?? planBy.BASIC, status: 'ACTIVE', startsAt: now, endsAt: new Date(now.getTime() + 30 * 864e5) },
    });
  }

  // Los perfiles profesionales deben estar completos (foto y portafolio) para aparecer en búsquedas.
  const looks: Record<string, { colors: [[number, number, number], [number, number, number]]; works: string[] }> = {
    'plomero@netjob.co': { colors: [[37, 99, 235], [14, 165, 233]], works: ['Cambio de tubería de cocina', 'Instalación de calentador', 'Reparación de baño'] },
    'electricista@netjob.co': { colors: [[217, 119, 6], [250, 204, 21]], works: ['Tablero eléctrico nuevo', 'Iluminación LED en sala', 'Cableado de oficina'] },
    'carpintero@netjob.co': { colors: [[120, 53, 15], [217, 119, 6]], works: ['Closet a la medida', 'Restauración de comedor', 'Puerta principal'] },
  };
  for (const p of pros) {
    const user = await prisma.user.findUniqueOrThrow({ where: { email: p.email }, include: { professional: { include: { _count: { select: { portfolio: true } } } } } });
    const look = looks[p.email];
    const slug = p.email.split('@')[0];
    if (!user.avatarUrl) {
      await prisma.user.update({ where: { id: user.id }, data: { avatarUrl: demoImage(`demo-avatar-${slug}`, 256, 256, look.colors[0], look.colors[1]) } });
    }
    if (user.professional && user.professional._count.portfolio < look.works.length) {
      for (const [i, title] of look.works.entries()) {
        const [a, b] = look.colors;
        await prisma.portfolioItem.create({
          data: {
            professionalId: user.professional.id,
            title,
            imageUrl: demoImage(`demo-work-${slug}-${i}`, 480, 360, i % 2 ? b : a, i % 2 ? a : b),
          },
        });
      }
    }
  }

  console.log(`Seed listo. Cuentas demo (contraseña ${DEMO_PASSWORD}): cliente@netjob.co, plomero@netjob.co, electricista@netjob.co, carpintero@netjob.co, admin@netjob.co`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
