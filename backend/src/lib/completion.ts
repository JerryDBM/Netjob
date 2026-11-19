import { prisma } from '../db.js';
import { config } from '../config.js';
import { notify } from './notify.js';
import { onServiceCompleted } from './rewards.js';

/**
 * Lo que ocurre cuando una solicitud queda Finalizada: empieza la garantía, se libera
 * al profesional el dinero retenido y se evalúan los premios de ambas partes.
 */
export async function afterCompleted(requestId: string) {
  const now = new Date();
  const r = await prisma.serviceRequest.update({
    where: { id: requestId },
    data: {
      warrantyUntil: new Date(now.getTime() + config.warrantyDays * 864e5),
      enRouteAt: null,
      proLat: null,
      proLng: null,
      proLocationAt: null,
    },
    select: { clientId: true, professional: { select: { userId: true } } },
  });
  const released = await prisma.payment.updateMany({
    where: { requestId, kind: 'SERVICE', status: 'APPROVED', payoutStatus: 'HELD' },
    data: { payoutStatus: 'RELEASED', payoutReleasedAt: now },
  });
  if (released.count) {
    const p = await prisma.payment.findFirst({ where: { requestId, kind: 'SERVICE', status: 'APPROVED' } });
    await notify(
      r.professional.userId,
      'PAYMENT',
      'Dinero liberado',
      `El servicio quedó finalizado. Se liberaron $${(p?.serviceAmount ?? 0).toLocaleString('es-CO')} a tu favor.`,
      { requestId, paymentId: p?.id },
      { email: true },
    );
  }
  await notify(
    r.clientId,
    'REMINDER',
    '¿Cómo te fue?',
    `Califica el servicio recibido. Tienes ${config.warrantyDays} días de garantía sobre la mano de obra: si algo falla, abre una reclamación desde la solicitud.`,
    { requestId },
  );
  await onServiceCompleted(requestId);
}

/** ¿Hay una reclamación sin resolver sobre la solicitud? Mientras exista, el dinero sigue retenido. */
export const hasOpenClaim = (requestId: string) =>
  prisma.claim.count({ where: { requestId, status: { in: ['OPEN', 'IN_REVIEW'] } } }).then((c) => c > 0);
