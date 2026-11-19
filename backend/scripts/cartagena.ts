/**
 * Barrios de Cartagena con su punto aproximado (para los datos de prueba). Todos quedan a
 * menos de 12 km del centro de la ciudad, así un cliente en Cartagena ve a todos los
 * profesionales demo.
 */
export const CARTAGENA = { name: 'Cartagena', dept: 'Bolívar', lat: 10.391, lng: -75.4794 };

export const BARRIOS: [name: string, lat: number, lng: number][] = [
  ['Bocagrande', 10.3995, -75.553],
  ['Castillogrande', 10.393, -75.552],
  ['Manga', 10.411, -75.534],
  ['Getsemaní', 10.421, -75.547],
  ['Centro Histórico', 10.4235, -75.55],
  ['Crespo', 10.443, -75.516],
  ['Pie de la Popa', 10.4175, -75.528],
  ['El Bosque', 10.395, -75.51],
  ['Los Alpes', 10.388, -75.49],
  ['Torices', 10.431, -75.533],
  ['San Fernando', 10.37, -75.495],
  ['Olaya Herrera', 10.412, -75.48],
  ['Los Ejecutivos', 10.401, -75.498],
  ['Marbella', 10.438, -75.532],
  ['El Cabrero', 10.433, -75.542],
  ['La Castellana', 10.4, -75.485],
  ['Blas de Lezo', 10.388, -75.479],
  ['Zaragocilla', 10.406, -75.502],
  ['Ternera', 10.38, -75.463],
  ['Santa Lucía', 10.389, -75.505],
];

/** Barrio principal, dos vecinos para la zona de cobertura y un punto con ±300 m de variación. */
export function placeFor(i: number) {
  const [name, lat, lng] = BARRIOS[i % BARRIOS.length];
  const near = [BARRIOS[(i + 1) % BARRIOS.length][0], BARRIOS[(i + 7) % BARRIOS.length][0]];
  const jitter = (k: number) => (((i * k) % 7) - 3) * 0.001;
  return { barrio: name, areas: [name, ...near], lat: lat + jitter(31), lng: lng + jitter(17) };
}
