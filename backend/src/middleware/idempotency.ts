import type { Request, Response, NextFunction } from 'express';
import crypto from 'node:crypto';
import { db } from '../db/knex.js';

export async function idempotencyMiddleware(req: Request, res: Response, next: NextFunction): Promise<void> {
  const idempotencyKey = (req.headers['idempotency-key'] as string | undefined)?.trim();
  if (!idempotencyKey || req.method === 'GET' || req.method === 'HEAD') {
    next();
    return;
  }

  const userId = req.user?.id || 'anonymous';
  const requestBodyStr = JSON.stringify(req.body || {});
  const currentHash = crypto.createHash('sha256').update(`${req.method}:${req.baseUrl + req.path}:${requestBodyStr}`).digest('hex');

  try {
    const cached = await db('idempotency_keys')
      .where({ user_id: userId, key_value: idempotencyKey })
      .first();

    if (cached && new Date(cached.expires_at) > new Date()) {
      if (cached.request_hash !== currentHash) {
        res.status(409).json({
          error: {
            code: 'CONFLICT',
            message: 'Idempotency key was previously used with a different request payload',
            details: {},
          },
        });
        return;
      }

      if (cached.response_status) {
        const body = typeof cached.response_body === 'string'
          ? JSON.parse(cached.response_body)
          : cached.response_body;
        res.status(cached.response_status).json(body);
        return;
      }
    }
  } catch (err) {
    console.error('[IdempotencyMiddleware] Error checking idempotency in MySQL:', err);
  }

  // Intercept json method to cache the response in DB
  const originalJson = res.json.bind(res);
  res.json = (body: any) => {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      db('idempotency_keys')
        .insert({
          user_id: userId,
          key_value: idempotencyKey,
          request_hash: currentHash,
          response_status: res.statusCode,
          response_body: JSON.stringify(body),
          created_at: new Date(),
          expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000),
        })
        .onConflict(['user_id', 'key_value'])
        .merge({
          request_hash: currentHash,
          response_status: res.statusCode,
          response_body: JSON.stringify(body),
          expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000),
        })
        .catch((err) => console.error('[IdempotencyMiddleware] Error saving response:', err));
    }
    return originalJson(body);
  };

  next();
}

