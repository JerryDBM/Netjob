import { prisma } from '../db.js';
import { emitToUser } from './socket.js';
import { sendMail } from './mailer.js';

export type NotificationType =
  | 'REQUEST_NEW'
  | 'REQUEST_STATUS'
  | 'REQUEST_QUOTE'
  | 'MESSAGE_NEW'
  | 'PAYMENT'
  | 'REVIEW_NEW'
  | 'SUBSCRIPTION'
  | 'REMINDER'
  | 'TRIP'
  | 'CLAIM'
  | 'VERIFICATION'
  | 'REWARD'
  | 'ACCOUNT';

/**
 * Registra la notificación, la emite en tiempo real por socket y (opcional) por correo.
 * Push (FCM) se conectará aquí cuando se registren los tokens de dispositivo.
 */
export async function notify(
  userId: string,
  type: NotificationType,
  title: string,
  body: string,
  data?: Record<string, unknown>,
  opts: { email?: boolean } = {},
) {
  const n = await prisma.notification.create({
    data: { userId, type, title, body, data: (data ?? undefined) as any },
  });
  emitToUser(userId, 'notification', n);
  if (opts.email) {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
    if (user) await sendMail(user.email, title, body);
  }
  return n;
}
