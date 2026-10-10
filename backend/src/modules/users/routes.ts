import { Router } from 'express';
import { z } from 'zod';
import { inMemoryUsers, findUserById, findUserByPhone, createUser, updateUser, mergePlaceholder } from './store.js';
import { normalizePhoneE164 } from './phone.js';
import { NotFoundError, ValidationError } from '../../lib/errors.js';

export const usersRouter = Router();

const updateMeSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  email: z.string().email().max(254).nullable().optional(),
  photoUrl: z.string().url().max(500).nullable().optional(),
});

// GET /v1/users/me
usersRouter.get('/users/me', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const user = findUserById(callerId);
  if (!user) {
    throw new NotFoundError(`User ${callerId} not found`);
  }

  res.json({
    data: {
      id: user.id,
      name: user.name,
      phoneE164: user.phoneE164,
      email: user.email,
      photoUrl: user.photoUrl,
      isPlaceholder: user.isPlaceholder,
      status: user.status,
      createdAt: user.createdAt,
    },
  });
});

// PATCH /v1/users/me
usersRouter.patch('/users/me', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const body = updateMeSchema.parse(req.body);

  const updated = updateUser(callerId, body);
  if (!updated) {
    throw new NotFoundError(`User ${callerId} not found`);
  }

  res.json({
    data: {
      id: updated.id,
      name: updated.name,
      phoneE164: updated.phoneE164,
      email: updated.email,
      photoUrl: updated.photoUrl,
      status: updated.status,
      updatedAt: updated.updatedAt,
    },
  });
});

const verifyAuthSchema = z.object({
  phone: z.string(),
  name: z.string().optional(),
  firebaseUid: z.string().optional(),
});

// POST /v1/users/auth/verify (Used for phone sign-in & placeholder merge trigger)
usersRouter.post('/users/auth/verify', (req, res) => {
  const body = verifyAuthSchema.parse(req.body);
  const normalizedPhone = normalizePhoneE164(body.phone);

  let user = findUserByPhone(normalizedPhone);
  let mergeSummary = null;

  if (user && user.isPlaceholder) {
    // A placeholder already existed with this phone! Create/promote to real user and merge
    const placeholder = user;
    const realUser = createUser({
      phoneE164: normalizedPhone,
      name: body.name || placeholder.name || 'New User',
      firebaseUid: body.firebaseUid || null,
      isPlaceholder: false,
      status: 'ACTIVE',
    });

    mergeSummary = mergePlaceholder(placeholder, realUser);
    user = realUser;
  } else if (!user) {
    // New registration
    user = createUser({
      phoneE164: normalizedPhone,
      name: body.name || 'New User',
      firebaseUid: body.firebaseUid || null,
      isPlaceholder: false,
      status: 'ACTIVE',
    });
  } else {
    // Existing real user
    if (body.firebaseUid && !user.firebaseUid) {
      updateUser(user.id, { firebaseUid: body.firebaseUid });
    }
    if (body.name && user.name === 'New User') {
      updateUser(user.id, { name: body.name });
    }
  }

  res.json({
    data: {
      user: {
        id: user.id,
        name: user.name,
        phoneE164: user.phoneE164,
        email: user.email,
        photoUrl: user.photoUrl,
        isPlaceholder: user.isPlaceholder,
      },
      mergeSummary,
    },
  });
});
