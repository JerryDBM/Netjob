import type { User } from '@prisma/client';

export function publicUser(u: User) {
  const { passwordHash, resetTokenHash, resetTokenExpires, ...rest } = u;
  return rest;
}
