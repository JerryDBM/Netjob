/**
 * PostgreSQL local para desarrollo, sin instalar nada (usa el paquete embedded-postgres).
 * Datos en backend/.pgdata. Deja este proceso corriendo y en otra terminal: npm run dev
 */
import EmbeddedPostgres from 'embedded-postgres';
import fs from 'node:fs';
import path from 'node:path';

const dataDir = path.resolve('.pgdata');
const firstRun = !fs.existsSync(path.join(dataDir, 'PG_VERSION'));

const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'postgres',
  password: 'netjob',
  port: 5433,
  persistent: true,
  // En Windows initdb usa WIN1252 por defecto; NetJob necesita UTF-8 (tildes, ñ, emojis)
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
});

if (firstRun) await pg.initialise();
await pg.start();
try {
  await pg.createDatabase('netjob');
} catch {
  /* ya existe */
}
console.log('PostgreSQL de desarrollo listo en postgresql://postgres:netjob@localhost:5433/netjob');
if (firstRun) console.log('Primera vez: ejecuta "npm run db:push" y "npm run db:seed".');

const stop = async () => {
  await pg.stop();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
