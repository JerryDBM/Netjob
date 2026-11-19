import { Router } from 'express';
import { prisma } from '../db.js';

export const categoriesRouter = Router();

categoriesRouter.get('/', async (_req, res) => {
  res.json(await prisma.category.findMany({ where: { active: true }, orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] }));
});
