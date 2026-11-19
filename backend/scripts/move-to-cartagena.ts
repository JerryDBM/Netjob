/**
 * Datos de prueba: pasa todos los profesionales a Cartagena, repartidos por barrios, y
 * actualiza las menciones de la ciudad en su perfil, servicios, portafolio y solicitudes.
 *
 *   npm run demo:cartagena
 */
import { prisma } from '../src/db.js';
import { CARTAGENA, placeFor } from './cartagena.js';

const OTHER_CITIES = ['El Carmen de Bolívar', 'Barranquilla', 'Bogotá', 'Medellín', 'Sincelejo', 'Cali'];
const swapCity = (s: string | null) => {
  if (!s) return s;
  let out = s;
  for (const c of OTHER_CITIES) out = out.split(c).join(CARTAGENA.name);
  return out;
};

const pros = await prisma.professionalProfile.findMany({
  orderBy: { createdAt: 'asc' },
  include: { user: true, portfolio: { orderBy: { createdAt: 'asc' } }, services: true },
});

for (const [i, p] of pros.entries()) {
  const place = placeFor(i);
  const areaText = place.areas.join(', ');
  const bio = p.bio
    ? swapCity(p.bio)!.replace(/Atiendo en .*? y barrios cercanos\./, `Atiendo en ${areaText} y barrios cercanos.`)
    : p.bio;
  await prisma.$transaction([
    prisma.user.update({ where: { id: p.userId }, data: { city: CARTAGENA.name, department: CARTAGENA.dept } }),
    prisma.professionalProfile.update({
      where: { id: p.id },
      data: { city: CARTAGENA.name, lat: place.lat, lng: place.lng, coverageArea: `${areaText} y alrededores`, bio, headline: swapCity(p.headline) },
    }),
    ...p.services.map((s) =>
      prisma.service.update({
        where: { id: s.id },
        data: { coverageArea: `${CARTAGENA.name}: ${areaText}`, description: swapCity(s.description)!, conditions: swapCity(s.conditions) },
      }),
    ),
    // "Baño remodelado · Chapinero" → "Baño remodelado · Manga"
    ...p.portfolio.map((w, k) =>
      prisma.portfolioItem.update({
        where: { id: w.id },
        data: { title: w.title.includes(' · ') ? `${w.title.split(' · ')[0]} · ${place.areas[k % place.areas.length]}` : w.title },
      }),
    ),
  ]);
  // Solicitudes de prueba ya finalizadas: dirección en un barrio de Cartagena
  const done = await prisma.serviceRequest.findMany({ where: { professionalId: p.id, status: 'COMPLETED' }, select: { id: true } });
  for (const [k, r] of done.entries()) {
    const near = placeFor(i + k + 3);
    await prisma.serviceRequest.update({
      where: { id: r.id },
      data: { address: `${near.barrio}, ${CARTAGENA.name}`, lat: near.lat, lng: near.lng },
    });
  }
  console.log(`${p.user.name} → ${place.barrio}`);
}
console.log(`\n${pros.length} profesionales en ${CARTAGENA.name}`);
await prisma.$disconnect();
