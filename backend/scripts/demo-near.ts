/**
 * Solo desarrollo: mueve los profesionales demo cerca de un punto para probar la búsqueda
 * por radio (15 km) desde tu ubicación real.
 *
 *   npm run demo:near -- 10.3910 -75.4794 "Cartagena"
 */
import { PrismaClient } from '@prisma/client';

const [lat, lng] = process.argv.slice(2, 4).map(Number);
const city = process.argv[4];
if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
  console.error('Uso: npm run demo:near -- <lat> <lng> ["Ciudad"]');
  process.exit(1);
}

const prisma = new PrismaClient();
// Desplazamientos en grados (≈ 2, 5 y 9 km) para que queden dentro del radio
const offsets = [[0.012, 0.01], [-0.03, 0.025], [0.05, -0.06]];
const emails = ['plomero@netjob.co', 'electricista@netjob.co', 'carpintero@netjob.co'];

for (const [i, email] of emails.entries()) {
  const user = await prisma.user.findUnique({ where: { email }, include: { professional: true } });
  if (!user?.professional) continue;
  await prisma.professionalProfile.update({
    where: { id: user.professional.id },
    data: { lat: lat + offsets[i][0], lng: lng + offsets[i][1], ...(city ? { city } : {}) },
  });
  console.log(`${user.name} → ${(lat + offsets[i][0]).toFixed(4)}, ${(lng + offsets[i][1]).toFixed(4)}`);
}
await prisma.$disconnect();
