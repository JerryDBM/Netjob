import { test } from 'node:test';
import assert from 'node:assert/strict';
import { availabilityStatus, inSchedule } from '../src/lib/availability.js';
import { instruction } from '../src/routes/routing.js';

// Lunes 8:00–17:00 (hora de Colombia, UTC−5)
const slots = [{ dayOfWeek: 1, startTime: '08:00', endTime: '17:00' }];
// 2026-11-09 es lunes. 16:59 Colombia = 21:59 UTC; 17:01 Colombia = 22:01 UTC
const at = (utc: string) => new Date(`2026-11-09T${utc}:00Z`);

test('disponible dentro del horario y no disponible después', () => {
  assert.equal(inSchedule(slots, at('13:00')), true, '8:00 Colombia');
  assert.equal(inSchedule(slots, at('21:59')), true, '16:59 Colombia');
  assert.equal(inSchedule(slots, at('22:01')), false, '17:01 Colombia: se quita el disponible');
  assert.equal(inSchedule(slots, at('12:59')), false, '7:59 Colombia');
});

test('estado de disponibilidad: hasta cuándo y cuándo vuelve', () => {
  assert.deepEqual(availabilityStatus(slots, true, at('15:00')), { availableNow: true, until: '17:00', next: null, enabled: true });
  const after = availabilityStatus(slots, true, at('22:01'));
  assert.equal(after.availableNow, false);
  assert.deepEqual(after.next, { day: 'lunes', time: '08:00' }, 'vuelve el próximo lunes');
  assert.equal(availabilityStatus(slots, false, at('15:00')).availableNow, false, 'pausado por el profesional');
});

test('indicaciones de la ruta en español', () => {
  const step = (type: string, modifier?: string, name = 'Calle 72', exit?: number) =>
    ({ maneuver: { type, modifier, exit, location: [0, 0] as [number, number] }, name, distance: 0, duration: 0 });
  assert.equal(instruction(step('turn', 'right')), 'Gira a la derecha hacia Calle 72');
  assert.equal(instruction(step('roundabout', undefined, 'Av. 30', 2)), 'En la glorieta toma la 2.ª salida hacia Av. 30');
  assert.equal(instruction(step('arrive')), 'Llegaste al domicilio del cliente');
});
