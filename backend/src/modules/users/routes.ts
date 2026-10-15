import { Router } from 'express';
import { z } from 'zod';
import {
  inMemoryUsers,
  findUserById,
  findUserByPhone,
  findUserByIdAsync,
  findUserByPhoneAsync,
  createUser,
  createUserAsync,
  updateUser,
  updateUserAsync,
  mergePlaceholder,
  hashPassword,
  verifyPassword,
} from './store.js';
import { normalizePhoneE164 } from './phone.js';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { calculateNetBalances, getUserTotalsFromDb } from '../balances/index.js';
import { NotFoundError, ValidationError, ConflictError, UnauthenticatedError } from '../../lib/errors.js';

export const usersRouter = Router();

const updateMeSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  email: z.string().email().max(254).nullable().optional(),
  photoUrl: z.string().url().max(500).nullable().optional(),
});

// GET /v1/users/me
usersRouter.get('/users/me', async (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const user = await findUserByIdAsync(callerId);
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
usersRouter.patch('/users/me', async (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const body = updateMeSchema.parse(req.body);

  const updated = await updateUserAsync(callerId, body);
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

// GET /v1/users/me/totals
usersRouter.get('/users/me/totals', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Missing or invalid Authorization header');
    }

    const totals = await getUserTotalsFromDb(callerId);
    res.json({
      data: totals,
    });
  } catch (err) {
    next(err);
  }
});

const registerAuthSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  phone: z.string().min(10, 'Valid phone number is required'),
  email: z.string().email().max(254).nullable().optional(),
  password: z.string().min(6, 'Password must be at least 6 characters'),
});

// POST /v1/users/auth/register (Phone + Password registration saved permanently to MySQL)
usersRouter.post('/users/auth/register', async (req, res) => {
  const body = registerAuthSchema.parse(req.body);
  const normalizedPhone = normalizePhoneE164(body.phone);
  const passwordHash = hashPassword(body.password);

  let user = await findUserByPhoneAsync(normalizedPhone);
  let mergeSummary = null;

  if (user && !user.isPlaceholder) {
    throw new ConflictError('A user with this mobile number already exists. Please log in.');
  }

  if (user && user.isPlaceholder) {
    const placeholder = user;
    const realUser = await createUserAsync({
      phoneE164: normalizedPhone,
      name: body.name.trim(),
      email: body.email?.trim() || null,
      passwordHash,
      isPlaceholder: false,
      status: 'ACTIVE',
    });

    mergeSummary = mergePlaceholder(placeholder, realUser);
    user = realUser;
  } else {
    user = await createUserAsync({
      phoneE164: normalizedPhone,
      name: body.name.trim(),
      email: body.email?.trim() || null,
      passwordHash,
      isPlaceholder: false,
      status: 'ACTIVE',
    });
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
      token: `Bearer user:${user.id}`,
      mergeSummary,
    },
  });
});

const loginAuthSchema = z.object({
  phone: z.string().min(10, 'Valid phone number is required'),
  password: z.string().min(1, 'Password is required'),
});

// POST /v1/users/auth/login (Phone + Password login checked against MySQL)
usersRouter.post('/users/auth/login', async (req, res) => {
  const body = loginAuthSchema.parse(req.body);
  const normalizedPhone = normalizePhoneE164(body.phone);

  const user = await findUserByPhoneAsync(normalizedPhone);
  if (!user || user.isPlaceholder) {
    throw new NotFoundError('No account found for this mobile number. Please sign up first.');
  }

  if (user.passwordHash) {
    const isValid = verifyPassword(body.password, user.passwordHash);
    if (!isValid) {
      throw new ValidationError('Incorrect password. Please try again.');
    }
  } else {
    // Legacy/stub user without password hash: set the password now
    await updateUserAsync(user.id, { passwordHash: hashPassword(body.password) });
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
      token: `Bearer user:${user.id}`,
    },
  });
});

const verifyAuthSchema = z.object({
  phone: z.string(),
  name: z.string().optional(),
  firebaseUid: z.string().optional(),
});

// POST /v1/users/auth/verify (Used for phone OTP sign-in & placeholder merge trigger)
usersRouter.post('/users/auth/verify', async (req, res) => {
  const body = verifyAuthSchema.parse(req.body);
  const normalizedPhone = normalizePhoneE164(body.phone);

  let user = await findUserByPhoneAsync(normalizedPhone);
  let mergeSummary = null;

  if (user && user.isPlaceholder) {
    const placeholder = user;
    const realUser = await createUserAsync({
      phoneE164: normalizedPhone,
      name: body.name || placeholder.name || 'New User',
      firebaseUid: body.firebaseUid || null,
      isPlaceholder: false,
      status: 'ACTIVE',
    });

    mergeSummary = mergePlaceholder(placeholder, realUser);
    user = realUser;
  } else if (!user) {
    user = await createUserAsync({
      phoneE164: normalizedPhone,
      name: body.name || 'New User',
      firebaseUid: body.firebaseUid || null,
      isPlaceholder: false,
      status: 'ACTIVE',
    });
  } else {
    if (body.firebaseUid && !user.firebaseUid) {
      await updateUserAsync(user.id, { firebaseUid: body.firebaseUid });
    }
    if (body.name && user.name === 'New User') {
      await updateUserAsync(user.id, { name: body.name });
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
      token: `Bearer user:${user.id}`,
      mergeSummary,
    },
  });
});
