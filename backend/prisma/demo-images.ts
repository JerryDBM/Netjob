/**
 * Genera imágenes PNG sencillas (degradado + círculo) para las cuentas demo, sin depender
 * de archivos externos. Solo se usa en el seed de desarrollo.
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

type RGB = [number, number, number];

function chunk(type: string, data: Buffer) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(zlib.crc32(body) >>> 0);
  return Buffer.concat([len, body, crc]);
}

export function makePng(width: number, height: number, from: RGB, to: RGB): Buffer {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  const cx = width * 0.7;
  const cy = height * 0.35;
  const r = Math.min(width, height) * 0.22;
  for (let y = 0; y < height; y++) {
    const row = y * (width * 3 + 1);
    raw[row] = 0;
    for (let x = 0; x < width; x++) {
      const t = (x / width + y / height) / 2;
      let px = from.map((c, i) => Math.round(c + (to[i] - c) * t));
      if ((x - cx) ** 2 + (y - cy) ** 2 < r * r) px = px.map((c) => Math.min(255, c + 45));
      raw.set(px, row + 1 + x * 3);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr.set([8, 2, 0, 0, 0], 8); // 8 bits, RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Escribe la imagen en uploads/ (si no existe) y devuelve su ruta pública relativa. */
export function demoImage(name: string, width: number, height: number, from: RGB, to: RGB): string {
  const dir = path.resolve('uploads');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${name}.png`);
  if (!fs.existsSync(file)) fs.writeFileSync(file, makePng(width, height, from, to));
  return `/uploads/${name}.png`;
}
