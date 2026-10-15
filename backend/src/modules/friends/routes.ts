import { Router } from 'express';
import { z } from 'zod';
import {
  listFriends,
  addFriend,
  updateFriendNickname,
  removeFriend,
  blockUser,
  unblockUser,
} from './store.js';
import { UnauthenticatedError } from '../../lib/errors.js';

export const friendsRouter = Router();

// GET /v1/friends
friendsRouter.get('/friends', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const friends = await listFriends(callerId);
    res.json({
      data: friends,
    });
  } catch (err) {
    next(err);
  }
});

const addFriendSchema = z.object({
  phone: z.string(),
  name: z.string().optional(),
  contactName: z.string().optional(),
});

// POST /v1/friends
friendsRouter.post('/friends', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const body = addFriendSchema.parse(req.body);

    const result = await addFriend({
      ownerUserId: callerId,
      phone: body.phone,
      name: body.name,
      contactName: body.contactName,
    });

    res.status(201).json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

const nicknameSchema = z.object({
  nickname: z.string().nullable(),
});

// PATCH /v1/friends/:id/nickname
friendsRouter.patch('/friends/:id/nickname', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const friendId = req.params.id;
    const body = nicknameSchema.parse(req.body);

    const result = await updateFriendNickname(callerId, friendId, body.nickname);
    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// DELETE /v1/friends/:id
friendsRouter.delete('/friends/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const friendId = req.params.id;

    const result = await removeFriend(callerId, friendId);
    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/friends/:id/block
friendsRouter.post('/friends/:id/block', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const friendId = req.params.id;

    const result = await blockUser(callerId, friendId);
    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// DELETE /v1/friends/:id/block
friendsRouter.delete('/friends/:id/block', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const friendId = req.params.id;

    const result = await unblockUser(callerId, friendId);
    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

