import { z } from 'zod';
import { prisma } from '../db.js';
import { config } from '../config.js';

/**
 * Configuración general editable por el administrador desde la app. Los valores iniciales
 * vienen del .env; lo que el administrador guarda queda en la tabla Setting (clave "system")
 * y se aplica sobre `config` al arrancar y cada vez que se guarda.
 */
export const baseSchema = z.object({
    commissionRate: z.number().min(0).max(0.2),
    loyaltyCommissionRate: z.number().min(0).max(0.2),
    loyaltyEvery: z.number().int().min(1).max(50),
    loyaltyMinRating: z.number().min(0).max(5),
    searchRadiusKm: z.number().int().min(1).max(100),
    warrantyDays: z.number().int().min(0).max(365),
    diagnosticFee: z.number().int().min(0).max(500_000),
    maxDiagnosticFee: z.number().int().min(0).max(500_000),
    minPortfolio: z.number().int().min(0).max(20),
    trainingPassScore: z.number().int().min(1).max(25),
    reviewThreshold: z.number().min(0).max(5),
    subscriptionDays: z.number().int().min(1).max(365),
  });

export const settingsSchema = baseSchema
  .refine((s) => s.loyaltyCommissionRate <= s.commissionRate, {
    message: 'La tarifa reducida no puede ser mayor que la comisión normal',
    path: ['loyaltyCommissionRate'],
  })
  .refine((s) => s.diagnosticFee <= s.maxDiagnosticFee, {
    message: 'El valor inicial de la visita no puede superar el tope',
    path: ['diagnosticFee'],
  });

export type SystemSettings = z.infer<typeof settingsSchema>;
const KEYS = Object.keys(baseSchema.shape) as (keyof SystemSettings)[];
const DB_KEY = 'system';

export function currentSettings(): SystemSettings {
  return Object.fromEntries(KEYS.map((k) => [k, config[k]])) as SystemSettings;
}

/** Lee lo guardado por el administrador y lo aplica sobre la configuración en memoria. */
export async function loadSettings() {
  const row = await prisma.setting.findUnique({ where: { key: DB_KEY } });
  if (!row) return currentSettings();
  try {
    const saved = settingsSchema.safeParse({ ...currentSettings(), ...JSON.parse(row.value) });
    if (saved.success) Object.assign(config, saved.data);
    else console.warn('[configuración] valores guardados inválidos, se ignoran:', saved.error.issues);
  } catch (e) {
    console.warn('[configuración] no se pudo leer la configuración guardada', e);
  }
  return currentSettings();
}

export async function saveSettings(patch: Partial<SystemSettings>) {
  const next = settingsSchema.parse({ ...currentSettings(), ...patch });
  await prisma.setting.upsert({
    where: { key: DB_KEY },
    update: { value: JSON.stringify(next) },
    create: { key: DB_KEY, value: JSON.stringify(next) },
  });
  Object.assign(config, next);
  return next;
}
