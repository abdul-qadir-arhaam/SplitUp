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

export const friendsRouter = Router();

// GET /v1/friends
friendsRouter.get('/friends', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const friends = listFriends(callerId);
  res.json({
    data: friends,
  });
});

const addFriendSchema = z.object({
  phone: z.string(),
  name: z.string().optional(),
  contactName: z.string().optional(),
});

// POST /v1/friends
friendsRouter.post('/friends', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const body = addFriendSchema.parse(req.body);

  const result = addFriend({
    ownerUserId: callerId,
    phone: body.phone,
    name: body.name,
    contactName: body.contactName,
  });

  res.status(201).json({
    data: result,
  });
});

const nicknameSchema = z.object({
  nickname: z.string().nullable(),
});

// PATCH /v1/friends/:id/nickname
friendsRouter.patch('/friends/:id/nickname', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const friendId = req.params.id;
  const body = nicknameSchema.parse(req.body);

  const result = updateFriendNickname(callerId, friendId, body.nickname);
  res.json({
    data: result,
  });
});

// DELETE /v1/friends/:id
friendsRouter.delete('/friends/:id', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const friendId = req.params.id;

  const result = removeFriend(callerId, friendId);
  res.json({
    data: result,
  });
});

// POST /v1/friends/:id/block
friendsRouter.post('/friends/:id/block', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const friendId = req.params.id;

  const result = blockUser(callerId, friendId);
  res.json({
    data: result,
  });
});

// DELETE /v1/friends/:id/block
friendsRouter.delete('/friends/:id/block', (req, res) => {
  const callerId = req.user?.id || 'usr_arhaam';
  const friendId = req.params.id;

  const result = unblockUser(callerId, friendId);
  res.json({
    data: result,
  });
});
