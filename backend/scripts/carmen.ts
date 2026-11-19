/**
 * Barrios de El Carmen de Bolívar con su punto aproximado (para los datos de prueba).
 * El casco urbano es pequeño: todos quedan a menos de 2 km del centro.
 */
export const CARMEN = { name: 'El Carmen de Bolívar', dept: 'Bolívar', lat: 9.7174, lng: -75.1202 };

export const CARMEN_BARRIOS: [name: string, lat: number, lng: number][] = [
  ['Centro', 9.7174, -75.1202],
  ['Barrio Nuevo', 9.7205, -75.1238],
  ['El Silencio', 9.7142, -75.1251],
  ['Las Palmas', 9.7231, -75.1179],
  ['San José', 9.7158, -75.1163],
  ['Villa Ana', 9.7112, -75.1214],
  ['Caracolí', 9.7246, -75.1226],
  ['Pueblo Nuevo', 9.7193, -75.1141],
  ['La Floresta', 9.7127, -75.1178],
  ['San Luis', 9.7262, -75.1198],
  ['Las Margaritas', 9.7098, -75.1236],
  ['El Bosque', 9.7219, -75.1262],
  ['Montecarlo', 9.7151, -75.1288],
  ['La Unión', 9.7276, -75.1159],
  ['Alto de Julio', 9.7087, -75.1172],
];

/** Barrio principal, dos vecinos para la zona de cobertura y un punto con ±200 m de variación. */
export function carmenPlaceFor(i: number) {
  const [name, lat, lng] = CARMEN_BARRIOS[i % CARMEN_BARRIOS.length];
  const near = [CARMEN_BARRIOS[(i + 1) % CARMEN_BARRIOS.length][0], CARMEN_BARRIOS[(i + 6) % CARMEN_BARRIOS.length][0]];
  const jitter = (k: number) => (((i * k) % 5) - 2) * 0.0008;
  return { barrio: name, areas: [name, ...near], lat: lat + jitter(31), lng: lng + jitter(17) };
}
