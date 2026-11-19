import type { Prisma } from '@prisma/client';
import { prisma } from '../db.js';
import { config } from '../config.js';

/**
 * Un profesional debe completar su perfil antes de aparecer en búsquedas:
 * foto, título, descripción, ciudad y ubicación en el mapa, zona, especialidades,
 * horarios y fotos de portafolio.
 */
export async function profileMissing(professionalId: string): Promise<string[]> {
  const p = await prisma.professionalProfile.findUnique({
    where: { id: professionalId },
    include: {
      user: { select: { avatarUrl: true } },
      _count: { select: { portfolio: true, availability: true, categories: true } },
    },
  });
  if (!p) return [];
  const missing: string[] = [];
  if (!p.user.avatarUrl) missing.push('avatar');
  if (!p.headline?.trim()) missing.push('headline');
  if (!p.bio?.trim()) missing.push('bio');
  if (!p.city?.trim() || !p.coverageArea?.trim() || p.lat == null || p.lng == null) missing.push('location');
  if (p._count.categories === 0) missing.push('categories');
  if (p._count.availability === 0) missing.push('availability');
  if (p._count.portfolio < config.minPortfolio) missing.push('portfolio');
  // Capacitación inicial obligatoria: instructivos leídos, reglas aceptadas y cuestionario aprobado
  if (!p.trainingPassedAt) missing.push('training');
  return missing;
}

/** Mismo criterio como filtro de Prisma, para excluir perfiles incompletos de la búsqueda. */
export function completeProfileFilter(): Prisma.ProfessionalProfileWhereInput {
  return {
    user: { avatarUrl: { not: null } },
    headline: { not: null },
    bio: { not: null },
    city: { not: null },
    coverageArea: { not: null },
    lat: { not: null },
    lng: { not: null },
    categories: { some: {} },
    availability: { some: {} },
    // Prisma no filtra por conteo mínimo; el conteo exacto se verifica después de la consulta.
    portfolio: { some: {} },
    trainingPassedAt: { not: null },
    // Opcional (REQUIRE_VERIFICATION=true): solo perfiles con documentos aprobados por el admin
    ...(config.requireVerification ? { verified: true } : {}),
  };
}
