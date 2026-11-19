import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { prisma } from '../db.js';
import { forbidden, unauthorized } from '../lib/errors.js';
import type { Role } from '@prisma/client';

export interface AuthUser {
  id: string;
  role: Role;
  professionalId?: string | null;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function signToken(userId: string, role: Role) {
  return jwt.sign({ sub: userId, role }, config.jwtSecret, { expiresIn: config.jwtExpiresIn as any });
}

export function verifyToken(token: string): { sub: string; role: Role } {
  return jwt.verify(token, config.jwtSecret) as any;
}

async function loadUser(token: string): Promise<AuthUser> {
  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    throw unauthorized('Sesión inválida o expirada');
  }
  const user = await prisma.user.findUnique({
    where: { id: payload.sub },
    select: { id: true, role: true, status: true, suspendedUntil: true, suspensionReason: true, professional: { select: { id: true } } },
  });
  if (!user) throw unauthorized('Usuario no encontrado');
  await assertNotSuspended(user);
  return { id: user.id, role: user.role, professionalId: user.professional?.id ?? null };
}

/**
 * Suspensión: si era temporal y ya venció, la cuenta se reactiva sola. Si sigue vigente,
 * se informa el motivo y hasta cuándo.
 */
export async function assertNotSuspended(user: { id: string; status: string; suspendedUntil: Date | null; suspensionReason: string | null }) {
  if (user.status === 'ACTIVE') return;
  if (user.suspendedUntil && user.suspendedUntil <= new Date()) {
    await prisma.user.update({ where: { id: user.id }, data: { status: 'ACTIVE', suspendedUntil: null, suspensionReason: null } });
    return;
  }
  const until = user.suspendedUntil
    ? ` hasta el ${user.suspendedUntil.toLocaleDateString('es-CO', { day: 'numeric', month: 'long', timeZone: 'America/Bogota' })}`
    : '';
  const why = user.suspensionReason ? ` Motivo: ${user.suspensionReason}.` : '';
  throw forbidden(`Tu cuenta está suspendida${until}.${why} Contacta a soporte.`);
}

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw unauthorized();
  req.user = await loadUser(header.slice(7));
  next();
}

export async function optionalAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) {
    try {
      req.user = await loadUser(header.slice(7));
    } catch {
      /* se ignora: ruta pública */
    }
  }
  next();
}

export const requireRole =
  (...roles: Role[]) =>
  (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) throw unauthorized();
    if (!roles.includes(req.user.role)) throw forbidden();
    next();
  };

/** Devuelve el id del perfil profesional del usuario autenticado o lanza 403. */
export function proId(req: Request): string {
  if (req.user?.role !== 'PROFESSIONAL' || !req.user.professionalId) throw forbidden('Solo para profesionales');
  return req.user.professionalId;
}
