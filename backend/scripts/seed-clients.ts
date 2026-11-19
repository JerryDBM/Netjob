/**
 * Datos de prueba: 20 clientes en Cartagena (demo-cliente-1 … demo-cliente-20@netjob.co,
 * contraseña NetJob2026!) con celular, barrio y foto. Los 12 primeros ya existen como
 * autores de las reseñas; aquí se completan sus datos. Volver a ejecutarlo no duplica.
 *
 *   npm run demo:clients
 */
import fs from 'node:fs';
import path from 'node:path';
import bcrypt from 'bcryptjs';
import { prisma } from '../src/db.js';
import { ensureBuckets, storeBuffer } from '../src/lib/upload.js';
import { CARTAGENA } from './cartagena.js';

// [nombre, género] — los 12 primeros coinciden con los autores de reseñas de seed-pros
const CLIENTS: [string, 'm' | 'f'][] = [
  ['Daniela Herrera', 'f'], ['Andrés Castillo', 'm'], ['Paola Vergara', 'f'], ['Julián Ortega', 'm'],
  ['Marcela Ríos', 'f'], ['Camilo Salgado', 'm'], ['Tatiana Blanco', 'f'], ['Fredy Caraballo', 'm'],
  ['Mariana Acosta', 'f'], ['Esteban Navarro', 'm'], ['Luz Dary Peña', 'f'], ['Hugo Ballesteros', 'm'],
  ['Valentina Montes', 'f'], ['Santiago Puello', 'm'], ['Isabel Cuesta', 'f'], ['Rodrigo Guerrero', 'm'],
  ['Natalia Simancas', 'f'], ['Javier Lambraño', 'm'], ['Karen Bolaño', 'f'], ['Miguel Ángel Teherán', 'm'],
];

const PHOTOS = path.resolve('prisma/demo-photos/avatars');
// Retratos que no usan los profesionales demo (34 hombres y 16 mujeres)
const avatarFor = (g: 'm' | 'f', n: number) => path.join(PHOTOS, g === 'm' ? `men-${35 + (n % 6)}.jpg` : `women-${17 + n}.jpg`);

await ensureBuckets();
const passwordHash = await bcrypt.hash('NetJob2026!', 10);
const counters = { m: 0, f: 0 };
for (const [i, [name, g]] of CLIENTS.entries()) {
  const email = `demo-cliente-${i + 1}@netjob.co`;
  const file = avatarFor(g, counters[g]++);
  const existing = await prisma.user.findUnique({ where: { email } });
  const avatarUrl =
    existing?.avatarUrl ?? (fs.existsSync(file) ? await storeBuffer(fs.readFileSync(file), 'image/jpeg', `demo-cliente-${i + 1}.jpg`) : null);
  const data = {
    name,
    city: CARTAGENA.name,
    department: CARTAGENA.dept,
    phone: `300${String(4100000 + i * 37171).slice(0, 7)}`,
    avatarUrl,
  };
  await prisma.user.upsert({
    where: { email },
    update: data,
    create: { ...data, email, role: 'CLIENT', passwordHash },
  });
  console.log(`${existing ? 'Actualizado' : 'Creado'}: ${name} (${email})`);
}
// La clienta demo principal también queda en Cartagena
await prisma.user.updateMany({ where: { email: 'cliente@netjob.co' }, data: { city: CARTAGENA.name, department: CARTAGENA.dept } });
console.log(`\n${CLIENTS.length} clientes en ${CARTAGENA.name} (contraseña NetJob2026!)`);
await prisma.$disconnect();
