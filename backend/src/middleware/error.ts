import type { NextFunction, Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import multer from 'multer';
import { HttpError } from '../lib/errors.js';

export function errorHandler(err: any, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof HttpError) {
    const code = (err.details as { code?: string } | undefined)?.code;
    return res.status(err.status).json({ error: err.message, code, details: err.details });
  }
  if (err instanceof multer.MulterError) {
    return res.status(400).json({ error: `Archivo inválido: ${err.message}` });
  }
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') return res.status(409).json({ error: 'El registro ya existe' });
    if (err.code === 'P2025') return res.status(404).json({ error: 'Recurso no encontrado' });
  }
  if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON inválido' });
  console.error(err);
  res.status(500).json({ error: 'Error interno del servidor' });
}
