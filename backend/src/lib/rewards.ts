import crypto from 'node:crypto';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { notify } from './notify.js';

const DAY = 864e5;

// ---------- Tarifa del cliente (fidelización y referidos) ----------

/**
 * Tarifa NetJob que le corresponde a un cliente en su próximo servicio:
 * 3 % normal, o 1 % si tiene un beneficio disponible (cliente frecuente bien calificado o referido).
 */
export async function commissionFor(clientId: string) {
  const u = await prisma.user.findUnique({ where: { id: clientId }, select: { commissionCredits: true } });
  const reduced = (u?.commissionCredits ?? 0) > 0;
  return {
    rate: reduced ? config.loyaltyCommissionRate : config.commissionRate,
    standardRate: config.commissionRate,
    reduced,
    credits: u?.commissionCredits ?? 0,
  };
}

/** Código corto y legible para invitar a otras personas. */
export function newReferralCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return 'NJ' + [...crypto.randomBytes(6)].map((b) => alphabet[b % alphabet.length]).join('');
}

/** Garantiza que el usuario tenga código de referido (las cuentas antiguas no lo tienen). */
export async function ensureReferralCode(userId: string) {
  const u = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { referralCode: true } });
  if (u.referralCode) return u.referralCode;
  for (let i = 0; i < 5; i++) {
    try {
      const code = newReferralCode();
      await prisma.user.update({ where: { id: userId }, data: { referralCode: code } });
      return code;
    } catch {
      /* colisión improbable: se reintenta */
    }
  }
  throw new Error('No se pudo generar el código de referido');
}

// ---------- Premios y seguimiento al terminar un servicio ----------

/** Desempeño reciente del profesional: define descuento en la suscripción y potenciador. */
export async function proPerformance(professionalId: string) {
  const [profile, recent] = await Promise.all([
    prisma.professionalProfile.findUniqueOrThrow({
      where: { id: professionalId },
      select: { ratingAvg: true, ratingCount: true, boostUntil: true },
    }),
    prisma.serviceRequest.count({
      where: { professionalId, status: 'COMPLETED', updatedAt: { gte: new Date(Date.now() - 30 * DAY) } },
    }),
  ]);
  const goodRating = profile.ratingCount >= config.proRewardMinReviews && profile.ratingAvg >= config.proRewardMinRating;
  const discountPct = !goodRating ? 0 : recent >= config.proRewardServicesTop ? 12 : recent >= config.proRewardServices ? 10 : 0;
  return {
    ratingAvg: profile.ratingAvg,
    ratingCount: profile.ratingCount,
    recentServices: recent,
    discountPct,
    boostUntil: profile.boostUntil && profile.boostUntil > new Date() ? profile.boostUntil : null,
    goals: {
      minRating: config.proRewardMinRating,
      minReviews: config.proRewardMinReviews,
      services: config.proRewardServices,
      servicesTop: config.proRewardServicesTop,
    },
  };
}

/**
 * Se ejecuta cuando un servicio queda finalizado:
 *  - cliente frecuente y bien calificado → gana una tarifa reducida;
 *  - primer servicio de un referido → premio para quien lo invitó;
 *  - profesional con buen desempeño → potenciador de recomendación.
 */
export async function onServiceCompleted(requestId: string) {
  const r = await prisma.serviceRequest.findUniqueOrThrow({
    where: { id: requestId },
    select: { clientId: true, professionalId: true, professional: { select: { userId: true } } },
  });
  const client = await prisma.user.findUniqueOrThrow({
    where: { id: r.clientId },
    select: { id: true, clientRatingAvg: true, clientRatingCount: true, referredById: true, referralRewarded: true, name: true },
  });
  const completed = await prisma.serviceRequest.count({ where: { clientId: r.clientId, status: 'COMPLETED' } });

  if (completed % config.loyaltyEvery === 0 && client.clientRatingCount > 0 && client.clientRatingAvg > config.loyaltyMinRating) {
    await prisma.user.update({ where: { id: client.id }, data: { commissionCredits: { increment: 1 } } });
    await notify(
      client.id,
      'REWARD',
      '¡Ganaste una tarifa reducida!',
      `Por ser cliente frecuente y tener buena calificación, en tu próximo servicio la tarifa NetJob baja del ${pct(config.commissionRate)} al ${pct(config.loyaltyCommissionRate)}.`,
    );
  }

  if (client.referredById && !client.referralRewarded) {
    await prisma.user.update({ where: { id: client.id }, data: { referralRewarded: true } });
    await rewardReferrer(client.referredById, client.name);
  }

  const perf = await proPerformance(r.professionalId);
  if (perf.discountPct > 0) {
    const until = new Date(Date.now() + config.boostDays * DAY);
    const hadBoost = !!perf.boostUntil;
    await prisma.professionalProfile.update({ where: { id: r.professionalId }, data: { boostUntil: until } });
    if (!hadBoost) {
      await notify(
        r.professional.userId,
        'REWARD',
        '¡Ganaste un potenciador de recomendación!',
        `Tu calificación y tu actividad te suben en los resultados durante ${config.boostDays} días y te dan ${perf.discountPct} % de descuento en tu siguiente suscripción.`,
      );
    }
  }
}

/** Premio para quien invitó: tarifa reducida si es cliente, potenciador si es profesional. */
export async function rewardReferrer(referrerId: string, invitedName: string) {
  const ref = await prisma.user.findUnique({ where: { id: referrerId }, select: { id: true, role: true, professional: { select: { id: true, boostUntil: true } } } });
  if (!ref) return;
  if (ref.role === 'PROFESSIONAL' && ref.professional) {
    const base = ref.professional.boostUntil && ref.professional.boostUntil > new Date() ? ref.professional.boostUntil : new Date();
    await prisma.professionalProfile.update({
      where: { id: ref.professional.id },
      data: { boostUntil: new Date(base.getTime() + config.referralBoostDays * DAY) },
    });
    await notify(ref.id, 'REWARD', 'Tu invitado ya está activo', `${invitedName} se unió con tu código. Ganaste ${config.referralBoostDays} días de potenciador de recomendación.`);
  } else if (ref.role === 'CLIENT') {
    await prisma.user.update({ where: { id: ref.id }, data: { commissionCredits: { increment: 1 } } });
    await notify(ref.id, 'REWARD', 'Tu invitado ya usó NetJob', `${invitedName} terminó su primer servicio. En tu próximo servicio la tarifa NetJob baja al ${pct(config.loyaltyCommissionRate)}.`);
  }
}

// ---------- Seguimiento de calidad (revisión por calificaciones bajas) ----------

/** Marca la cuenta "en revisión" si su promedio cae por debajo del umbral con al menos 3 reseñas. */
export async function checkQuality(userId: string, ratingAvg: number, ratingCount: number, as: 'cliente' | 'profesional') {
  const low = ratingCount >= 3 && ratingAvg < config.reviewThreshold;
  const u = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { underReview: true } });
  if (low && !u.underReview) {
    await prisma.user.update({
      where: { id: userId },
      data: { underReview: true, reviewNote: `Calificación promedio ${ratingAvg} como ${as} (${ratingCount} reseñas)` },
    });
    await notify(
      userId,
      'ACCOUNT',
      'Tu cuenta entró en revisión',
      `Tu calificación promedio es ${ratingAvg}. El equipo de NetJob revisará tus últimos servicios y te contactará con recomendaciones. Mejorar tus próximas calificaciones te saca de la revisión.`,
      undefined,
      { email: true },
    );
  } else if (!low && u.underReview && ratingCount >= 3 && ratingAvg >= config.reviewThreshold) {
    await prisma.user.update({ where: { id: userId }, data: { underReview: false, reviewNote: null } });
  }
}

export const pct = (rate: number) => `${Math.round(rate * 1000) / 10} %`.replace('.', ',');
