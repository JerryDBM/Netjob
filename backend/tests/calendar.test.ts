/**
 * Agenda de citas, visita de diagnóstico con valor propio, recordatorios y herramientas
 * del administrador (categorías, pagos y configuración general).
 * Requiere la base de desarrollo con seed y PAYMENTS_MOCK=true.
 */
process.env.NODE_ENV = 'test';
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { prisma } from '../src/db.js';
import { config } from '../src/config.js';
import { sendAppointmentReminders } from '../src/lib/calendar.js';

const app = createApp();
const run = Date.now().toString(36);
const auth = (t: string) => ({ Authorization: `Bearer ${t}` });
const contact = { phone: '300 123 4567', department: 'Cundinamarca', city: 'Bogotá' };
const login = async (email: string) => (await request(app).post('/auth/login').send({ email, password: 'NetJob2026!' })).body.token as string;

let pro: string;
let admin: string;
let client: string;
let serviceId: string;
let proProfileId: string;
let originalFee: number;
const created: string[] = [];

/** Fecha futura a la hora en punto, `days` días adelante (en UTC) más `hours` horas. */
const at = (days: number, hours = 0) => {
  const d = new Date(Date.now() + days * 864e5);
  d.setUTCHours(15 + hours, 0, 0, 0);
  return d;
};

before(async () => {
  pro = await login('plomero@netjob.co');
  admin = await login('admin@netjob.co');
  const cli = await request(app).post('/auth/register').send({ name: 'Agenda Prueba', email: `agenda-${run}@test.co`, password: 'secreto123', role: 'CLIENT', ...contact });
  client = cli.body.token;
  const profile = (await request(app).get('/professionals/me/profile').set(auth(pro))).body;
  proProfileId = profile.id;
  originalFee = profile.diagnosticFee;
  serviceId = (await request(app).get('/services').set(auth(pro))).body[0].id;
  // Corridas anteriores pudieron dejar citas o bloqueos en esas fechas
  await prisma.calendarBlock.deleteMany({ where: { professionalId: proProfileId } });
  await prisma.serviceRequest.updateMany({
    where: { professionalId: proProfileId, status: { in: ['PENDING', 'ACCEPTED'] }, scheduledAt: { gte: new Date() } },
    data: { status: 'CANCELLED' },
  });
});

after(async () => {
  await request(app).patch('/professionals/me/profile').set(auth(pro)).send({ diagnosticFee: originalFee });
  await prisma.calendarBlock.deleteMany({ where: { professionalId: proProfileId } });
  await prisma.serviceRequest.updateMany({ where: { id: { in: created }, status: { in: ['PENDING', 'ACCEPTED'] } }, data: { status: 'CANCELLED' } });
  await prisma.$disconnect();
});

async function newRequest(when: Date) {
  const r = await request(app).post('/requests').set(auth(client)).send({
    serviceId, description: 'Gotea la llave del lavaplatos', address: 'Cra 7 # 72-10, Bogotá', scheduledAt: when.toISOString(),
  });
  if (r.status === 201) created.push(r.body.id);
  return r;
}

test('el profesional fija el valor de la visita (máximo 35.000) y se copia en la solicitud', async () => {
  assert.equal(config.maxDiagnosticFee, 35_000);
  const tooHigh = await request(app).patch('/professionals/me/profile').set(auth(pro)).send({ diagnosticFee: 40_000 });
  assert.equal(tooHigh.status, 400);
  await request(app).patch('/professionals/me/profile').set(auth(pro)).send({ diagnosticFee: 25_000 }).expect(200);
  const pub = (await request(app).get(`/professionals/${proProfileId}`)).body;
  assert.equal(pub.diagnosticFee, 25_000);
  const r = await newRequest(at(12));
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.diagnosticFee, 25_000);
  // Un cambio posterior no afecta solicitudes ya creadas
  await request(app).patch('/professionals/me/profile').set(auth(pro)).send({ diagnosticFee: 10_000 }).expect(200);
  assert.equal((await request(app).get(`/requests/${r.body.id}`).set(auth(client))).body.diagnosticFee, 25_000);
});

test('visita gratis: sin pago de diagnóstico, el profesional cotiza y el cliente paga el valor final', async () => {
  await request(app).patch('/professionals/me/profile').set(auth(pro)).send({ diagnosticFee: 0 }).expect(200);
  const r = (await newRequest(at(13))).body;
  assert.equal(r.diagnosticFee, 0);
  const accepted = (await request(app).post(`/requests/${r.id}/accept`).set(auth(pro)).send({})).body;
  assert.equal(accepted.stage, 'DIAGNOSIS');
  assert.equal(accepted.diagnosticFree, true);
  await request(app).post(`/requests/${r.id}/quote`).set(auth(pro)).send({ agreedPrice: 90_000, quoteNote: 'Cambio de empaque y grifería' }).expect(200);
  const co = await request(app).post(`/payments/service/${r.id}/checkout`).set(auth(client)).send({});
  assert.equal(co.status, 201, JSON.stringify(co.body));
  assert.equal(co.body.payment.kind, 'SERVICE');
  assert.equal(co.body.charge.totalAmount, 92_700);
});

test('reprogramar: una parte propone, la otra acepta y la cita cambia de hora', async () => {
  await request(app).patch('/professionals/me/profile').set(auth(pro)).send({ diagnosticFee: 8_000 }).expect(200);
  const r = (await newRequest(at(15))).body;
  await request(app).post(`/requests/${r.id}/accept`).set(auth(pro)).send({}).expect(200);
  const newTime = at(16, 2);
  const proposed = await request(app).post(`/requests/${r.id}/reschedule`).set(auth(client)).send({ scheduledAt: newTime.toISOString(), note: 'Ese día no estoy' });
  assert.equal(proposed.status, 200, JSON.stringify(proposed.body));
  assert.equal(proposed.body.reschedule.byMe, true);
  // Quien propone no puede aceptarse a sí mismo
  assert.equal((await request(app).post(`/requests/${r.id}/reschedule/respond`).set(auth(client)).send({ accept: true })).status, 403);
  const ok = await request(app).post(`/requests/${r.id}/reschedule/respond`).set(auth(pro)).send({ accept: true });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal(new Date(ok.body.scheduledAt).getTime(), newTime.getTime());
  assert.equal(ok.body.reschedule, null);
  assert.ok(ok.body.history.some((h: any) => /reprogramada/.test(h.note ?? '')));

  // Rechazo: la cita sigue igual
  await request(app).post(`/requests/${r.id}/reschedule`).set(auth(pro)).send({ scheduledAt: at(17).toISOString() }).expect(200);
  const no = await request(app).post(`/requests/${r.id}/reschedule/respond`).set(auth(client)).send({ accept: false });
  assert.equal(new Date(no.body.scheduledAt).getTime(), newTime.getTime());
});

test('bloqueos: el profesional bloquea días y no le pueden pedir ni mover citas ahí', async () => {
  const from = at(20, -15); // 00:00 UTC del día 20
  const to = new Date(from.getTime() + 2 * 864e5);
  const block = await request(app).post('/calendar/blocks').set(auth(pro)).send({ startsAt: from, endsAt: to, reason: 'Vacaciones' });
  assert.equal(block.status, 201, JSON.stringify(block.body));
  // El cliente ve los días bloqueados en el perfil (sin el motivo)
  const pub = (await request(app).get(`/professionals/${proProfileId}`)).body;
  assert.ok(pub.blocks.length >= 1);
  assert.equal(pub.blocks[0].reason, undefined);
  const inside = await newRequest(at(20, 2));
  assert.equal(inside.status, 409);
  assert.match(inside.body.error, /no tiene agenda/);
  // Tampoco se puede proponer mover una cita a esos días
  const r = (await newRequest(at(23))).body;
  assert.equal((await request(app).post(`/requests/${r.id}/reschedule`).set(auth(client)).send({ scheduledAt: at(21).toISOString() })).status, 409);
  // No se puede bloquear encima de una cita aceptada
  await request(app).post(`/requests/${r.id}/accept`).set(auth(pro)).send({}).expect(200);
  const over = await request(app).post('/calendar/blocks').set(auth(pro)).send({ startsAt: at(23, -2), endsAt: at(23, 4) });
  assert.equal(over.status, 409);
  await request(app).delete(`/calendar/blocks/${block.body.id}`).set(auth(pro)).expect(204);
});

test('agenda: citas del rango con nota privada para cada parte', async () => {
  const r = (await newRequest(at(25))).body;
  await request(app).put(`/requests/${r.id}/note`).set(auth(pro)).send({ note: 'Llevar llave de expansión' }).expect(200);
  await request(app).put(`/requests/${r.id}/note`).set(auth(client)).send({ note: 'Dejar razón en portería' }).expect(200);
  const range = { from: at(24).toISOString(), to: at(26).toISOString() };
  const proCal = (await request(app).get('/calendar').query(range).set(auth(pro))).body;
  const mine = proCal.appointments.find((a: any) => a.id === r.id);
  assert.equal(mine.myNote, 'Llevar llave de expansión');
  assert.equal(mine.counterpart.name, 'Agenda Prueba');
  assert.equal(mine.description, 'Gotea la llave del lavaplatos');
  const cliCal = (await request(app).get('/calendar').query(range).set(auth(client))).body;
  assert.equal(cliCal.appointments.find((a: any) => a.id === r.id).myNote, 'Dejar razón en portería');
  assert.deepEqual(cliCal.blocks, []);
});

test('recordatorios: un día antes y una hora antes, sin repetirse', async () => {
  const now = new Date();
  const soon = new Date(now.getTime() + 20 * 3600 * 1000);
  soon.setUTCMinutes(0, 0, 0);
  const r = (await newRequest(soon)).body;
  await request(app).post(`/requests/${r.id}/accept`).set(auth(pro)).send({}).expect(200);
  const reminders = () => prisma.notification.count({ where: { type: 'REMINDER', data: { path: ['requestId'], equals: r.id } } });
  await sendAppointmentReminders(now);
  assert.equal(await reminders(), 2); // cliente y profesional
  await sendAppointmentReminders(now);
  assert.equal(await reminders(), 2);
  await sendAppointmentReminders(new Date(soon.getTime() - 30 * 60 * 1000));
  assert.equal(await reminders(), 4);
});

test('admin: configuración general editable y validada', async () => {
  const original = (await request(app).get('/admin/settings').set(auth(admin))).body;
  assert.equal(original.maxDiagnosticFee, config.maxDiagnosticFee);
  assert.equal((await request(app).put('/admin/settings').set(auth(admin)).send({ loyaltyCommissionRate: 0.5 })).status, 400);
  const saved = await request(app).put('/admin/settings').set(auth(admin)).send({ searchRadiusKm: 15, warrantyDays: 45 });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(config.searchRadiusKm, 15);
  assert.equal((await request(app).get('/config')).body.warrantyDays, 45);
  assert.equal((await request(app).get('/admin/settings').set(auth(client))).status, 403);
  await request(app).put('/admin/settings').set(auth(admin)).send(original).expect(200);
});

test('admin: categorías y pagos con filtros y totales', async () => {
  const slug = `prueba-${run}`;
  const c = await request(app).post('/admin/categories').set(auth(admin)).send({ name: `Prueba ${run}`, slug, icon: 'build' });
  assert.equal(c.status, 201);
  await request(app).patch(`/admin/categories/${c.body.id}`).set(auth(admin)).send({ active: false }).expect(200);
  await prisma.category.delete({ where: { id: c.body.id } });
  const p = (await request(app).get('/admin/payments').query({ status: 'APPROVED', kind: 'SUBSCRIPTION' }).set(auth(admin))).body;
  assert.ok(Array.isArray(p.items));
  assert.ok(p.items.every((x: any) => x.kind === 'SUBSCRIPTION' && x.status === 'APPROVED'));
  assert.equal(typeof p.totals.collected, 'number');
});
