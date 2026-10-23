import {Database} from '../infrastructure/db/Database';
let authDatabase:Database|null=null;
export function configureAuthDatabase(db:Database|null){authDatabase=db;}
import { createSecretKey, randomUUID } from 'node:crypto';
import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { ApiError } from './api';
import { env } from './env';

// Reuse parsed HMAC keys, never authentication results. Signature/expiry and
// live account revocation checks still run for every protected request.
const accessKey = createSecretKey(Buffer.from(env.jwtAccessSecret));
const refreshKey = createSecretKey(Buffer.from(env.jwtRefreshSecret));

export type AuthUser = {
  id: string;
  role: 'customer' | 'cleaner' | 'admin' | 'superadmin';
  phone: string;
  sessionId?: string;
  authVersion?: number;
  passwordChangeRequired?: boolean;
};

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function signAccessToken(user: AuthUser): string {
  return jwt.sign({ id: user.id, role: user.role, phone: user.phone, ...(user.sessionId?{sessionId:user.sessionId}:{}), ...(user.authVersion!==undefined?{authVersion:user.authVersion}:{}), ...(user.passwordChangeRequired?{passwordChangeRequired:true}:{}) }, accessKey, { expiresIn: env.jwtAccessTtlSeconds });
}

export function signRefreshToken(user: AuthUser): string {
  return jwt.sign({ id: user.id, role: user.role, phone: user.phone, ...(user.sessionId?{sessionId:user.sessionId}:{}), ...(user.authVersion!==undefined?{authVersion:user.authVersion}:{}), ...(user.passwordChangeRequired?{passwordChangeRequired:true}:{}) }, refreshKey, {
    expiresIn: env.jwtRefreshTtlSeconds,
    jwtid: randomUUID(),
  });
}

export function verifyRefreshToken(token: string): AuthUser {
  try {
    const decoded = jwt.verify(token, refreshKey) as jwt.JwtPayload;
    if (typeof decoded.id !== 'string' || !decoded.id || typeof decoded.phone !== 'string'
        || !['customer', 'cleaner', 'admin', 'superadmin'].includes(decoded.role)) {
      throw new Error('Invalid refresh identity');
    }
    return { id: decoded.id, role: decoded.role, phone: decoded.phone, ...(decoded.sessionId?{sessionId:decoded.sessionId}:{}), ...(decoded.authVersion!==undefined?{authVersion:decoded.authVersion}:{}), ...(decoded.passwordChangeRequired?{passwordChangeRequired:true}:{}) };
  } catch (_) {
    throw new ApiError(401, 'unauthorized', 'Сессия истекла. Войдите заново.');
  }
}

export function verifyAccessToken(token: string): AuthUser {
  return jwt.verify(token, accessKey) as AuthUser;
}

export function auth(requiredRoles: AuthUser['role'][] = [], options: { allowQueryToken?: boolean } = {}) {
  return async (req: Request, _res: Response, next: NextFunction) => {
    const raw = req.header('authorization') ?? '';
    const queryToken = options.allowQueryToken
      ? String(req.query.access_token ?? req.query.accessToken ?? '')
      : '';
    const token = raw.startsWith('Bearer ') ? raw.slice(7) : queryToken;
    if (!token) return next(new ApiError(401, 'unauthorized', 'Войдите в аккаунт заново.'));
    try {
      const user = verifyAccessToken(token);
      if(authDatabase){
       const account=(await authDatabase.query('SELECT role,status,deleted_at,auth_version,password_change_required FROM app_users WHERE id=$1',[user.id])).rows[0];
       if(!account||account.deleted_at||account.status==='blocked'||account.role!==user.role||Number(account.auth_version)!==Number(user.authVersion??0))return next(new ApiError(401,'unauthorized','Сессия завершена. Войдите заново.'));
       if(account.password_change_required&&!['/auth/password/change','/auth/logout','/me'].includes(req.path))return next(new ApiError(403,'password_change_required','Сначала смените временный пароль.'));
      }
      if (requiredRoles.length > 0 && !requiredRoles.includes(user.role)) {
        return next(new ApiError(403, 'forbidden', 'Недостаточно прав для этого действия.'));
      }
      req.user = user;
      return next();
    } catch (error:any) {
      if(['JsonWebTokenError','TokenExpiredError','NotBeforeError'].includes(error?.name))return next(new ApiError(401, 'unauthorized', 'Сессия истекла. Войдите заново.'));
      return next(new ApiError(503,'authentication_unavailable','Проверка сессии временно недоступна. Повторите позже.'));
    }
  };
}
