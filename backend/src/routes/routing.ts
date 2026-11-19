import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { parse } from '../lib/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { badRequest } from '../lib/errors.js';

/**
 * Ruta por calles para la navegación del profesional dentro de la app.
 * Usa un servidor OSRM (por defecto el público de demostración; en producción se
 * recomienda uno propio o Google Routes API) y devuelve las indicaciones en español.
 */
export const routingRouter = Router();
routingRouter.use(requireAuth);

type Maneuver = { type: string; modifier?: string; exit?: number; location: [number, number] };
type OsrmStep = { maneuver: Maneuver; name: string; distance: number; duration: number };

const SIDE: Record<string, string> = {
  left: 'a la izquierda',
  right: 'a la derecha',
  'slight left': 'ligeramente a la izquierda',
  'slight right': 'ligeramente a la derecha',
  'sharp left': 'cerrado a la izquierda',
  'sharp right': 'cerrado a la derecha',
  straight: 'derecho',
  uturn: 'en U',
};

/** Indicación en español a partir de la maniobra de OSRM. */
export function instruction(s: OsrmStep): string {
  const m = s.maneuver;
  const on = s.name ? ` por ${s.name}` : '';
  const onto = s.name ? ` hacia ${s.name}` : '';
  const side = m.modifier ? SIDE[m.modifier] ?? '' : '';
  switch (m.type) {
    case 'depart':
      return s.name ? `Arranca por ${s.name}` : 'Arranca hacia la vía principal';
    case 'arrive':
      return 'Llegaste al domicilio del cliente';
    case 'turn':
      return m.modifier === 'straight' ? `Sigue derecho${on}` : m.modifier === 'uturn' ? `Da la vuelta en U${on}` : `Gira ${side}${onto}`;
    case 'new name':
    case 'continue':
      return m.modifier && m.modifier !== 'straight' ? `Continúa ${side}${on}` : `Continúa${on}`;
    case 'merge':
      return `Incorpórate ${side}${onto}`.replace('  ', ' ');
    case 'on ramp':
      return `Toma la entrada ${side}${onto}`;
    case 'off ramp':
      return `Toma la salida ${side}${onto}`;
    case 'fork':
      return `En la bifurcación mantente ${side}${onto}`;
    case 'end of road':
      return `Al final de la vía gira ${side}${onto}`;
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
      return m.exit ? `En la glorieta toma la ${m.exit}.ª salida${onto}` : `Entra a la glorieta${onto}`;
    case 'exit roundabout':
    case 'exit rotary':
      return `Sal de la glorieta${onto}`;
    default:
      return side ? `Sigue ${side}${on}` : `Continúa${on}`;
  }
}

const pt = z.coerce.number();

routingRouter.get('/', async (req, res) => {
  const q = parse(
    z.object({ fromLat: pt.min(-90).max(90), fromLng: pt.min(-180).max(180), toLat: pt.min(-90).max(90), toLng: pt.min(-180).max(180) }),
    req.query,
  );
  const url =
    `${config.routingUrl}/route/v1/driving/${q.fromLng},${q.fromLat};${q.toLng},${q.toLat}` +
    '?overview=full&geometries=geojson&steps=true';
  let data: any;
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(12_000), headers: { 'User-Agent': 'NetJob/0.1 (desarrollo)' } });
    data = await r.json();
  } catch {
    throw badRequest('No fue posible calcular la ruta en este momento');
  }
  const route = data?.routes?.[0];
  if (data?.code !== 'Ok' || !route) throw badRequest('No encontramos una ruta por calles hasta ese punto');
  const steps = (route.legs?.[0]?.steps ?? []) as OsrmStep[];
  res.json({
    distance: Math.round(route.distance), // metros
    duration: Math.round(route.duration), // segundos
    points: (route.geometry.coordinates as [number, number][]).map(([lng, lat]) => [lat, lng]),
    steps: steps.map((s) => ({
      text: instruction(s),
      type: s.maneuver.type,
      modifier: s.maneuver.modifier ?? null,
      name: s.name || null,
      distance: Math.round(s.distance),
      duration: Math.round(s.duration),
      lat: s.maneuver.location[1],
      lng: s.maneuver.location[0],
    })),
  });
});
