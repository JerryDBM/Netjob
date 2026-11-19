import http from 'node:http';
import { Server } from 'socket.io';
import { createApp } from './app.js';
import { config } from './config.js';
import { prisma } from './db.js';
import { verifyToken } from './middleware/auth.js';
import { setIo } from './lib/socket.js';
import { sendRenewalReminders } from './lib/subscriptions.js';
import { sendAppointmentReminders } from './lib/calendar.js';
import { loadSettings } from './lib/settings.js';
import { ensureBuckets } from './lib/upload.js';

const app = createApp();
const server = http.createServer(app);

/**
 * Tiempo real (chat y notificaciones). El cliente se conecta con `auth: { token }`
 * y entra automáticamente a su sala `user:<id>`. Para un chat, emite `join` con el id
 * de la solicitud; solo se permite si es participante.
 */
const io = new Server(server, { cors: { origin: '*' } });
setIo(io);

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token as string | undefined;
    if (!token) return next(new Error('No autenticado'));
    socket.data.userId = verifyToken(token).sub;
    next();
  } catch {
    next(new Error('Sesión inválida'));
  }
});

io.on('connection', (socket) => {
  const userId: string = socket.data.userId;
  socket.join(`user:${userId}`);

  socket.on('join', async (requestId: string, ack?: (ok: boolean) => void) => {
    const r = await prisma.serviceRequest.findUnique({
      where: { id: String(requestId) },
      select: { clientId: true, professional: { select: { userId: true } } },
    });
    const ok = !!r && (r.clientId === userId || r.professional.userId === userId);
    if (ok) socket.join(`request:${requestId}`);
    ack?.(ok);
  });

  socket.on('leave', (requestId: string) => socket.leave(`request:${requestId}`));
});

// Configuración guardada por el administrador (comisión, radio, garantía, tope de visita…)
await loadSettings().catch((e) => console.error('[configuración]', e));
await ensureBuckets().catch((e) => console.error('[almacenamiento]', e));

// Avisos de renovación: al arrancar y cada hora
const remind = () => sendRenewalReminders().catch((e) => console.error('[recordatorios]', e));
remind();
setInterval(remind, 60 * 60 * 1000).unref();

// Recordatorios de citas (un día y una hora antes): cada 5 minutos
const remindAppointments = () => sendAppointmentReminders().catch((e) => console.error('[recordatorios de citas]', e));
remindAppointments();
setInterval(remindAppointments, 5 * 60 * 1000).unref();

server.listen(config.port, () => {
  console.log(`NetJob API escuchando en http://localhost:${config.port} (pagos: ${config.paymentsMock ? 'simulados' : 'Wompi ' + config.wompi.env})`);
});
