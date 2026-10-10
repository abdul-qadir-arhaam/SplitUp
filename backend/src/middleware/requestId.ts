import type { Request, Response, NextFunction } from 'express';
import { ulid } from 'ulidx';

export function requestId(req: Request, res: Response, next: NextFunction): void {
  const reqId = (req.headers['x-request-id'] as string) || ulid();
  req.headers['x-request-id'] = reqId;
  res.setHeader('x-request-id', reqId);
  next();
}
