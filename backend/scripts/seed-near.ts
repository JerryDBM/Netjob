/**
 * Solo desarrollo: crea profesionales demo completos (foto, portafolio, horarios,
 * servicios y plan activo) alrededor de un punto, a entre 1 y 9 km.
 *
 *   npm run demo:seed-near -- 9.7174 -75.1202 "El Carmen de Bolívar" carmen
 *
 * El último argumento es un prefijo para los correos (demo-<prefijo>-1@netjob.co…).
 * Contraseña de las cuentas: NetJob2026!  Volver a ejecutarlo no duplica cuentas.
 */
import { PrismaClient, type PriceUnit } from '@prisma/client';
import bcrypt from 'bcryptjs';
import { demoImage } from '../prisma/demo-images.js';

const [latArg, lngArg, city = 'Mi ciudad', prefix = 'local'] = process.argv.slice(2);
const lat = Number(latArg);
const lng = Number(lngArg);
if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
  console.error('Uso: npm run demo:seed-near -- <lat> <lng> "Ciudad" prefijo');
  process.exit(1);
}

type Svc = [slug: string, title: string, description: string, price: number, unit: PriceUnit];
const people: {
  name: string; plan: string; km: number; angle: number; years: number; headline: string; bio: string;
  cats: string[]; colors: [[number, number, number], [number, number, number]]; works: string[]; services: Svc[];
}[] = [
  {
    name: 'José Luis Pérez', plan: 'PREMIUM', km: 1.2, angle: 30, years: 15,
    headline: 'Plomero y técnico en redes hidráulicas', bio: 'Arreglo fugas, tanques, bombas de agua y baños completos. Atiendo urgencias.',
    cats: ['plomeria', 'instalaciones'], colors: [[2, 132, 199], [56, 189, 248]],
    works: ['Instalación de tanque elevado', 'Baño remodelado', 'Cambio de tubería'],
    services: [
      ['plomeria', 'Reparación de fugas y goteras', 'Detección y arreglo de fugas en tuberías, llaves y sanitarios.', 40_000, 'FIXED'],
      ['instalaciones', 'Instalación de bomba de agua', 'Instalación y conexión de bombas y tanques.', 120_000, 'FIXED'],
    ],
  },
  {
    name: 'Yesenia Arrieta', plan: 'INTERMEDIATE', km: 2.5, angle: 140, years: 9,
    headline: 'Electricista residencial certificada', bio: 'Instalaciones eléctricas, breakers, ventiladores de techo y aires acondicionados.',
    cats: ['electricidad', 'servicios-tecnicos'], colors: [[202, 138, 4], [253, 224, 71]],
    works: ['Tablero de breakers', 'Instalación de ventiladores', 'Cableado de local'],
    services: [
      ['electricidad', 'Revisión de cortos y breakers', 'Diagnóstico de fallas eléctricas y cambio de breakers.', 35_000, 'VISIT'],
      ['servicios-tecnicos', 'Instalación de aire acondicionado', 'Instalación de equipos minisplit hasta 12.000 BTU.', 180_000, 'FIXED'],
    ],
  },
  {
    name: 'Rafael Contreras', plan: 'BASIC', km: 4.0, angle: 250, years: 20,
    headline: 'Carpintero ebanista', bio: 'Puertas, closets, cocinas y reparación de muebles en madera.',
    cats: ['carpinteria'], colors: [[146, 64, 14], [234, 88, 12]],
    works: ['Puerta en cedro', 'Cocina integral', 'Restauración de mecedora'],
    services: [
      ['carpinteria', 'Reparación de muebles', 'Ajuste y reparación de muebles, sillas y puertas.', 30_000, 'HOUR'],
      ['carpinteria', 'Closet a la medida', 'Diseño y fabricación de closets en madera o MDF.', 600_000, 'FIXED'],
    ],
  },
  {
    name: 'Luis Fernando Bustillo', plan: 'INTERMEDIATE', km: 6.5, angle: 320, years: 7,
    headline: 'Pintor y estucador', bio: 'Pintura de casas por dentro y por fuera, estuco y resanes.',
    cats: ['pintura', 'reparaciones'], colors: [[22, 163, 74], [134, 239, 172]],
    works: ['Fachada pintada', 'Sala estucada', 'Pintura de local'],
    services: [
      ['pintura', 'Pintura de habitación', 'Pintura de habitación estándar con resanes menores.', 150_000, 'FIXED'],
      ['reparaciones', 'Resanes y humedades', 'Tratamiento de humedades y grietas en paredes.', 60_000, 'VISIT'],
    ],
  },
  {
    name: 'Kelly Johana Mercado', plan: 'BASIC', km: 8.5, angle: 200, years: 5,
    headline: 'Cerrajera 24 horas', bio: 'Apertura de puertas, cambio de guardas y cerraduras de seguridad.',
    cats: ['cerrajeria'], colors: [[124, 58, 237], [196, 181, 253]],
    works: ['Cerradura de seguridad', 'Cambio de guardas', 'Apertura de puerta'],
    services: [
      ['cerrajeria', 'Apertura de puertas', 'Apertura de puertas sin daños, a domicilio.', 45_000, 'FIXED'],
      ['cerrajeria', 'Cambio de guarda', 'Cambio de guarda de cerradura con llaves nuevas.', 50_000, 'FIXED'],
    ],
  },
];

const prisma = new PrismaClient();
const passwordHash = await bcrypt.hash('NetJob2026!', 10);
const cat = Object.fromEntries((await prisma.category.findMany()).map((c) => [c.slug, c.id]));
const plan = Object.fromEntries((await prisma.subscriptionPlan.findMany()).map((p) => [p.code, p.id]));
const now = new Date();

for (const [i, p] of people.entries()) {
  const email = `demo-${prefix.toLowerCase()}-${i + 1}@netjob.co`;
  if (await prisma.user.findUnique({ where: { email } })) {
    console.log(`Ya existe ${email}`);
    continue;
  }
  // Punto a p.km del centro en la dirección p.angle
  const rad = (p.angle * Math.PI) / 180;
  const pLat = lat + (p.km * Math.cos(rad)) / 110.57;
  const pLng = lng + (p.km * Math.sin(rad)) / (111.32 * Math.cos((lat * Math.PI) / 180));
  const slug = `${prefix}-${i + 1}`;
  const user = await prisma.user.create({
    data: {
      email, name: p.name, role: 'PROFESSIONAL', city, passwordHash,
      avatarUrl: demoImage(`demo-avatar-${slug}`, 256, 256, p.colors[0], p.colors[1]),
      professional: {
        create: {
          headline: p.headline, bio: p.bio, yearsExperience: p.years, city, coverageArea: `${city} y alrededores`,
          lat: pLat, lng: pLng, verified: true, isAvailable: true,
          verificationStatus: 'APPROVED',
          rulesAcceptedAt: now, trainingPassedAt: now, trainingScore: 25,
          ratingAvg: [4.9, 4.6, 4.8, 4.3, 4.5][i], ratingCount: [14, 8, 21, 5, 3][i],
          categories: { connect: p.cats.map((c) => ({ id: cat[c] })) },
          availability: {
            create: [1, 2, 3, 4, 5, 6].map((d) => ({ dayOfWeek: d, startTime: '07:00', endTime: d === 6 ? '13:00' : '18:00' })),
          },
          subscriptions: { create: { planId: plan[p.plan], status: 'ACTIVE', startsAt: now, endsAt: new Date(now.getTime() + 30 * 864e5) } },
          portfolio: {
            create: p.works.map((title, w) => ({
              title,
              imageUrl: demoImage(`demo-work-${slug}-${w}`, 480, 360, w % 2 ? p.colors[1] : p.colors[0], w % 2 ? p.colors[0] : p.colors[1]),
            })),
          },
        },
      },
    },
    include: { professional: true },
  });
  for (const [c, title, description, price, priceUnit] of p.services) {
    await prisma.service.create({
      data: {
        professionalId: user.professional!.id, categoryId: cat[c], title, description, price, priceUnit,
        conditions: 'Precio de referencia. El valor final se define después de la visita de diagnóstico.',
      },
    });
  }
  console.log(`${p.name} (${email}) a ${p.km} km`);
}
await prisma.$disconnect();
