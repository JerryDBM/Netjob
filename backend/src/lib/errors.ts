export class HttpError extends Error {
  constructor(public status: number, message: string, public details?: unknown) {
    super(message);
  }
}

export const badRequest = (msg: string, details?: unknown) => new HttpError(400, msg, details);
export const unauthorized = (msg = 'No autenticado') => new HttpError(401, msg);
export const forbidden = (msg = 'No tienes permiso para esta acción') => new HttpError(403, msg);
export const notFound = (msg = 'Recurso no encontrado') => new HttpError(404, msg);
export const conflict = (msg: string) => new HttpError(409, msg);
/** Límite o beneficio que depende del plan: la app ofrece mejorar la suscripción. */
export const planRequired = (msg: string, code: 'PLAN_LIMIT' | 'PLAN_REQUIRED' = 'PLAN_LIMIT') => new HttpError(403, msg, { code });
