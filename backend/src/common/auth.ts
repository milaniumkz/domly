import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { ApiError } from './api';
import { env } from './env';

export type AuthUser = {
  id: string;
  role: 'customer' | 'cleaner' | 'admin' | 'superadmin';
  phone: string;
};

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function signAccessToken(user: AuthUser): string {
  return jwt.sign(user, env.jwtAccessSecret, { expiresIn: env.jwtAccessTtlSeconds });
}

export function signRefreshToken(user: AuthUser): string {
  return jwt.sign({ id: user.id, role: user.role, phone: user.phone }, env.jwtRefreshSecret, {
    expiresIn: env.jwtRefreshTtlSeconds,
  });
}

export function verifyRefreshToken(token: string): AuthUser {
  return jwt.verify(token, env.jwtRefreshSecret) as AuthUser;
}

export function verifyAccessToken(token: string): AuthUser {
  return jwt.verify(token, env.jwtAccessSecret) as AuthUser;
}

export function auth(requiredRoles: AuthUser['role'][] = [], options: { allowQueryToken?: boolean } = {}) {
  return (req: Request, _res: Response, next: NextFunction) => {
    const raw = req.header('authorization') ?? '';
    const queryToken = options.allowQueryToken
      ? String(req.query.access_token ?? req.query.accessToken ?? '')
      : '';
    const token = raw.startsWith('Bearer ') ? raw.slice(7) : queryToken;
    if (!token) return next(new ApiError(401, 'unauthorized', 'Войдите в аккаунт заново.'));
    try {
      const user = verifyAccessToken(token);
      if (requiredRoles.length > 0 && !requiredRoles.includes(user.role)) {
        return next(new ApiError(403, 'forbidden', 'Недостаточно прав для этого действия.'));
      }
      req.user = user;
      return next();
    } catch {
      return next(new ApiError(401, 'unauthorized', 'Сессия истекла. Войдите заново.'));
    }
  };
}
