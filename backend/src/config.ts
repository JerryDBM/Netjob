import 'dotenv/config';

function num(name: string, def: number): number {
  const v = process.env[name];
  return v === undefined || v === '' ? def : Number(v);
}

const wompiEnv = process.env.WOMPI_ENV === 'production' ? 'production' : 'sandbox';

export const config = {
  port: num('PORT', 4000),
  jwtSecret: process.env.JWT_SECRET || 'dev-secret',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  publicUrl: process.env.PUBLIC_URL || 'http://localhost:4000',
  paymentRedirectUrl: process.env.PAYMENT_REDIRECT_URL || 'http://localhost:4000/payments/return',
  commissionRate: num('COMMISSION_RATE', 0.03),
  subscriptionDays: num('SUBSCRIPTION_DAYS', 30),
  /**
   * Visita de diagnóstico (sin comisión). Cada profesional fija su propio valor en el perfil:
   * este es el valor inicial de los perfiles nuevos y `maxDiagnosticFee` el tope permitido.
   */
  diagnosticFee: num('DIAGNOSTIC_FEE', 8000),
  maxDiagnosticFee: num('MAX_DIAGNOSTIC_FEE', 35000),
  /** Radio máximo de búsqueda alrededor del cliente. */
  searchRadiusKm: num('SEARCH_RADIUS_KM', 12),
  /** Fotos mínimas de portafolio para que un perfil profesional quede completo. */
  minPortfolio: num('MIN_PORTFOLIO', 2),
  /** Tarifa reducida para clientes frecuentes y referidos (1 %). */
  loyaltyCommissionRate: num('LOYALTY_COMMISSION_RATE', 0.01),
  /** Cada cuántos servicios finalizados un cliente bien calificado gana una tarifa reducida. */
  loyaltyEvery: num('LOYALTY_EVERY', 3),
  /** Calificación mínima (estrictamente mayor) del cliente para ganar la tarifa reducida. */
  loyaltyMinRating: num('LOYALTY_MIN_RATING', 4.4),
  /** Premio al profesional: calificación mínima y servicios en los últimos 30 días. */
  proRewardMinRating: num('PRO_REWARD_MIN_RATING', 4.8),
  proRewardMinReviews: num('PRO_REWARD_MIN_REVIEWS', 3),
  proRewardServices: num('PRO_REWARD_SERVICES', 3), // → 10 % en la siguiente suscripción
  proRewardServicesTop: num('PRO_REWARD_SERVICES_TOP', 6), // → 12 %
  /** Días del potenciador de recomendación. */
  boostDays: num('BOOST_DAYS', 30),
  referralBoostDays: num('REFERRAL_BOOST_DAYS', 7),
  /** Garantía de la mano de obra después de finalizar (días). */
  warrantyDays: num('WARRANTY_DAYS', 30),
  /** Calificación por debajo de la cual una cuenta entra en revisión (con al menos 3 reseñas). */
  reviewThreshold: num('REVIEW_THRESHOLD', 3.5),
  /** Preguntas correctas para aprobar la capacitación inicial (de 25). */
  trainingPassScore: num('TRAINING_PASS_SCORE', 20),
  /**
   * Verificación obligatoria: el profesional no aparece en búsquedas ni recibe solicitudes
   * hasta que el admin apruebe sus documentos. Se desactiva con REQUIRE_VERIFICATION=false.
   */
  requireVerification: process.env.REQUIRE_VERIFICATION !== 'false',
  /** Supabase Storage para imágenes (si no se configura, se guardan en el disco del servidor). */
  supabase: {
    url: (process.env.SUPABASE_URL || '').replace(/\/$/, ''),
    serviceKey: process.env.SUPABASE_SERVICE_ROLE_KEY || '',
    publicBucket: process.env.SUPABASE_PUBLIC_BUCKET || 'uploads',
    privateBucket: process.env.SUPABASE_PRIVATE_BUCKET || 'private-docs',
  },
  /** WhatsApp Business de soporte (formato internacional, sin +). */
  supportWhatsapp: process.env.SUPPORT_WHATSAPP || '573027402932',
  /** Servidor de rutas OSRM para la navegación dentro de la app. */
  routingUrl: process.env.ROUTING_URL || 'https://router.project-osrm.org',
  wompi: {
    env: wompiEnv,
    apiBase: wompiEnv === 'production' ? 'https://production.wompi.co/v1' : 'https://sandbox.wompi.co/v1',
    checkoutBase: 'https://checkout.wompi.co/p/',
    publicKey: process.env.WOMPI_PUBLIC_KEY || '',
    privateKey: process.env.WOMPI_PRIVATE_KEY || '',
    integritySecret: process.env.WOMPI_INTEGRITY_SECRET || '',
    eventsSecret: process.env.WOMPI_EVENTS_SECRET || '',
  },
  // Proyecto académico sin comercio en Wompi: con PAYMENTS_MOCK=true los pagos se simulan (también en
  // el servidor de pruebas). Si se configuran llaves de Wompi, siempre se usa la pasarela real.
  paymentsMock: process.env.PAYMENTS_MOCK === 'true',
};

if (process.env.NODE_ENV === 'production' && config.jwtSecret === 'dev-secret') {
  throw new Error('JWT_SECRET es obligatorio en producción');
}
