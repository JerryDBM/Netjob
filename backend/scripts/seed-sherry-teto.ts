/**
 * Usuarios de prueba en Cartagena (contraseña 12345678):
 *  - teto123@gmail.com   → profesional con 3 servicios
 *  - sherry123@gmail.com → cliente con una solicitud a Teto pendiente de que Teto la confirme
 * Volver a ejecutarlo no duplica nada.
 *
 *   npm run demo:sherry-teto
 */
import fs from 'node:fs';
import path from 'node:path';
import bcrypt from 'bcryptjs';
import { prisma } from '../src/db.js';
import { ensureBuckets, storeBuffer } from '../src/lib/upload.js';
import { CARTAGENA } from './cartagena.js';

const DIR = path.resolve('prisma/demo-users');
const passwordHash = await bcrypt.hash('12345678', 10);
const cat = Object.fromEntries((await prisma.category.findMany()).map((c) => [c.slug, c.id]));
const basic = await prisma.subscriptionPlan.findUnique({ where: { code: 'BASIC' } });
if (!cat.otros || !basic) {
  console.error('Faltan categorías o planes. Ejecuta primero: npm run db:seed');
  process.exit(1);
}
await ensureBuckets();

async function avatar(email: string, file: string, type: string) {
  const existing = await prisma.user.findUnique({ where: { email } });
  return existing?.avatarUrl ?? (await storeBuffer(fs.readFileSync(path.join(DIR, file)), type, file));
}
const now = new Date();
const days = (n: number) => new Date(now.getTime() + n * 864e5);

// ---- Teto (profesional)
const tetoEmail = 'teto123@gmail.com';
const tetoData = {
  name: 'Teto', city: CARTAGENA.name, department: CARTAGENA.dept, phone: '3001234567',
  avatarUrl: await avatar(tetoEmail, 'teto.webp', 'image/webp'),
};
const teto = await prisma.user.upsert({
  where: { email: tetoEmail },
  update: { ...tetoData, role: 'PROFESSIONAL' },
  create: { ...tetoData, email: tetoEmail, role: 'PROFESSIONAL', passwordHash },
});
const profile = await prisma.professionalProfile.upsert({
  where: { userId: teto.id },
  update: {},
  create: {
    userId: teto.id,
    headline: 'Arreglos del hogar, limpieza y organización',
    bio: 'Soy Teto. Ayudo con arreglos pequeños, limpieza profunda y organización de espacios en Cartagena.',
    yearsExperience: 5, city: CARTAGENA.name, coverageArea: 'Manga, Bocagrande, Crespo y alrededores',
    lat: 10.411, lng: -75.534, diagnosticFee: 0,
    verified: true, verificationStatus: 'APPROVED', verificationSubmittedAt: days(-3), verificationReviewedAt: days(-2),
    rulesAcceptedAt: days(-3), trainingPassedAt: days(-3), trainingScore: 24, trainingAttempts: 1,
    categories: { connect: [{ id: cat.otros }, { id: cat.reparaciones }] },
    availability: { create: [1, 2, 3, 4, 5, 6].map((d) => ({ dayOfWeek: d, startTime: '08:00', endTime: '18:00' })) },
    subscriptions: { create: { planId: basic.id, status: 'ACTIVE', startsAt: days(-3), endsAt: days(120) } },
  },
});

const SERVICES = [
  { slug: 'otros', title: 'Limpieza profunda de apartamento', description: 'Limpieza completa de cocina, baños, pisos y ventanas.', price: 120_000, priceUnit: 'FIXED' as const },
  { slug: 'reparaciones', title: 'Arreglos menores del hogar', description: 'Ajuste de puertas, cambio de manijas, colgar cuadros y repisas.', price: 35_000, priceUnit: 'HOUR' as const },
  { slug: 'otros', title: 'Organización de closets y espacios', description: 'Ordeno closets, cocinas y bodegas con sistema de cajas y etiquetas.', price: 90_000, priceUnit: 'FIXED' as const },
];
const svcIds: string[] = [];
for (const s of SERVICES) {
  const found = await prisma.service.findFirst({ where: { professionalId: profile.id, title: s.title } });
  const { slug, ...rest } = s;
  const svc = found ?? (await prisma.service.create({
    data: { ...rest, professionalId: profile.id, categoryId: cat[slug], coverageArea: 'Cartagena', conditions: 'El valor final se confirma después de la visita.' },
  }));
  svcIds.push(svc.id);
}

// ---- Sherry (cliente)
const sherryEmail = 'sherry123@gmail.com';
const sherryData = {
  name: 'Sherry', city: CARTAGENA.name, department: CARTAGENA.dept, phone: '3007654321',
  avatarUrl: await avatar(sherryEmail, 'sherry.jpg', 'image/jpeg'),
};
const sherry = await prisma.user.upsert({
  where: { email: sherryEmail },
  update: sherryData,
  create: { ...sherryData, email: sherryEmail, role: 'CLIENT', passwordHash },
});

// ---- Solicitud pendiente: Teto debe aceptarla
const pending = await prisma.serviceRequest.findFirst({ where: { clientId: sherry.id, professionalId: profile.id, status: 'PENDING' } });
if (!pending) {
  const when = days(2);
  when.setUTCHours(15, 0, 0, 0); // 10:00 a. m. en Colombia
  const created = await prisma.serviceRequest.create({
    data: {
      clientId: sherry.id, professionalId: profile.id, serviceId: svcIds[0],
      description: 'Necesito una limpieza profunda del apartamento antes de una visita familiar.',
      address: 'Manga, Calle 27 #20-15, Cartagena', lat: 10.412, lng: -75.533,
      scheduledAt: when, status: 'PENDING', diagnosticFee: profile.diagnosticFee,
      history: { create: { toStatus: 'PENDING', changedById: sherry.id, note: 'Solicitud creada' } },
    },
  });
  await prisma.notification.create({
    data: { userId: teto.id, type: 'REQUEST_NEW', title: 'Nueva solicitud de servicio', body: 'Tienes una nueva solicitud para "Limpieza profunda de apartamento".', data: { requestId: created.id } },
  });
}
console.log('Listo: teto123@gmail.com y sherry123@gmail.com (contraseña 12345678). Solicitud de Sherry pendiente de Teto.');
await prisma.$disconnect();
