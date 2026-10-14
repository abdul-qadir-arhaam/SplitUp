import type { Request, Response, NextFunction } from 'express';
import { UnauthenticatedError, ForbiddenError } from '../lib/errors.js';
import { config } from '../config/env.js';

export interface AuthUser {
  id: string;
  phone: string;
  name: string;
  firebaseUid?: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  const xUserId = req.headers['x-user-id'] as string;

  if (
    req.path === '/users/auth/verify' ||
    req.path === '/users/auth/login' ||
    req.path === '/users/auth/register' ||
    req.path.endsWith('/auth/login') ||
    req.path.endsWith('/auth/register')
  ) {
    next();
    return;
  }

  if (xUserId) {
    req.user = {
      id: xUserId,
      phone: '+919876543210',
      name: `User ${xUserId}`,
    };
    next();
    return;
  }

  if (authHeader && authHeader.startsWith('Bearer ')) {
    const rawToken = authHeader.replace('Bearer ', '').trim();
    let userId = '';
    if (rawToken.startsWith('user:')) {
      userId = rawToken.replace('user:', '').trim();
    } else if (rawToken.startsWith('token_usr_')) {
      const parts = rawToken.split('_');
      userId = `usr_${parts[2]}`;
    } else if (rawToken.startsWith('usr_')) {
      userId = rawToken;
    } else {
      userId = rawToken;
    }

    req.user = {
      id: userId || 'usr_arhaam',
      phone: '+919876543210',
      name: `User ${userId}`,
    };
    next();
    return;
  }

  if (config.AUTH_STUB_MODE) {
    req.user = {
      id: 'usr_arhaam',
      phone: '+919876543210',
      name: 'Arhaam',
    };
    next();
    return;
  }

  throw new UnauthenticatedError('Missing or invalid Authorization header');
}

/**
 * Asserts that the authenticated user is a member of the given ledger.
 */
export function assertMember(memberIds: string[], userId: string): void {
  if (!memberIds.includes(userId)) {
    throw new ForbiddenError(`User ${userId} is not a member of this ledger`);
  }
}
