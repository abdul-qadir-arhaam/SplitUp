import type { Request, Response, NextFunction } from 'express';
import crypto from 'node:crypto';

interface CachedResponse {
  statusCode: number;
  body: any;
  hash: string;
  createdAt: number;
}

const idempotencyStore = new Map<string, CachedResponse>();

export function idempotencyMiddleware(req: Request, res: Response, next: NextFunction): void {
  const idempotencyKey = req.headers['idempotency-key'] as string;
  if (!idempotencyKey || req.method === 'GET' || req.method === 'HEAD') {
    next();
    return;
  }

  const userId = req.user?.id || 'anonymous';
  const compositeKey = `${userId}:${idempotencyKey}`;
  const requestBodyStr = JSON.stringify(req.body || {});
  const currentHash = crypto.createHash('sha256').update(`${req.method}:${req.path}:${requestBodyStr}`).digest('hex');

  const cached = idempotencyStore.get(compositeKey);
  if (cached) {
    if (cached.hash !== currentHash) {
      res.status(409).json({
        error: {
          code: 'CONFLICT',
          message: 'Idempotency key was previously used with a different request payload',
          details: {},
        },
      });
      return;
    }

    res.status(cached.statusCode).json(cached.body);
    return;
  }

  // Intercept json method to cache the response
  const originalJson = res.json.bind(res);
  res.json = (body: any) => {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      idempotencyStore.set(compositeKey, {
        statusCode: res.statusCode,
        body,
        hash: currentHash,
        createdAt: Date.now(),
      });
    }
    return originalJson(body);
  };

  next();
}
