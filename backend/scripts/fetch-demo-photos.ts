/**
 * Solo para datos de prueba: descarga fotos con licencia Creative Commons (vía Openverse,
 * fuente Flickr) para el portafolio de los profesionales demo, y retratos de randomuser.me
 * para sus fotos de perfil. Guarda los créditos de cada foto en prisma/demo-photos/credits.json.
 *
 *   npm run demo:photos
 *
 * Volver a ejecutarlo solo descarga lo que falte.
 */
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.resolve('prisma/demo-photos');
const UA = 'NetJob-demo-seed/1.0 (proyecto academico)';
const PER_TRADE = 24;

/** Búsquedas (en inglés, donde hay más fotos) por categoría de NetJob. */
const QUERIES: Record<string, string[]> = {
  plomeria: ['plumber pipes', 'bathroom faucet', 'plumbing repair', 'kitchen sink plumbing', 'toilet installation', 'water heater'],
  electricidad: ['electrician', 'electrical panel', 'electrical wiring', 'ceiling fan', 'light fixture installation'],
  carpinteria: ['carpenter woodwork', 'kitchen cabinets wood', 'woodworking furniture', 'wooden door', 'wardrobe closet wood'],
  pintura: ['house painter', 'paint roller wall', 'interior painting', 'house exterior paint'],
  cerrajeria: ['locksmith', 'door lock', 'lock cylinder keys', 'padlock gate'],
  reparaciones: ['drywall repair', 'tile installation floor', 'roof repair', 'brick wall masonry', 'handyman repair'],
  instalaciones: ['air conditioner installation', 'shower installation', 'tv wall mount', 'solar water heater', 'curtain installation'],
  'servicios-tecnicos': ['refrigerator repair', 'washing machine repair', 'appliance repair', 'air conditioner repair', 'computer repair'],
  otros: ['gardener lawn', 'house cleaning', 'hedge trimming', 'pool cleaning'],
};

type Credit = { file: string; title: string; creator: string | null; license: string; licenseUrl: string | null; source: string };
const creditsFile = path.join(OUT, 'credits.json');
const credits: Record<string, Credit> = fs.existsSync(creditsFile) ? JSON.parse(fs.readFileSync(creditsFile, 'utf8')) : {};
const save = () => fs.writeFileSync(creditsFile, JSON.stringify(credits, null, 2));
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function download(url: string, file: string, minBytes = 15_000, maxBytes = 2_500_000) {
  const res = await fetch(url, { headers: { 'User-Agent': UA }, redirect: 'follow', signal: AbortSignal.timeout(30_000) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const type = res.headers.get('content-type') ?? '';
  if (!type.startsWith('image/jpeg')) throw new Error(`tipo ${type}`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < minBytes || buf.length > maxBytes) throw new Error(`tamaño ${buf.length}`);
  fs.writeFileSync(file, buf);
}

async function search(q: string, page: number) {
  const url = new URL('https://api.openverse.org/v1/images/');
  url.search = new URLSearchParams({ q, page_size: '20', page: String(page), source: 'flickr', aspect_ratio: 'wide', mature: 'false' }).toString();
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch(url, { headers: { 'User-Agent': UA } });
    if (res.status === 429) {
      console.log('  límite de Openverse, esperando 65 s…');
      await sleep(65_000);
      continue;
    }
    if (!res.ok) throw new Error(`Openverse ${res.status}`);
    return ((await res.json()) as { results: any[] }).results;
  }
  return [];
}

for (const [trade, queries] of Object.entries(QUERIES)) {
  const dir = path.join(OUT, trade);
  fs.mkdirSync(dir, { recursive: true });
  const have = () => fs.readdirSync(dir).filter((f) => f.endsWith('.jpg')).length;
  const seen = new Set(Object.values(credits).map((c) => c.source));
  let n = have();
  console.log(`${trade}: ${n} fotos`);
  for (const q of queries) {
    if (n >= PER_TRADE) break;
    const results = await search(q, 1);
    await sleep(3500); // máximo 20 búsquedas por minuto
    for (const r of results.slice(0, Math.ceil(PER_TRADE / queries.length) + 3)) {
      if (n >= PER_TRADE) break;
      if (!r.url || seen.has(r.foreign_landing_url)) continue;
      const name = `${String(n + 1).padStart(2, '0')}.jpg`;
      const file = path.join(dir, name);
      try {
        await download(r.url, file);
        credits[`${trade}/${name}`] = {
          file: `${trade}/${name}`,
          title: r.title ?? q,
          creator: r.creator ?? null,
          license: `CC ${String(r.license).toUpperCase()} ${r.license_version ?? ''}`.trim(),
          licenseUrl: r.license_url ?? null,
          source: r.foreign_landing_url,
        };
        seen.add(r.foreign_landing_url);
        n++;
        save();
      } catch (e) {
        console.log(`  omitida (${(e as Error).message}): ${r.url}`);
      }
    }
    console.log(`  "${q}" → ${n}`);
  }
}

// Retratos para las fotos de perfil (randomuser.me, de uso libre para datos de prueba)
const avatars = path.join(OUT, 'avatars');
fs.mkdirSync(avatars, { recursive: true });
for (const g of ['men', 'women'] as const) {
  for (let i = 1; i <= 40; i++) {
    const file = path.join(avatars, `${g}-${i}.jpg`);
    if (fs.existsSync(file)) continue;
    try {
      await download(`https://randomuser.me/api/portraits/${g}/${i}.jpg`, file, 2_000);
    } catch (e) {
      console.log(`  retrato ${g}/${i} omitido: ${(e as Error).message}`);
    }
  }
}
console.log(`Listo. Créditos en ${path.relative(process.cwd(), creditsFile)}`);
