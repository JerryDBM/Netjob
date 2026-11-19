import { prisma } from '../db.js';
import { notify } from './notify.js';

/** Horas que ocupa una cita en la agenda del profesional (evita citas simultáneas). */
export const BLOCK_HOURS = 2;
const BLOCK_MS = BLOCK_HOURS * 3600 * 1000;

/** "p. m." → "pm": evita dobles puntos cuando la hora cierra una frase. */
const ampm = (s: string) => s.replace(/\s*([ap])\.\s*m\./g, ' $1m').replace(/ /g, ' ');

/** Fecha y hora en Colombia para mensajes: "jueves, 20 de noviembre, 3:00 pm" */
export function bogotaDateTime(d: Date) {
  return ampm(d.toLocaleString('es-CO', {
    timeZone: 'America/Bogota',
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    hour: 'numeric',
    minute: '2-digit',
  }));
}

export function bogotaTime(d: Date) {
  return ampm(d.toLocaleTimeString('es-CO', { timeZone: 'America/Bogota', hour: 'numeric', minute: '2-digit' }));
}

/** Bloqueo del profesional que se cruza con una cita a esa hora (la cita ocupa BLOCK_HOURS). */
export function blockAt(professionalId: string, at: Date) {
  return prisma.calendarBlock.findFirst({
    where: { professionalId, startsAt: { lt: new Date(at.getTime() + BLOCK_MS) }, endsAt: { gt: at } },
    orderBy: { startsAt: 'asc' },
  });
}

/** Otra cita aceptada o en curso del profesional a menos de BLOCK_HOURS de esa hora. */
export function clashAt(professionalId: string, at: Date, excludeRequestId?: string) {
  return prisma.serviceRequest.findFirst({
    where: {
      professionalId,
      id: excludeRequestId ? { not: excludeRequestId } : undefined,
      status: { in: ['ACCEPTED', 'IN_PROGRESS'] },
      scheduledAt: { gt: new Date(at.getTime() - BLOCK_MS), lt: new Date(at.getTime() + BLOCK_MS) },
    },
  });
}

/** Mensaje para el cliente cuando la hora pedida cae en un bloqueo del profesional. */
export function blockedMessage(b: { startsAt: Date; endsAt: Date }) {
  return `El profesional no tiene agenda del ${bogotaDateTime(b.startsAt)} al ${bogotaDateTime(b.endsAt)}. Elige otra fecha u hora.`;
}

const HOUR = 3600 * 1000;

/**
 * Recordatorios de citas (se ejecuta cada pocos minutos):
 *  - Un día antes: a ambas partes si la cita está aceptada; al profesional si aún está pendiente
 *    de respuesta.
 *  - Una hora antes: a ambas partes de las citas aceptadas.
 */
export async function sendAppointmentReminders(now = new Date()) {
  const soon = await prisma.serviceRequest.findMany({
    where: {
      status: { in: ['PENDING', 'ACCEPTED'] },
      scheduledAt: { gt: now, lte: new Date(now.getTime() + 24 * HOUR) },
      OR: [{ reminderDaySentAt: null }, { reminderHourSentAt: null }],
    },
    include: {
      service: { select: { title: true } },
      client: { select: { name: true } },
      professional: { select: { userId: true, user: { select: { name: true } } } },
    },
    take: 500,
  });
  let sent = 0;
  for (const r of soon) {
    const left = r.scheduledAt.getTime() - now.getTime();
    const when = bogotaDateTime(r.scheduledAt);
    const data = { requestId: r.id, calendar: true };
    const proFirst = r.professional.user.name.split(' ')[0];
    const clientFirst = r.client.name.split(' ')[0];

    if (left <= HOUR && !r.reminderHourSentAt) {
      // Marcar primero evita avisos duplicados si el proceso se reinicia a mitad del envío
      const claimed = await prisma.serviceRequest.updateMany({
        where: { id: r.id, reminderHourSentAt: null },
        data: { reminderHourSentAt: now, reminderDaySentAt: r.reminderDaySentAt ?? now },
      });
      if (!claimed.count || r.status !== 'ACCEPTED') continue;
      const at = bogotaTime(r.scheduledAt);
      await notify(r.clientId, 'REMINDER', 'Tu cita es en menos de una hora', `${proFirst} te atiende a las ${at}: ${r.service.title}. Dirección: ${r.address}.`, data);
      await notify(r.professional.userId, 'REMINDER', 'Cita en menos de una hora', `${r.service.title} con ${clientFirst} a las ${at} en ${r.address}. Avisa "Voy en camino" cuando salgas.`, data);
      sent++;
    } else if (left > HOUR && !r.reminderDaySentAt) {
      const claimed = await prisma.serviceRequest.updateMany({
        where: { id: r.id, reminderDaySentAt: null },
        data: { reminderDaySentAt: now },
      });
      if (!claimed.count) continue;
      if (r.status === 'PENDING') {
        await notify(
          r.professional.userId,
          'REMINDER',
          'Solicitud sin responder para mañana',
          `${clientFirst} pidió "${r.service.title}" para el ${when}. Acéptala o recházala para que pueda organizarse.`,
          data,
        );
      } else {
        await notify(r.clientId, 'REMINDER', 'Recordatorio de tu cita', `${r.service.title} con ${proFirst}: ${when}. Dirección: ${r.address}.`, data, { email: true });
        await notify(r.professional.userId, 'REMINDER', 'Recordatorio de cita', `${r.service.title} con ${clientFirst}: ${when} en ${r.address}.`, data, { email: true });
      }
      sent++;
    }
  }
  return sent;
}
