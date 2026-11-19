/**
 * Prueba de extremo a extremo del flujo principal de NetJob.
 * Requiere la base de datos de desarrollo con seed (npm run db:dev, db:push, db:seed)
 * y PAYMENTS_MOCK=true sin llaves de Wompi.
 */
process.env.NODE_ENV = 'test';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { prisma } from '../src/db.js';
import { computeServiceCharge } from '../src/lib/money.js';
import { makePng } from '../prisma/demo-images.js';

const app = createApp();
const run = Date.now().toString(36);
// Nombre único por corrida: la base de desarrollo conserva los datos de corridas anteriores
const proName = `Pedro Prueba ${run}`;
const auth = (t: string) => ({ Authorization: `Bearer ${t}` });
// Datos obligatorios del registro
const contact = { phone: '300 123 4567', department: 'Valle del Cauca', city: 'Cali' };
const png = makePng(40, 40, [10, 120, 200], [20, 200, 120]);
// Cali, y un punto a ~1 km y otro a ~20 km
const CALI = { lat: 3.4516, lng: -76.532 };
const NEAR = { lat: 3.46, lng: -76.53 };
const FAR = { lat: 3.27, lng: -76.53 };

after(() => prisma.$disconnect());

/** Capacitación inicial: acepta las reglas y aprueba el cuestionario (respuestas directas de la base de preguntas). */
async function passTraining(token: string) {
  const { gradeQuiz, totalQuestions } = await import('../src/lib/training.js');
  await request(app).post('/training/accept-rules').set(auth(token)).expect(200);
  // Se buscan las respuestas correctas probando cada opción contra el calificador
  const answers = Array.from({ length: totalQuestions }, () => 0);
  for (let i = 0; i < totalQuestions; i++) {
    for (let o = 0; o < 4; o++) {
      const trial = [...answers];
      trial[i] = o;
      if (!gradeQuiz(trial).wrong.includes(i)) {
        answers[i] = o;
        break;
      }
    }
  }
  const r = await request(app).post('/training/submit').set(auth(token)).send({ answers });
  assert.equal(r.body.passed, true, JSON.stringify(r.body));
  return answers;
}

test('comisión del 3 % asumida por el cliente', () => {
  assert.deepEqual(computeServiceCharge(100_000), { serviceAmount: 100_000, commissionAmount: 3_000, totalAmount: 103_000 });
  assert.equal(computeServiceCharge(33_333).commissionAmount, 1_000);
});

test('búsqueda: sin ubicación no devuelve a nadie', async () => {
  const r = await request(app).get('/professionals');
  assert.equal(r.body.needsLocation, true);
  assert.equal(r.body.items.length, 0);
});

test('flujo completo: registro → perfil → suscripción → búsqueda 12 km → diagnóstico → cotización → pago → reseña', async () => {
  // 1. Profesional se registra: el perfil queda pendiente de completar
  const proReg = await request(app).post('/auth/register').send({
    name: proName, email: `pro-${run}@test.co`, password: 'secreto123', role: 'PROFESSIONAL', ...contact,
  });
  assert.equal(proReg.status, 201, JSON.stringify(proReg.body));
  const proToken = proReg.body.token;
  assert.deepEqual(
    [...proReg.body.user.professional.missing].sort(),
    ['availability', 'avatar', 'bio', 'categories', 'headline', 'location', 'portfolio', 'training'],
  );
  assert.equal(proReg.body.user.professional.idFrontFile, undefined, 'los documentos no viajan en la sesión');
  assert.match(proReg.body.user.referralCode, /^NJ[A-Z0-9]{6}$/);

  // 2. Completa el perfil (antes de suscribirse puede subir portafolio)
  const categories = (await request(app).get('/categories')).body;
  const plomeria = categories.find((c: any) => c.slug === 'plomeria');
  await request(app).post('/me/avatar').set(auth(proToken)).attach('file', png, 'yo.png').expect(200);
  await request(app).patch('/professionals/me/profile').set(auth(proToken)).send({
    headline: 'Plomero en Cali', bio: 'Arreglo fugas y tuberías', city: 'Cali', coverageArea: 'San Fernando, El Peñón',
    ...CALI, categoryIds: [plomeria.id],
  }).expect(200);
  await request(app).put('/professionals/me/availability').set(auth(proToken))
    .send({ slots: [{ dayOfWeek: 1, startTime: '08:00', endTime: '17:00' }] }).expect(200);
  for (const t of ['Baño', 'Cocina']) {
    await request(app).post('/professionals/me/portfolio').set(auth(proToken)).field('title', t).attach('file', png, 'w.png').expect(201);
  }
  // 2b. Capacitación obligatoria: sin reglas aceptadas no hay cuestionario; con 0 aciertos no aprueba
  assert.deepEqual((await request(app).get('/me').set(auth(proToken))).body.professional.missing, ['training']);
  const training = await request(app).get('/training').set(auth(proToken));
  assert.equal(training.body.questions.length, 25);
  assert.equal(training.body.questions[0].answer, undefined, 'las respuestas no salen del backend');
  assert.ok(training.body.guides.length >= 4);
  const blank = { answers: Array.from({ length: 25 }, () => 2) };
  assert.equal((await request(app).post('/training/submit').set(auth(proToken)).send(blank)).status, 409);
  await request(app).post('/training/accept-rules').set(auth(proToken)).expect(200);
  const failed = await request(app).post('/training/submit').set(auth(proToken)).send(blank);
  assert.equal(failed.body.passed, false);
  await passTraining(proToken);
  const me = await request(app).get('/me').set(auth(proToken));
  assert.deepEqual(me.body.professional.missing, []);
  assert.ok(me.body.avatarUrl.startsWith('/uploads/'), 'las imágenes se guardan con ruta relativa');

  // Sin suscripción no puede publicar
  const blocked = await request(app).post('/services').set(auth(proToken)).send({
    categoryId: plomeria.id, title: 'Arreglo de grifos', description: 'Cambio y reparación de grifería', price: 100_000,
  });
  assert.equal(blocked.status, 403);

  // 3. Plan Básico pagado (simulado) y servicio publicado con precio "desde"
  const plans = (await request(app).get('/subscriptions/plans')).body;
  const basic = plans.find((p: any) => p.code === 'BASIC');
  assert.equal(basic.priceMonthly, 24_900);
  const subCheckout = await request(app).post('/subscriptions/checkout').set(auth(proToken)).send({ planId: basic.id });
  assert.equal(subCheckout.body.mode, 'mock');
  await request(app).post(`/payments/${subCheckout.body.payment.id}/simulate`).set(auth(proToken)).send({ status: 'APPROVED' }).expect(200);
  const svc = await request(app).post('/services').set(auth(proToken)).send({
    categoryId: plomeria.id, title: `Arreglo de grifos ${run}`, description: 'Cambio y reparación de grifería', price: 60_000,
  });
  assert.equal(svc.status, 201, JSON.stringify(svc.body));

  // 3a. Verificación obligatoria: con todo lo demás completo, sin documentos aprobados no aparece
  // en búsquedas ni puede recibir solicitudes; al aprobarlo el administrador, sí.
  const hidden = await request(app).get('/professionals').query({ categoryId: plomeria.id, ...NEAR });
  assert.ok(!hidden.body.items.some((i: any) => i.name === proName), 'sin verificar no aparece');
  const proId = proReg.body.user.professional.id;
  assert.equal((await request(app).get(`/professionals/${proId}`)).body.canReceiveRequests, false);
  const earlyCli = await request(app).post('/auth/register').send({ name: 'Tempra', email: `early-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact });
  const early = await request(app).post('/requests').set(auth(earlyCli.body.token)).send({
    serviceId: svc.body.id, description: 'Solicitud a un profesional sin verificar', address: 'Calle 1 # 2-3, Cali', scheduledAt: new Date(Date.now() + 864e5).toISOString(),
  });
  assert.equal(early.status, 400);
  for (const kind of ['idFront', 'idBack', 'selfie', 'backgroundCheck']) {
    await request(app).post(`/verification/documents/${kind}`).set(auth(proToken)).attach('file', png, 'doc.png').expect(200);
  }
  await request(app).post('/verification/submit').set(auth(proToken)).expect(200);
  const adminToken = (await request(app).post('/auth/login').send({ email: 'admin@netjob.co', password: 'NetJob2026!' })).body.token;
  await request(app).patch(`/admin/verifications/${proId}`).set(auth(adminToken)).send({ approve: true }).expect(200);

  // 3b. Beneficios del plan a la vista: contadores de uso, límite con código y estadísticas solo desde Intermedio
  const subMe = await request(app).get('/subscriptions/me').set(auth(proToken));
  assert.deepEqual(subMe.body.usage.services, { used: 1, max: 3, reached: false, near: false });
  assert.equal(subMe.body.usage.portfolio.max, 6);
  assert.equal(subMe.body.daysLeft, 30);
  assert.equal(subMe.body.value.requests, 0);
  for (const t of ['Segundo', 'Tercero']) {
    await request(app).post('/services').set(auth(proToken)).send({ categoryId: plomeria.id, title: `${t} ${run}`, description: 'Servicio de prueba adicional', price: 70_000 }).expect(201);
  }
  const overLimit = await request(app).post('/services').set(auth(proToken)).send({ categoryId: plomeria.id, title: `Cuarto ${run}`, description: 'Servicio que supera el límite', price: 70_000 });
  assert.equal(overLimit.status, 403);
  assert.equal(overLimit.body.code, 'PLAN_LIMIT');
  const noStats = await request(app).get('/professionals/me/insights').set(auth(proToken));
  assert.equal(noStats.status, 403);
  assert.equal(noStats.body.code, 'PLAN_REQUIRED');
  assert.equal(plans.find((p: any) => p.code === 'INTERMEDIATE').popular, true);
  assert.equal(plans.find((p: any) => p.code === 'PREMIUM').badge, 'Premium');

  // 4. Cliente busca: aparece a ~1 km, no aparece a ~20 km
  const cliReg = await request(app).post('/auth/register').send({
    name: 'Clara Cliente', email: `cli-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact,
  });
  const cliToken = cliReg.body.token;
  const search = await request(app).get('/professionals').query({ categoryId: plomeria.id, ...NEAR });
  assert.equal(search.body.radiusKm, 12);
  const found = search.body.items.find((i: any) => i.name === proName);
  assert.ok(found, 'el profesional aparece dentro del radio');
  assert.equal(found.minPrice, 60_000);
  assert.ok(found.distanceKm < 2);
  assert.equal(typeof found.lat, 'number');
  const far = await request(app).get('/professionals').query({ categoryId: plomeria.id, ...FAR });
  assert.ok(!far.body.items.some((i: any) => i.name === proName), 'fuera de 12 km no aparece');
  assert.equal(found.planBadge, null, 'el plan Básico no tiene insignia');
  assert.equal(found.boost, undefined, 'los pesos internos del orden no salen');
  const profile = await request(app).get(`/professionals/${found.id}`).set(auth(cliToken));
  assert.equal(profile.body.canReceiveRequests, true);
  assert.equal(profile.body.selfieFile, undefined);
  assert.equal(profile.body.user.phone, undefined);

  // 5. Envía solicitud
  const scheduledAt = new Date(Date.now() + 2 * 864e5).toISOString();
  const reqRes = await request(app).post('/requests').set(auth(cliToken)).send({
    serviceId: svc.body.id, description: 'El grifo de la cocina gotea todo el día', address: 'Calle 5 # 10-20, Cali', ...NEAR, scheduledAt,
  });
  assert.equal(reqRes.status, 201, JSON.stringify(reqRes.body));
  const rid = reqRes.body.id;
  assert.equal(reqRes.body.stage, 'PENDING');
  assert.equal(reqRes.body.diagnosticFee, 8_000);

  assert.equal((await request(app).post(`/payments/service/${rid}/checkout`).set(auth(cliToken))).status, 409);
  const intruder = await request(app).post('/auth/register').send({ name: 'Otro', email: `otro-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact });
  assert.equal((await request(app).get(`/requests/${rid}`).set(auth(intruder.body.token))).status, 403);

  // 6. Profesional acepta → el cliente debe pagar la visita de diagnóstico
  const accepted = await request(app).post(`/requests/${rid}/accept`).set(auth(proToken)).send({});
  assert.equal(accepted.body.status, 'ACCEPTED');
  assert.equal(accepted.body.stage, 'PAY_DIAGNOSTIC');
  assert.equal(accepted.body.charge, null);
  // No puede cotizar antes de que paguen la visita
  assert.equal((await request(app).post(`/requests/${rid}/quote`).set(auth(proToken)).send({ agreedPrice: 100_000, quoteNote: 'Cambio de grifo completo' })).status, 409);

  // 7. Chat
  await request(app).post(`/requests/${rid}/messages`).set(auth(cliToken)).send({ content: '¿Puede llegar a las 9am?' }).expect(201);
  await request(app).post(`/requests/${rid}/messages`).set(auth(proToken)).send({ content: 'Claro, allá estaré.' }).expect(201);

  // 8. Póliza de diagnóstico: $8.000 sin comisión
  const dg = await request(app).post(`/payments/service/${rid}/checkout`).set(auth(cliToken));
  assert.equal(dg.status, 201);
  assert.equal(dg.body.payment.kind, 'DIAGNOSTIC');
  assert.equal(dg.body.payment.totalAmount, 8_000);
  assert.equal(dg.body.payment.commissionAmount, 0);
  await request(app).post(`/payments/${dg.body.payment.id}/simulate`).set(auth(cliToken)).send({ status: 'APPROVED' }).expect(200);
  const afterDg = await request(app).get(`/requests/${rid}`).set(auth(cliToken));
  assert.equal(afterDg.body.stage, 'DIAGNOSIS');

  // 8b. "Voy en camino": el cliente ve la ubicación solo entre la salida y la llegada
  assert.equal(afterDg.body.trip.enRoute, false);
  assert.equal((await request(app).post(`/requests/${rid}/trip/location`).set(auth(proToken)).send(CALI)).status, 409, 'sin ir en camino no se comparte ubicación');
  assert.equal((await request(app).post(`/requests/${rid}/trip`).set(auth(cliToken)).send({ action: 'start' })).status, 403);
  const started = await request(app).post(`/requests/${rid}/trip`).set(auth(proToken)).send({ action: 'start', ...CALI });
  assert.equal(started.body.trip.enRoute, true);
  await request(app).post(`/requests/${rid}/trip/location`).set(auth(proToken)).send({ lat: 3.455, lng: -76.531 }).expect(200);
  const tracking = await request(app).get(`/requests/${rid}`).set(auth(cliToken));
  assert.equal(tracking.body.trip.lat, 3.455);
  assert.equal(tracking.body.proLat, undefined);
  const cliNotifs = await request(app).get('/notifications').set(auth(cliToken));
  assert.ok(cliNotifs.body.items.some((n: any) => n.type === 'TRIP' && n.data.track === true), 'el cliente recibe el aviso de "en camino"');
  const arrived = await request(app).post(`/requests/${rid}/trip`).set(auth(proToken)).send({ action: 'arrive' });
  assert.equal(arrived.body.trip.enRoute, false);
  assert.equal(arrived.body.trip.lat, null, 'al llegar deja de compartirse la ubicación');
  assert.ok(arrived.body.trip.arrivedAt);
  // Sin cotización no hay segundo pago ni inicio
  assert.equal((await request(app).post(`/payments/service/${rid}/checkout`).set(auth(cliToken))).status, 409);
  assert.equal((await request(app).post(`/requests/${rid}/start`).set(auth(proToken))).status, 409);

  // 9. Cotización tras el diagnóstico (se puede corregir antes del pago)
  await request(app).post(`/requests/${rid}/quote`).set(auth(proToken)).send({ agreedPrice: 90_000, quoteNote: 'Cambio de grifo y empaques' }).expect(200);
  const quoted = await request(app).post(`/requests/${rid}/quote`).set(auth(proToken)).send({ agreedPrice: 100_000, quoteNote: 'Cambio de grifo, empaques y sifón' });
  assert.equal(quoted.body.stage, 'PAY_SERVICE');
  assert.deepEqual(quoted.body.charge, { serviceAmount: 100_000, commissionAmount: 3_000, totalAmount: 103_000 });
  assert.equal(quoted.body.commission.reduced, false);

  // 10. Pago del valor cotizado: rechazo, luego aprobado
  const co1 = await request(app).post(`/payments/service/${rid}/checkout`).set(auth(cliToken));
  assert.equal(co1.body.payment.kind, 'SERVICE');
  assert.equal(co1.body.payment.totalAmount, 103_000);
  await request(app).post(`/payments/${co1.body.payment.id}/simulate`).set(auth(cliToken)).send({ status: 'DECLINED' }).expect(200);
  const co2 = await request(app).post(`/payments/service/${rid}/checkout`).set(auth(cliToken));
  const approved = await request(app).post(`/payments/${co2.body.payment.id}/simulate`).set(auth(cliToken)).send({ status: 'APPROVED' });
  assert.equal(approved.body.status, 'APPROVED');
  assert.equal((await request(app).post(`/payments/service/${rid}/checkout`).set(auth(cliToken))).status, 409);
  assert.equal((await request(app).post(`/requests/${rid}/quote`).set(auth(proToken)).send({ agreedPrice: 200_000, quoteNote: 'Intento de cambio' })).status, 409);
  assert.equal((await request(app).post(`/requests/${rid}/cancel`).set(auth(cliToken)).send({ reason: 'ya no lo necesito' })).status, 409);

  // 11. En proceso; el dinero del profesional queda retenido hasta que ambos confirmen
  assert.equal((await request(app).post(`/requests/${rid}/start`).set(auth(proToken))).body.status, 'IN_PROGRESS');
  const heldStats = await request(app).get('/professionals/me/stats').set(auth(proToken));
  assert.equal(heldStats.body.income.held, 100_000, 'el valor del servicio queda retenido');
  assert.equal(heldStats.body.income.total, 8_000, 'la visita se libera de una vez');
  // 11b. Reclamación abierta: bloquea la finalización y mantiene el dinero retenido hasta que el admin resuelva
  const claim = await request(app).post('/claims').set(auth(cliToken)).send({ requestId: rid, type: 'QUALITY', description: 'El grifo quedó goteando después del arreglo' });
  assert.equal(claim.status, 201, JSON.stringify(claim.body));
  assert.equal((await request(app).post('/claims').set(auth(cliToken)).send({ requestId: rid, type: 'OTHER', description: 'Otra reclamación sobre lo mismo, repetida' })).status, 409);
  assert.equal((await request(app).post('/claims').set(auth(intruder.body.token)).send({ requestId: rid, type: 'OTHER', description: 'No soy parte de esta solicitud pero reclamo' })).status, 403);
  assert.equal((await request(app).post(`/requests/${rid}/complete`).set(auth(proToken))).status, 409);
  const admin = (await request(app).post('/auth/login').send({ email: 'admin@netjob.co', password: 'NetJob2026!' })).body.token;
  assert.equal((await request(app).patch(`/admin/claims/${claim.body.id}`).set(auth(cliToken)).send({ status: 'RESOLVED' })).status, 403);
  const openClaims = await request(app).get('/admin/claims').set(auth(admin));
  assert.ok(openClaims.body.some((c: any) => c.id === claim.body.id));
  const resolved = await request(app).patch(`/admin/claims/${claim.body.id}`).set(auth(admin))
    .send({ status: 'RESOLVED', action: 'WARRANTY_VISIT', resolution: 'El profesional vuelve a ajustar el grifo sin costo.' });
  assert.equal(resolved.body.status, 'RESOLVED');

  const proDone = await request(app).post(`/requests/${rid}/complete`).set(auth(proToken));
  assert.equal(proDone.body.status, 'IN_PROGRESS', 'con una sola confirmación no se finaliza');
  assert.ok(proDone.body.proConfirmedAt);
  assert.equal((await request(app).post(`/requests/${rid}/complete`).set(auth(proToken))).status, 409, 'no confirma dos veces');
  assert.equal((await request(app).post(`/requests/${rid}/review`).set(auth(cliToken)).send({ rating: 5 })).status, 409);
  const done = await request(app).post(`/requests/${rid}/complete`).set(auth(cliToken));
  assert.equal(done.body.status, 'COMPLETED');
  const servicePayment = done.body.payments.find((p: any) => p.kind === 'SERVICE' && p.status === 'APPROVED');
  assert.equal(servicePayment.payoutStatus, 'RELEASED');
  assert.ok(new Date(done.body.warrantyUntil).getTime() > Date.now() + 29 * 864e5, 'empieza la garantía de 30 días');
  // Comprobante: el cliente ve la tarifa; el profesional ve lo que recibe
  const receipt = await request(app).get(`/payments/${servicePayment.id}/receipt`).set(auth(cliToken));
  assert.equal(receipt.body.total, 103_000);
  assert.equal(receipt.body.payout, 'Liberado al profesional');
  assert.equal((await request(app).get(`/payments/${servicePayment.id}/receipt`).set(auth(proToken))).body.total, 100_000);
  assert.equal((await request(app).get(`/payments/${servicePayment.id}/receipt`).set(auth(intruder.body.token))).status, 404);

  // 12. Reseña (solo una vez)
  await request(app).post(`/requests/${rid}/review`).set(auth(cliToken)).send({ rating: 4, comment: 'Muy puntual' }).expect(201);
  assert.equal((await request(app).post(`/requests/${rid}/review`).set(auth(cliToken)).send({ rating: 5 })).status, 409);

  // 12b. El profesional califica al cliente (una vez); solo el profesional puede hacerlo
  assert.equal((await request(app).post(`/requests/${rid}/client-review`).set(auth(cliToken)).send({ rating: 5 })).status, 403);
  await request(app).post(`/requests/${rid}/client-review`).set(auth(proToken)).send({ rating: 5, comment: 'Clienta muy amable y pagó a tiempo' }).expect(201);
  assert.equal((await request(app).post(`/requests/${rid}/client-review`).set(auth(proToken)).send({ rating: 4 })).status, 409);
  const cliId = cliReg.body.user.id;
  const asClient = await request(app).get(`/reviews/client/${cliId}`).set(auth(cliToken));
  assert.equal(asClient.body.client.clientRatingAvg, 5);
  assert.equal(asClient.body.reviews.length, 1);
  assert.equal((await request(app).get(`/reviews/client/${cliId}`).set(auth(proToken))).status, 200);
  assert.equal((await request(app).get(`/reviews/client/${cliId}`).set(auth(intruder.body.token))).status, 404, 'otro cliente no ve las reseñas');
  const detailAfter = await request(app).get(`/requests/${rid}`).set(auth(proToken));
  assert.equal(detailAfter.body.clientReview.rating, 5);

  // 13. Historiales: el profesional recibe visita + servicio
  const stats = await request(app).get('/professionals/me/stats').set(auth(proToken));
  assert.equal(stats.body.income.total, 108_000);
  const cliPayments = await request(app).get('/payments').set(auth(cliToken));
  assert.equal(cliPayments.body.filter((p: any) => p.status === 'APPROVED' && p.kind !== 'SUBSCRIPTION').length, 2);
  const value = (await request(app).get('/subscriptions/me').set(auth(proToken))).body.value;
  assert.equal(value.requests, 1);
  assert.equal(value.income, 108_000);
  assert.ok(value.views >= 1, 'la visita del cliente al perfil se cuenta');

  // 14. Recomendados: el cliente ve primero al profesional que ya contrató
  const rec = await request(app).get('/professionals/recommended').query(NEAR).set(auth(cliToken));
  assert.equal(rec.body.items[0].name, proName);
  assert.equal(rec.body.items[0].hiredBefore, true);
  assert.deepEqual(rec.body.basedOn, ['Plomería']);
});

test('fidelización: referido y cliente frecuente pagan 1 % en lugar de 3 %', async () => {
  const { computeServiceCharge: charge } = await import('../src/lib/money.js');
  assert.deepEqual(charge(100_000, 0.01), { serviceAmount: 100_000, commissionAmount: 1_000, totalAmount: 101_000 });

  // Quien invita es un cliente; el invitado empieza con un servicio a tarifa reducida
  const host = await request(app).post('/auth/register').send({ name: 'Ana Invita', email: `host-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact });
  const code = (await request(app).get('/me/benefits').set(auth(host.body.token))).body.referralCode;
  assert.equal((await request(app).post('/auth/register').send({ name: 'X', email: `bad-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact, referralCode: 'NOEXISTE' })).status, 400);
  const guest = await request(app).post('/auth/register').send({ name: 'Beto Invitado', email: `guest-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact, referralCode: code.toLowerCase() });
  assert.equal(guest.status, 201, JSON.stringify(guest.body));
  const gt = guest.body.token;
  assert.equal((await request(app).get('/me/benefits').set(auth(gt))).body.credits, 1);
  assert.equal((await request(app).get('/me/benefits').set(auth(host.body.token))).body.invited, 1);

  // Servicio completo con el plomero demo
  const pro = (await request(app).post('/auth/login').send({ email: 'plomero@netjob.co', password: 'NetJob2026!' })).body.token;
  const services = (await request(app).get('/services').set(auth(pro))).body;
  const when = new Date(Date.now() + 20 * 864e5 + Math.floor(Math.random() * 500) * 3 * 3600e3).toISOString();
  const rq = await request(app).post('/requests').set(auth(gt)).send({ serviceId: services[0].id, description: 'Tengo una fuga en el lavamanos', address: 'Cra 7 # 72-10, Bogotá', scheduledAt: when });
  const id = rq.body.id;
  assert.equal((await request(app).post(`/requests/${id}/accept`).set(auth(pro)).send({})).status, 200);
  const dg = await request(app).post(`/payments/service/${id}/checkout`).set(auth(gt));
  await request(app).post(`/payments/${dg.body.payment.id}/simulate`).set(auth(gt)).send({ status: 'APPROVED' }).expect(200);
  const quoted = await request(app).post(`/requests/${id}/quote`).set(auth(pro)).send({ agreedPrice: 200_000, quoteNote: 'Cambio de sifón y empaques' });
  assert.deepEqual(quoted.body.charge, { serviceAmount: 200_000, commissionAmount: 2_000, totalAmount: 202_000 });
  assert.equal(quoted.body.commission.reduced, true);
  const co = await request(app).post(`/payments/service/${id}/checkout`).set(auth(gt));
  assert.equal(co.body.payment.totalAmount, 202_000);
  assert.equal(co.body.payment.loyaltyApplied, true);
  await request(app).post(`/payments/${co.body.payment.id}/simulate`).set(auth(gt)).send({ status: 'APPROVED' }).expect(200);
  assert.equal((await request(app).get('/me/benefits').set(auth(gt))).body.credits, 0, 'el beneficio se consume al pagar');
  // El profesional siempre recibe el valor completo
  await request(app).post(`/requests/${id}/start`).set(auth(pro)).expect(200);
  await request(app).post(`/requests/${id}/complete`).set(auth(pro)).expect(200);
  const done = await request(app).post(`/requests/${id}/complete`).set(auth(gt));
  assert.equal(done.body.status, 'COMPLETED');
  assert.equal(done.body.charge.totalAmount, 202_000, 'después de pagar se muestra lo cobrado');
  // Al terminar el primer servicio del invitado, quien invitó gana su tarifa reducida
  const hostBenefits = (await request(app).get('/me/benefits').set(auth(host.body.token))).body;
  assert.equal(hostBenefits.credits, 1);
  assert.equal(hostBenefits.rewarded, 1);
});

test('reclamación resuelta a favor del cliente: el dinero retenido se devuelve', async () => {
  const pro = (await request(app).post('/auth/login').send({ email: 'electricista@netjob.co', password: 'NetJob2026!' })).body.token;
  const admin = (await request(app).post('/auth/login').send({ email: 'admin@netjob.co', password: 'NetJob2026!' })).body.token;
  const cli = (await request(app).post('/auth/register').send({ name: 'Rita Reclama', email: `rita-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact })).body.token;
  const services = (await request(app).get('/services').set(auth(pro))).body;
  const when = new Date(Date.now() + 40 * 864e5 + Math.floor(Math.random() * 500) * 3 * 3600e3).toISOString();
  const id = (await request(app).post('/requests').set(auth(cli)).send({ serviceId: services[0].id, description: 'Se dispara el breaker de la cocina', address: 'Cl 45 # 13-20, Bogotá', scheduledAt: when })).body.id;
  await request(app).post(`/requests/${id}/accept`).set(auth(pro)).send({}).expect(200);
  const dg = await request(app).post(`/payments/service/${id}/checkout`).set(auth(cli));
  await request(app).post(`/payments/${dg.body.payment.id}/simulate`).set(auth(cli)).send({ status: 'APPROVED' }).expect(200);
  await request(app).post(`/requests/${id}/quote`).set(auth(pro)).send({ agreedPrice: 150_000, quoteNote: 'Cambio de breaker y revisión' }).expect(200);
  const co = await request(app).post(`/payments/service/${id}/checkout`).set(auth(cli));
  await request(app).post(`/payments/${co.body.payment.id}/simulate`).set(auth(cli)).send({ status: 'APPROVED' }).expect(200);
  await request(app).post(`/requests/${id}/start`).set(auth(pro)).expect(200);

  const claim = await request(app).post('/claims').set(auth(cli)).send({ requestId: id, type: 'NO_SHOW', description: 'El profesional nunca llegó a hacer el trabajo pagado' });
  assert.equal(claim.status, 201);
  const out = await request(app).patch(`/admin/claims/${claim.body.id}`).set(auth(admin))
    .send({ status: 'RESOLVED', action: 'REFUND_CLIENT', resolution: 'Se confirma que el profesional no asistió a la cita.' });
  assert.equal(out.body.action, 'REFUND_CLIENT');
  const after = await request(app).get(`/requests/${id}`).set(auth(cli));
  assert.equal(after.body.status, 'CANCELLED');
  assert.equal(after.body.payments.find((p: any) => p.kind === 'SERVICE' && p.status === 'APPROVED').payoutStatus, 'REFUNDED');
  assert.equal((await request(app).patch(`/admin/claims/${claim.body.id}`).set(auth(admin)).send({ status: 'REJECTED', resolution: 'Segundo cierre no permitido' })).status, 409);
});

test('verificación de identidad: documentos privados y aprobación del administrador', async () => {
  const reg = await request(app).post('/auth/register').send({ name: `Vero ${run}`, email: `vero-${run}@test.co`, password: 'secreto123', role: 'PROFESSIONAL', ...contact });
  const t = reg.body.token;
  const admin = (await request(app).post('/auth/login').send({ email: 'admin@netjob.co', password: 'NetJob2026!' })).body.token;
  const other = (await request(app).post('/auth/register').send({ name: 'Curioso', email: `cur-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact })).body.token;
  assert.equal((await request(app).post('/verification/submit').set(auth(t))).status, 400, 'no se envía sin los cuatro documentos');
  let state: any;
  for (const kind of ['idFront', 'idBack', 'selfie', 'backgroundCheck']) {
    state = (await request(app).post(`/verification/documents/${kind}`).set(auth(t)).attach('file', png, 'doc.png').expect(200)).body;
  }
  const file = state.documents.selfie;
  assert.equal((await request(app).get(`/uploads/${file}`)).status, 404, 'los documentos no son archivos públicos');
  assert.equal((await request(app).get(`/verification/files/${file}`)).status, 401);
  assert.equal((await request(app).get(`/verification/files/${file}`).set(auth(other))).status, 403);
  assert.equal((await request(app).get(`/verification/files/${file}`).set(auth(t))).status, 200);
  assert.equal((await request(app).post('/verification/submit').set(auth(t))).body.status, 'PENDING');
  const queue = await request(app).get('/admin/verifications').set(auth(admin));
  const mine = queue.body.find((v: any) => v.user.name === `Vero ${run}`);
  assert.ok(mine);
  assert.equal((await request(app).get(`/verification/files/${mine.idFrontFile}`).set(auth(admin))).status, 200);
  assert.equal((await request(app).patch(`/admin/verifications/${mine.id}`).set(auth(admin)).send({ approve: false })).status, 400, 'el rechazo exige un motivo');
  await request(app).patch(`/admin/verifications/${mine.id}`).set(auth(admin)).send({ approve: true }).expect(200);
  const final = await request(app).get('/verification').set(auth(t));
  assert.equal(final.body.status, 'APPROVED');
  assert.equal(final.body.verified, true);
});

test('suspensión temporal: bloquea el acceso y se levanta sola al vencer', async () => {
  const admin = (await request(app).post('/auth/login').send({ email: 'admin@netjob.co', password: 'NetJob2026!' })).body.token;
  const reg = await request(app).post('/auth/register').send({ name: 'Susana Suspendida', email: `sus-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact });
  const id = reg.body.user.id;
  await request(app).patch(`/admin/users/${id}`).set(auth(admin)).send({ status: 'SUSPENDED', days: 7, reason: 'Incumplimiento reiterado' }).expect(200);
  const blocked = await request(app).get('/me').set(auth(reg.body.token));
  assert.equal(blocked.status, 403);
  assert.match(blocked.body.error, /Incumplimiento reiterado/);
  await prisma.user.update({ where: { id }, data: { suspendedUntil: new Date(Date.now() - 1000) } });
  assert.equal((await request(app).get('/me').set(auth(reg.body.token))).status, 200, 'vencida la suspensión, la cuenta se reactiva');
});

test('perfil destacado y plan Premium: compra, días incluidos y prioridad en la búsqueda', async () => {
  const pro = (await request(app).post('/auth/login').send({ email: 'carpintero@netjob.co', password: 'NetJob2026!' })).body.token;
  const promos = await request(app).get('/promotions').set(auth(pro));
  assert.equal(promos.body.options.length, 3);
  const before = promos.body.featuredUntil ? new Date(promos.body.featuredUntil).getTime() : Date.now();
  const co = await request(app).post('/promotions/checkout').set(auth(pro)).send({ optionId: 'D7' });
  assert.equal(co.body.payment.kind, 'PROMOTION');
  assert.equal(co.body.payment.totalAmount, 14_900);
  await request(app).post(`/payments/${co.body.payment.id}/simulate`).set(auth(pro)).send({ status: 'APPROVED' }).expect(200);
  const after = new Date((await request(app).get('/promotions').set(auth(pro))).body.featuredUntil).getTime();
  assert.ok(after >= before + 7 * 864e5 - 5000, 'se suman 7 días de perfil destacado');
  // En Medellín el carpintero destacado sale primero y con la etiqueta
  const s = await request(app).get('/professionals').query({ lat: 6.2442, lng: -75.5812 });
  const row = s.body.items.find((i: any) => i.name === 'María Fernanda López');
  assert.equal(row.featured, true);
  // El plomero demo es Premium: su insignia es visible para el cliente
  const bog = await request(app).get('/professionals').query({ lat: 4.676, lng: -74.048 });
  assert.equal(bog.body.items.find((i: any) => i.name === 'Carlos Rodríguez').planBadge, 'Premium');
  const insights = await request(app).get('/professionals/me/insights').set(auth((await request(app).post('/auth/login').send({ email: 'plomero@netjob.co', password: 'NetJob2026!' })).body.token));
  assert.equal(insights.status, 200);
  assert.equal(insights.body.months.length, 6);
});

test('un perfil profesional incompleto no aparece en la búsqueda', async () => {
  const reg = await request(app).post('/auth/register').send({
    name: `Incompleto ${run}`, email: `inc-${run}@test.co`, password: 'secreto123', role: 'PROFESSIONAL', ...contact,
  });
  const t = reg.body.token;
  await request(app).patch('/professionals/me/profile').set(auth(t)).send({ headline: 'Pintor', city: 'Cali', ...CALI }).expect(200);
  const plans = (await request(app).get('/subscriptions/plans')).body;
  const co = await request(app).post('/subscriptions/checkout').set(auth(t)).send({ planId: plans[0].id });
  await request(app).post(`/payments/${co.body.payment.id}/simulate`).set(auth(t)).send({ status: 'APPROVED' }).expect(200);
  const cat = (await request(app).get('/categories')).body[0];
  await request(app).post('/services').set(auth(t)).send({ categoryId: cat.id, title: 'Pintura', description: 'Pintura de interiores', price: 50_000 }).expect(201);
  const s = await request(app).get('/professionals').query(NEAR);
  assert.ok(!s.body.items.some((i: any) => i.name === `Incompleto ${run}`));
});

test('no se aceptan dos servicios a la misma hora', async () => {
  const login = await request(app).post('/auth/login').send({ email: 'plomero@netjob.co', password: 'NetJob2026!' });
  const proToken = login.body.token;
  const cli = await request(app).post('/auth/register').send({ name: 'Doble', email: `doble-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact });
  const services = (await request(app).get('/services').set(auth(proToken))).body;
  const when = new Date(Date.now() + 10 * 864e5);
  when.setUTCMinutes(0, 0, 0);
  const mk = async (offsetMin: number) =>
    (await request(app).post('/requests').set(auth(cli.body.token)).send({
      serviceId: services[0].id, description: 'Necesito revisión urgente', address: 'Cra 7 # 72-10, Bogotá',
      scheduledAt: new Date(when.getTime() + offsetMin * 60000).toISOString(),
    })).body.id;
  const a = await mk(0);
  const b = await mk(60);
  assert.equal((await request(app).post(`/requests/${a}/accept`).set(auth(proToken)).send({})).status, 200);
  assert.equal((await request(app).post(`/requests/${b}/accept`).set(auth(proToken)).send({})).status, 409);
  await request(app).post(`/requests/${a}/cancel`).set(auth(proToken)).send({ reason: 'prueba automática' }).expect(200);
  await request(app).post(`/requests/${b}/reject`).set(auth(proToken)).send({}).expect(200);
});

test('el registro exige celular, departamento y municipio', async () => {
  const base = { name: 'Sin Datos', email: `sin-${run}@test.co`, password: 'secreto123', role: 'CLIENT' };
  assert.equal((await request(app).post('/auth/register').send(base)).status, 400);
  assert.equal((await request(app).post('/auth/register').send({ ...base, ...contact, phone: '12345' })).status, 400);
  const ok = await request(app).post('/auth/register').send({ ...base, ...contact, phone: '+57 310 555 1234' });
  assert.equal(ok.status, 201, JSON.stringify(ok.body));
  assert.equal(ok.body.user.phone, '3105551234');
  assert.equal(ok.body.user.department, 'Valle del Cauca');
});

test('el registro público no permite crear administradores', async () => {
  const r = await request(app).post('/auth/register').send({ name: 'Hacker', email: `adm-${run}@test.co`, password: 'secreto123', role: 'ADMIN' });
  assert.equal(r.status, 400);
});
