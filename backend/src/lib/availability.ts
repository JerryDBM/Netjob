/**
 * Disponibilidad automática según los horarios del profesional, en hora de Colombia
 * (UTC−5, sin horario de verano). Ej.: lunes 08:00–17:00 → disponible de 8:00 a 16:59.
 */
export type Slot = { dayOfWeek: number; startTime: string; endTime: string };

const COLOMBIA_OFFSET_MIN = -5 * 60;

/** Día (0 = domingo) y hora "HH:mm" actuales en Colombia. */
export function colombiaNow(now = new Date()) {
  const local = new Date(now.getTime() + COLOMBIA_OFFSET_MIN * 60_000);
  const hh = String(local.getUTCHours()).padStart(2, '0');
  const mm = String(local.getUTCMinutes()).padStart(2, '0');
  return { day: local.getUTCDay(), time: `${hh}:${mm}` };
}

/** ¿Está dentro de alguna franja ahora mismo? (inicio incluido, fin excluido) */
export function inSchedule(slots: Slot[], now = new Date()) {
  const { day, time } = colombiaNow(now);
  return slots.some((s) => s.dayOfWeek === day && s.startTime <= time && time < s.endTime);
}

const DAYS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];

/**
 * Estado para mostrar: disponible ahora (hasta qué hora) o cuándo vuelve a estarlo.
 * `enabled` es el interruptor manual del profesional (puede pausar su disponibilidad).
 */
export function availabilityStatus(slots: Slot[], enabled: boolean, now = new Date()) {
  const { day, time } = colombiaNow(now);
  const current = slots.find((s) => s.dayOfWeek === day && s.startTime <= time && time < s.endTime);
  const availableNow = enabled && !!current;
  let next: { day: string; time: string } | null = null;
  if (enabled && !current) {
    for (let i = 0; i < 8 && !next; i++) {
      const d = (day + i) % 7;
      const candidates = slots
        .filter((s) => s.dayOfWeek === d && (i > 0 || s.startTime > time))
        .sort((a, b) => a.startTime.localeCompare(b.startTime));
      if (candidates.length) next = { day: i === 0 ? 'hoy' : i === 1 ? 'mañana' : DAYS[d], time: candidates[0].startTime };
    }
  }
  return { availableNow, until: availableNow ? current!.endTime : null, next, enabled };
}
