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

  if (config.AUTH_STUB_MODE) {
    // Development and test stub
    if (authHeader && authHeader.startsWith('Bearer user:')) {
      const customId = authHeader.replace('Bearer user:', '').trim();
      req.user = {
        id: customId,
        phone: '+919876543210',
        name: `User ${customId}`,
      };
      next();
      return;
    }

    // Default test user
    req.user = {
      id: 'usr_arhaam',
      phone: '+919876543210',
      name: 'Arhaam',
    };
    next();
    return;
  }

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new UnauthenticatedError('Missing or invalid Authorization header');
  }

  // Real Firebase verification goes here in production
  next();
}

/**
 * Asserts that the authenticated user is a member of the given ledger.
 */
export function assertMember(memberIds: string[], userId: string): void {
  if (!memberIds.includes(userId)) {
    throw new ForbiddenError(`User ${userId} is not a member of this ledger`);
  }
}
