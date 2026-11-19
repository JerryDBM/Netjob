import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { z } from 'zod';
import { prisma } from '../db.js';
import { parse } from '../lib/validate.js';
import { badRequest, conflict, unauthorized } from '../lib/errors.js';
import { signToken, requireAuth, assertNotSuspended } from '../middleware/auth.js';
import { config } from '../config.js';
import { ensureReferralCode, newReferralCode } from '../lib/rewards.js';
import { publicUser } from '../lib/serialize.js';
import { profileMissing } from '../lib/profile.js';
import { sendMail } from '../lib/mailer.js';
import { upload, storePublic } from '../lib/upload.js';

export const authRouter = Router();

const password = z.string().min(8, 'mínimo 8 caracteres');

const registerSchema = z.object({
  name: z.string().trim().min(2),
  email: z.string().trim().toLowerCase().email(),
  password,
  phone: z
    .string()
    .trim()
    .transform((v) => v.replace(/\D/g, '').replace(/^57(?=3\d{9}$)/, ''))
    .pipe(z.string().regex(/^3\d{9}$/, 'el celular debe tener 10 dígitos y empezar por 3')),
  department: z.string().trim().min(2, 'elige el departamento').max(80),
  city: z.string().trim().min(2, 'elige el municipio').max(80),
  // El rol ADMIN nunca se puede elegir en el registro público
  role: z.enum(['CLIENT', 'PROFESSIONAL']),
  // Código de quien lo invitó (opcional)
  referralCode: z.string().trim().toUpperCase().max(20).optional(),
});

async function userWithProfile(id: string) {
  return prisma.user.findUniqueOrThrow({ where: { id }, include: { professional: true } });
}

/** Usuario público + lo que le falta al perfil profesional (la app exige completarlo). */
async function userPayload(user: Awaited<ReturnType<typeof userWithProfile>>) {
  const out = publicUser(user);
  if (!user.professional) return out;
  const { idFrontFile, idBackFile, selfieFile, backgroundCheckFile, ...professional } = user.professional;
  return { ...out, professional: { ...professional, missing: await profileMissing(professional.id) } };
}

async function authResponse(user: Awaited<ReturnType<typeof userWithProfile>>) {
  return { token: signToken(user.id, user.role), user: await userPayload(user) };
}

authRouter.post('/register', async (req, res) => {
  const body = parse(registerSchema, req.body);
  const exists = await prisma.user.findUnique({ where: { email: body.email } });
  if (exists) throw conflict('Ya existe una cuenta con ese correo');
  const referrer = body.referralCode
    ? await prisma.user.findUnique({ where: { referralCode: body.referralCode }, select: { id: true, status: true } })
    : null;
  if (body.referralCode && (!referrer || referrer.status !== 'ACTIVE')) throw badRequest('El código de invitación no es válido');
  const user = await prisma.user.create({
    data: {
      referralCode: newReferralCode(),
      referredById: referrer?.id,
      // Bienvenida del referido: su primer servicio paga la tarifa reducida
      commissionCredits: referrer && body.role === 'CLIENT' ? 1 : 0,
      name: body.name,
      email: body.email,
      phone: body.phone,
      department: body.department,
      city: body.city,
      role: body.role,
      passwordHash: await bcrypt.hash(body.password, 10),
      professional: body.role === 'PROFESSIONAL' ? { create: { city: body.city, diagnosticFee: config.diagnosticFee } } : undefined,
    },
  });
  res.status(201).json(await authResponse(await userWithProfile(user.id)));
});

authRouter.post('/login', async (req, res) => {
  const body = parse(z.object({ email: z.string().trim().toLowerCase(), password: z.string() }), req.body);
  const user = await prisma.user.findUnique({ where: { email: body.email } });
  if (!user || !(await bcrypt.compare(body.password, user.passwordHash))) {
    throw unauthorized('Correo o contraseña incorrectos');
  }
  await assertNotSuspended(user);
  res.json(await authResponse(await userWithProfile(user.id)));
});

const hashToken = (t: string) => crypto.createHash('sha256').update(t).digest('hex');

authRouter.post('/forgot-password', async (req, res) => {
  const { email } = parse(z.object({ email: z.string().trim().toLowerCase().email() }), req.body);
  const user = await prisma.user.findUnique({ where: { email } });
  let devToken: string | undefined;
  if (user) {
    const token = crypto.randomBytes(24).toString('hex');
    await prisma.user.update({
      where: { id: user.id },
      data: { resetTokenHash: hashToken(token), resetTokenExpires: new Date(Date.now() + 60 * 60 * 1000) },
    });
    await sendMail(email, 'Recupera tu contraseña de NetJob', `Tu código de recuperación es: ${token}\nVence en 1 hora.`);
    if (process.env.NODE_ENV !== 'production') devToken = token;
  }
  // Misma respuesta exista o no la cuenta, para no revelar correos registrados
  res.json({ ok: true, message: 'Si el correo existe, enviamos instrucciones para recuperar la contraseña.', devToken });
});

authRouter.post('/reset-password', async (req, res) => {
  const body = parse(z.object({ token: z.string().min(10), password }), req.body);
  const user = await prisma.user.findFirst({
    where: { resetTokenHash: hashToken(body.token), resetTokenExpires: { gt: new Date() } },
  });
  if (!user) throw badRequest('El código es inválido o ya venció');
  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: await bcrypt.hash(body.password, 10), resetTokenHash: null, resetTokenExpires: null },
  });
  res.json({ ok: true });
});

// ---- Cuenta del usuario autenticado ----
export const meRouter = Router();
meRouter.use(requireAuth);

meRouter.get('/', async (req, res) => {
  res.json(await userPayload(await userWithProfile(req.user!.id)));
});

/**
 * Beneficios del usuario: código para invitar, personas invitadas y (cliente) el avance
 * hacia la próxima tarifa reducida.
 */
meRouter.get('/benefits', async (req, res) => {
  const code = await ensureReferralCode(req.user!.id);
  const [u, invited, rewarded, completed] = await Promise.all([
    prisma.user.findUniqueOrThrow({
      where: { id: req.user!.id },
      select: { role: true, commissionCredits: true, clientRatingAvg: true, clientRatingCount: true },
    }),
    prisma.user.count({ where: { referredById: req.user!.id } }),
    prisma.user.count({ where: { referredById: req.user!.id, referralRewarded: true } }),
    prisma.serviceRequest.count({ where: { clientId: req.user!.id, status: 'COMPLETED' } }),
  ]);
  res.json({
    referralCode: code,
    invited,
    rewarded,
    role: u.role,
    credits: u.commissionCredits,
    standardRate: config.commissionRate,
    reducedRate: config.loyaltyCommissionRate,
    loyalty: {
      every: config.loyaltyEvery,
      minRating: config.loyaltyMinRating,
      completed,
      // Servicios que faltan para el siguiente beneficio
      remaining: config.loyaltyEvery - (completed % config.loyaltyEvery),
      ratingAvg: u.clientRatingAvg,
      ratingCount: u.clientRatingCount,
      ratingOk: u.clientRatingCount > 0 && u.clientRatingAvg > config.loyaltyMinRating,
    },
    referralBoostDays: config.referralBoostDays,
  });
});

meRouter.patch('/', async (req, res) => {
  const body = parse(
    z.object({
      name: z.string().trim().min(2).optional(),
      phone: z.string().trim().min(7).max(20).nullable().optional(),
      department: z.string().trim().max(80).nullable().optional(),
      city: z.string().trim().max(80).nullable().optional(),
    }),
    req.body,
  );
  await prisma.user.update({ where: { id: req.user!.id }, data: body });
  res.json(await userPayload(await userWithProfile(req.user!.id)));
});

meRouter.post('/avatar', upload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Adjunta una imagen en el campo "file"');
  await prisma.user.update({ where: { id: req.user!.id }, data: { avatarUrl: await storePublic(req.file) } });
  res.json(await userPayload(await userWithProfile(req.user!.id)));
});

meRouter.post('/change-password', async (req, res) => {
  const body = parse(z.object({ currentPassword: z.string(), newPassword: password }), req.body);
  const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
  if (!(await bcrypt.compare(body.currentPassword, user.passwordHash))) throw badRequest('La contraseña actual no es correcta');
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash: await bcrypt.hash(body.newPassword, 10) } });
  res.json({ ok: true });
});
