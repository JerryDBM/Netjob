import { config } from '../config.js';

/**
 * Comisión NetJob: 3 % del valor del servicio, asumida por el cliente.
 * Ej.: 100.000 → comisión 3.000 → total 103.000.
 */
export function computeServiceCharge(serviceAmount: number, rate = config.commissionRate) {
  if (!Number.isInteger(serviceAmount) || serviceAmount <= 0) {
    throw new Error('El valor del servicio debe ser un entero positivo en COP');
  }
  const commissionAmount = Math.round(serviceAmount * rate);
  return { serviceAmount, commissionAmount, totalAmount: serviceAmount + commissionAmount };
}
