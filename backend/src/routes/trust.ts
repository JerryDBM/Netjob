import { Router } from 'express';
import path from 'node:path';
import { z } from 'zod';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { parse } from '../lib/validate.js';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { requireAuth, proId } from '../middleware/auth.js';
import { privateUpload, readPrivate, removePrivate, storePrivate } from '../lib/upload.js';
import { gradeQuiz, guides, publicQuestions, totalQuestions } from '../lib/training.js';
import { getActiveSubscription } from '../lib/subscriptions.js';

// ---------- Capacitación inicial obligatoria ----------
export const trainingRouter = Router();
trainingRouter.use(requireAuth);

async function trainingState(professionalId: string) {
  const p = await prisma.professionalProfile.findUniqueOrThrow({
    where: { id: professionalId },
    select: { rulesAcceptedAt: true, trainingPassedAt: true, trainingScore: true, trainingAttempts: true },
  });
  return { ...p, passScore: config.trainingPassScore, total: totalQuestions };
}

/** Instructivos y cuestionario. Los instructivos quedan disponibles siempre desde la cuenta. */
trainingRouter.get('/', async (req, res) => {
  const id = proId(req);
  res.json({ guides, questions: publicQuestions(), state: await trainingState(id) });
});

trainingRouter.post('/accept-rules', async (req, res) => {
  const id = proId(req);
  const p = await prisma.professionalProfile.findUniqueOrThrow({ where: { id }, select: { rulesAcceptedAt: true } });
  if (!p.rulesAcceptedAt) await prisma.professionalProfile.update({ where: { id }, data: { rulesAcceptedAt: new Date() } });
  res.json(await trainingState(id));
});

trainingRouter.post('/submit', async (req, res) => {
  const id = proId(req);
  const { answers } = parse(z.object({ answers: z.array(z.number().int().min(0).max(5)).length(totalQuestions) }), req.body);
  const p = await prisma.professionalProfile.findUniqueOrThrow({ where: { id }, select: { rulesAcceptedAt: true, trainingPassedAt: true } });
  if (!p.rulesAcceptedAt) throw conflict('Primero lee los instructivos y acepta las reglas y condiciones');
  const result = gradeQuiz(answers);
  const passed = result.score >= config.trainingPassScore;
  await prisma.professionalProfile.update({
    where: { id },
    data: {
      trainingAttempts: { increment: 1 },
      trainingScore: result.score,
      // Una vez aprobada, la capacitación no se pierde por un intento posterior
      trainingPassedAt: passed ? (p.trainingPassedAt ?? new Date()) : (p.trainingPassedAt ?? null),
    },
  });
  res.json({ ...result, passed, state: await trainingState(id) });
});

// ---------- Verificación de identidad y antecedentes ----------
export const verificationRouter = Router();
verificationRouter.use(requireAuth);

const DOCS = {
  idFront: 'idFrontFile',
  idBack: 'idBackFile',
  selfie: 'selfieFile',
  backgroundCheck: 'backgroundCheckFile',
} as const;
type DocKind = keyof typeof DOCS;

async function verificationState(professionalId: string) {
  const p = await prisma.professionalProfile.findUniqueOrThrow({
    where: { id: professionalId },
    select: {
      verificationStatus: true, verificationNote: true, verificationSubmittedAt: true, verificationReviewedAt: true,
      idFrontFile: true, idBackFile: true, selfieFile: true, backgroundCheckFile: true, verified: true,
    },
  });
  const sub = await getActiveSubscription(professionalId);
  return {
    status: p.verificationStatus,
    verified: p.verified,
    note: p.verificationNote,
    submittedAt: p.verificationSubmittedAt,
    reviewedAt: p.verificationReviewedAt,
    documents: Object.fromEntries((Object.keys(DOCS) as DocKind[]).map((k) => [k, p[DOCS[k]]])),
    priority: sub?.plan.verificationPriority ?? false,
    required: config.requireVerification,
  };
}

verificationRouter.get('/', async (req, res) => {
  res.json(await verificationState(proId(req)));
});

/** Sube (o reemplaza) uno de los cuatro documentos. Solo mientras no esté en revisión ni aprobado. */
verificationRouter.post('/documents/:kind', privateUpload.single('file'), async (req, res) => {
  const id = proId(req);
  const kind = req.params.kind as DocKind;
  if (!(kind in DOCS)) throw badRequest('Documento desconocido');
  if (!req.file) throw badRequest('Adjunta una foto en el campo "file"');
  const p = await prisma.professionalProfile.findUniqueOrThrow({ where: { id } });
  if (p.verificationStatus === 'PENDING' || p.verificationStatus === 'APPROVED') {
    throw conflict(p.verificationStatus === 'PENDING' ? 'Tus documentos ya están en revisión' : 'Tu identidad ya fue verificada');
  }
  const previous = p[DOCS[kind]];
  const name = await storePrivate(req.file);
  await prisma.professionalProfile.update({ where: { id }, data: { [DOCS[kind]]: name } });
  if (previous) await removePrivate(previous);
  res.json(await verificationState(id));
});

verificationRouter.post('/submit', async (req, res) => {
  const id = proId(req);
  const p = await prisma.professionalProfile.findUniqueOrThrow({ where: { id } });
  if (p.verificationStatus === 'PENDING') throw conflict('Tus documentos ya están en revisión');
  if (p.verificationStatus === 'APPROVED') throw conflict('Tu identidad ya fue verificada');
  if (!p.idFrontFile || !p.idBackFile || !p.selfieFile || !p.backgroundCheckFile) {
    throw badRequest('Faltan documentos: cédula por ambos lados, selfie y certificado de antecedentes');
  }
  await prisma.professionalProfile.update({
    where: { id },
    data: { verificationStatus: 'PENDING', verificationSubmittedAt: new Date(), verificationNote: null },
  });
  res.json(await verificationState(id));
});

/** Descarga de un documento: solo el dueño o un administrador. */
verificationRouter.get('/files/:name', async (req, res) => {
  const name = path.basename(req.params.name as string);
  const owner = await prisma.professionalProfile.findFirst({
    where: { OR: [{ idFrontFile: name }, { idBackFile: name }, { selfieFile: name }, { backgroundCheckFile: name }] },
    select: { userId: true },
  });
  if (!owner) throw notFound('Documento no encontrado');
  if (req.user!.role !== 'ADMIN' && owner.userId !== req.user!.id) throw forbidden();
  const file = await readPrivate(name);
  if (!file) throw notFound('Documento no encontrado');
  res.setHeader('Cache-Control', 'private, no-store');
  res.type(file.contentType).send(file.data);
});
