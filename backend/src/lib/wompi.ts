import crypto from 'node:crypto';
import { config } from '../config.js';

/** Estados de transacción que reporta Wompi. */
export type WompiStatus = 'PENDING' | 'APPROVED' | 'DECLINED' | 'VOIDED' | 'ERROR';

export const wompiConfigured = () => Boolean(config.wompi.publicKey && config.wompi.integritySecret);

const sha256 = (s: string) => crypto.createHash('sha256').update(s).digest('hex');

/** Firma de integridad: SHA256(referencia + montoEnCentavos + moneda + secretoIntegridad). */
export function integritySignature(reference: string, amountInCents: number, currency = 'COP') {
  return sha256(`${reference}${amountInCents}${currency}${config.wompi.integritySecret}`);
}

/** URL del Web Checkout de Wompi para que el cliente pague. */
export function checkoutUrl(params: { reference: string; amountCop: number; email?: string; redirectUrl?: string }) {
  const amountInCents = params.amountCop * 100;
  const q = new URLSearchParams({
    'public-key': config.wompi.publicKey,
    currency: 'COP',
    'amount-in-cents': String(amountInCents),
    reference: params.reference,
    'signature:integrity': integritySignature(params.reference, amountInCents),
    'redirect-url': params.redirectUrl ?? config.paymentRedirectUrl,
  });
  if (params.email) q.set('customer-data:email', params.email);
  return `${config.wompi.checkoutBase}?${q.toString()}`;
}

function getPath(obj: any, path: string) {
  return path.split('.').reduce((acc, k) => (acc == null ? undefined : acc[k]), obj);
}

/**
 * Verifica el checksum de un evento (webhook) de Wompi:
 * SHA256(valores de signature.properties concatenados + timestamp + secretoEventos).
 */
export function verifyEventChecksum(event: any): boolean {
  const props: string[] | undefined = event?.signature?.properties;
  const checksum: string | undefined = event?.signature?.checksum;
  if (!props || !checksum || !config.wompi.eventsSecret) return false;
  const concatenated = props.map((p) => String(getPath(event.data, p) ?? '')).join('');
  const computed = sha256(`${concatenated}${event.timestamp}${config.wompi.eventsSecret}`);
  const a = Buffer.from(computed.toLowerCase());
  const b = Buffer.from(String(checksum).toLowerCase());
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Busca transacciones por referencia (requiere llave privada). Devuelve la más reciente o null. */
export async function findTransactionByReference(reference: string): Promise<any | null> {
  if (!config.wompi.privateKey) return null;
  const res = await fetch(`${config.wompi.apiBase}/transactions?reference=${encodeURIComponent(reference)}`, {
    headers: { Authorization: `Bearer ${config.wompi.privateKey}` },
  });
  if (!res.ok) throw new Error(`Wompi respondió ${res.status}`);
  const json: any = await res.json();
  const list: any[] = json.data ?? [];
  return list.sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null;
}

/** Consulta una transacción en Wompi por su id (endpoint público). */
export async function fetchTransaction(transactionId: string): Promise<any> {
  const res = await fetch(`${config.wompi.apiBase}/transactions/${encodeURIComponent(transactionId)}`);
  if (!res.ok) throw new Error(`Wompi respondió ${res.status}`);
  const json: any = await res.json();
  return json.data;
}
