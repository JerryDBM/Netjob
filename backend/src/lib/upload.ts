import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { badRequest } from './errors.js';
import { config } from '../config.js';

/**
 * Imágenes subidas por los usuarios. Si están configuradas SUPABASE_URL y
 * SUPABASE_SERVICE_ROLE_KEY se guardan en Supabase Storage (bucket público para fotos y
 * privado para documentos de identidad); si no, en el disco del servidor (desarrollo).
 */
export const UPLOAD_DIR = path.resolve('uploads');
export const PRIVATE_DIR = path.resolve('private-uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
fs.mkdirSync(PRIVATE_DIR, { recursive: true });

export const cloudStorage = () => !!(config.supabase.url && config.supabase.serviceKey);

const imageFilter = (types: RegExp, msg: string): multer.Options['fileFilter'] => (_req, file, cb) => {
  if (types.test(file.mimetype)) cb(null, true);
  else cb(badRequest(msg));
};

/** Los archivos llegan en memoria y luego se guardan con storePublic / storePrivate. */
export const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 6 },
  fileFilter: imageFilter(/^image\/(jpeg|png|webp|gif)$/, 'Solo se permiten imágenes JPG, PNG, WEBP o GIF'),
});

export const privateUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024, files: 1 },
  fileFilter: imageFilter(/^image\/(jpeg|png|webp)$/, 'Sube una foto en JPG, PNG o WEBP'),
});

const EXT: Record<string, string> = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp', 'image/gif': '.gif' };
const CONTENT_TYPE: Record<string, string> = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.gif': 'image/gif' };

function newName(mimetype: string, bytes = 6) {
  return `${Date.now()}-${crypto.randomBytes(bytes).toString('hex')}${EXT[mimetype] ?? '.jpg'}`;
}

const sbHeaders = () => ({ Authorization: `Bearer ${config.supabase.serviceKey}`, apikey: config.supabase.serviceKey });

async function sbUpload(bucket: string, name: string, data: Buffer, contentType: string) {
  const res = await fetch(`${config.supabase.url}/storage/v1/object/${bucket}/${encodeURIComponent(name)}`, {
    method: 'POST',
    headers: { ...sbHeaders(), 'Content-Type': contentType, 'x-upsert': 'true', 'Cache-Control': 'max-age=604800' },
    body: new Uint8Array(data),
  });
  if (!res.ok) throw new Error(`Supabase Storage respondió ${res.status}: ${await res.text()}`);
}

/** URL pública de un archivo del bucket público. */
export const publicObjectUrl = (name: string) =>
  `${config.supabase.url}/storage/v1/object/public/${config.supabase.publicBucket}/${encodeURIComponent(name)}`;

/**
 * Guarda una imagen pública (avatar, portafolio, fotos de servicios, solicitudes y
 * reclamaciones) y devuelve su URL. En disco devuelve una ruta relativa (/uploads/...):
 * la app le antepone la URL de la API.
 */
export async function storeBuffer(data: Buffer, contentType: string, name = newName(contentType)): Promise<string> {
  if (cloudStorage()) {
    await sbUpload(config.supabase.publicBucket, name, data, contentType);
    return publicObjectUrl(name);
  }
  await fs.promises.writeFile(path.join(UPLOAD_DIR, path.basename(name)), data);
  return `/uploads/${path.basename(name)}`;
}

export const storePublic = (file: Express.Multer.File) => storeBuffer(file.buffer, file.mimetype);

/** Documentos de identidad: nunca públicos. Devuelve el nombre con el que se guardó. */
export async function storePrivate(file: Express.Multer.File): Promise<string> {
  const name = newName(file.mimetype, 12);
  if (cloudStorage()) await sbUpload(config.supabase.privateBucket, name, file.buffer, file.mimetype);
  else await fs.promises.writeFile(path.join(PRIVATE_DIR, name), file.buffer);
  return name;
}

export async function readPrivate(name: string): Promise<{ data: Buffer; contentType: string } | null> {
  const safe = path.basename(name);
  const contentType = CONTENT_TYPE[path.extname(safe).toLowerCase()] ?? 'application/octet-stream';
  if (cloudStorage()) {
    const res = await fetch(`${config.supabase.url}/storage/v1/object/${config.supabase.privateBucket}/${encodeURIComponent(safe)}`, {
      headers: sbHeaders(),
    });
    if (!res.ok) return null;
    return { data: Buffer.from(await res.arrayBuffer()), contentType };
  }
  const file = path.join(PRIVATE_DIR, safe);
  if (!fs.existsSync(file)) return null;
  return { data: await fs.promises.readFile(file), contentType };
}

export async function removePrivate(name: string) {
  const safe = path.basename(name);
  if (cloudStorage()) {
    await fetch(`${config.supabase.url}/storage/v1/object/${config.supabase.privateBucket}`, {
      method: 'DELETE',
      headers: { ...sbHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: [safe] }),
    }).catch(() => {});
  } else {
    fs.rm(path.join(PRIVATE_DIR, safe), () => {});
  }
}

/** Crea los buckets si no existen (público para fotos, privado para documentos). */
export async function ensureBuckets() {
  if (!cloudStorage()) return;
  for (const [id, isPublic] of [
    [config.supabase.publicBucket, true],
    [config.supabase.privateBucket, false],
  ] as const) {
    const res = await fetch(`${config.supabase.url}/storage/v1/bucket`, {
      method: 'POST',
      headers: { ...sbHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, name: id, public: isPublic, file_size_limit: 8 * 1024 * 1024 }),
    });
    if (!res.ok) {
      const text = await res.text();
      if (!/already exists|Duplicate/i.test(text)) throw new Error(`No se pudo crear el bucket ${id}: ${res.status} ${text}`);
    }
  }
  console.log(`Imágenes en Supabase Storage (buckets "${config.supabase.publicBucket}" y "${config.supabase.privateBucket}")`);
}
