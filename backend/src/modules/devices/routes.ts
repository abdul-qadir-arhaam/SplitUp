import { Router } from 'express';
import { z } from 'zod';
import { ulid } from 'ulidx';

export const devicesRouter = Router();

interface DeviceToken {
  id: string;
  userId: string;
  fcmToken: string;
  platform: 'android' | 'ios' | 'web';
  createdAt: string;
  lastSeenAt: string;
}

export const inMemoryDeviceTokens = new Map<string, DeviceToken>();

const registerTokenSchema = z.object({
  fcmToken: z.string().min(10).max(512),
  platform: z.enum(['android', 'ios', 'web']).default('android'),
});

// POST /v1/devices/tokens
devicesRouter.post('/devices/tokens', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const body = registerTokenSchema.parse(req.body);

  const existing = inMemoryDeviceTokens.get(body.fcmToken);
  const now = new Date().toISOString();

  if (existing) {
    existing.userId = callerId;
    existing.platform = body.platform;
    existing.lastSeenAt = now;
    res.json({ data: existing });
    return;
  }

  const tokenRecord: DeviceToken = {
    id: `dtk_${ulid()}`,
    userId: callerId,
    fcmToken: body.fcmToken,
    platform: body.platform,
    createdAt: now,
    lastSeenAt: now,
  };

  inMemoryDeviceTokens.set(body.fcmToken, tokenRecord);
  res.status(201).json({ data: tokenRecord });
});

// DELETE /v1/devices/tokens/:token
devicesRouter.delete('/devices/tokens/:token', (req, res) => {
  const token = req.params.token;
  inMemoryDeviceTokens.delete(token);
  res.json({ success: true });
});
