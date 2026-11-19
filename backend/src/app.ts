import { routingRouter } from './routes/routing.js';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { UPLOAD_DIR } from './lib/upload.js';
import { errorHandler } from './middleware/error.js';
import { authRouter, meRouter } from './routes/auth.js';
import { categoriesRouter } from './routes/categories.js';
import { professionalsRouter } from './routes/professionals.js';
import { servicesRouter } from './routes/services.js';
import { requestsRouter } from './routes/requests.js';
import { paymentsRouter } from './routes/payments.js';
import { subscriptionsRouter } from './routes/subscriptions.js';
import { adminRouter, notificationsRouter, reviewsRouter } from './routes/misc.js';
import { config } from './config.js';
import { trainingRouter, verificationRouter } from './routes/trust.js';
import { claimsRouter } from './routes/claims.js';
import { promotionsRouter } from './routes/promotions.js';
import { calendarRouter } from './routes/calendar.js';

export function createApp() {
  const app = express();
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

  app.use('/uploads', express.static(UPLOAD_DIR, { maxAge: '7d' }));

  app.get('/health', (_req, res) => res.json({ ok: true, payments: config.paymentsMock ? 'mock' : 'wompi' }));
  app.get('/config', (_req, res) =>
    res.json({
      commissionRate: config.commissionRate,
      paymentsMock: config.paymentsMock,
      subscriptionDays: config.subscriptionDays,
      diagnosticFee: config.diagnosticFee,
      maxDiagnosticFee: config.maxDiagnosticFee,
      searchRadiusKm: config.searchRadiusKm,
      minPortfolio: config.minPortfolio,
      loyaltyCommissionRate: config.loyaltyCommissionRate,
      loyaltyEvery: config.loyaltyEvery,
      warrantyDays: config.warrantyDays,
      supportWhatsapp: config.supportWhatsapp,
      requireVerification: config.requireVerification,
    }),
  );

  app.use('/auth', authRouter);
  app.use('/me', meRouter);
  app.use('/categories', categoriesRouter);
  app.use('/professionals', professionalsRouter);
  app.use('/services', servicesRouter);
  app.use('/requests', requestsRouter);
  app.use('/payments', paymentsRouter);
  app.use('/subscriptions', subscriptionsRouter);
  app.use('/notifications', notificationsRouter);
  app.use('/reviews', reviewsRouter);
  app.use('/routes', routingRouter);
  app.use('/training', trainingRouter);
  app.use('/verification', verificationRouter);
  app.use('/claims', claimsRouter);
  app.use('/promotions', promotionsRouter);
  app.use('/calendar', calendarRouter);
  app.use('/admin', adminRouter);

  app.use((_req, res) => res.status(404).json({ error: 'Ruta no encontrada' }));
  app.use(errorHandler);
  return app;
}
