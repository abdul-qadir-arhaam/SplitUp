import { Router } from 'express';
import { z } from 'zod';
import {
  createGroup,
  listUserGroups,
  getGroupDetails,
  updateGroup,
  addMember,
  removeMember,
  deleteGroup,
  getGroupDashboard,
  getGroupGraph,
} from './store.js';

export const groupsRouter = Router();

const createGroupSchema = z.object({
  name: z.string().min(1).max(100),
  memberUserIds: z.array(z.string()).default([]),
  photoUrl: z.string().url().nullable().optional(),
});

const updateGroupSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  photoUrl: z.string().url().nullable().optional(),
});

const addMemberSchema = z.object({
  userId: z.string(),
});

// POST /v1/groups
groupsRouter.post('/groups', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = createGroupSchema.parse(req.body);

    const group = await createGroup({
      name: body.name,
      creatorUserId: callerId,
      memberUserIds: body.memberUserIds,
      photoUrl: body.photoUrl,
    });

    res.status(201).json({
      data: group,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/groups
groupsRouter.get('/groups', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const groups = await listUserGroups(callerId);

    res.json({
      data: groups,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/groups/:id
groupsRouter.get('/groups/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const details = await getGroupDetails(req.params.id, callerId);

    res.json({
      data: details,
    });
  } catch (err) {
    next(err);
  }
});

// PATCH /v1/groups/:id
groupsRouter.patch('/groups/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = updateGroupSchema.parse(req.body);

    const updated = await updateGroup(req.params.id, callerId, body);
    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/groups/:id/members
groupsRouter.post('/groups/:id/members', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = addMemberSchema.parse(req.body);

    const updated = await addMember(req.params.id, callerId, body.userId);
    res.status(201).json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// DELETE /v1/groups/:id/members/:userId
groupsRouter.delete('/groups/:id/members/:userId', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const targetUserId = req.params.userId;

    const updated = await removeMember(req.params.id, callerId, targetUserId);
    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// DELETE /v1/groups/:id
groupsRouter.delete('/groups/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const result = await deleteGroup(req.params.id, callerId);

    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/groups/:id/dashboard
groupsRouter.get('/groups/:id/dashboard', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const dashboard = await getGroupDashboard(req.params.id, callerId);

    res.json({
      data: dashboard,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/groups/:id/graph
groupsRouter.get('/groups/:id/graph', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const mode = req.query.mode === 'actual' ? 'actual' : 'simplified';
    const graph = await getGroupGraph(req.params.id, callerId, mode);

    res.json({
      data: graph,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/groups/:id/offset-suggestions
groupsRouter.get('/groups/:id/offset-suggestions', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const { getOffsetSuggestions } = await import('../offsets/store.js');
    const suggestions = getOffsetSuggestions(req.params.id, callerId);

    res.json({
      data: suggestions,
    });
  } catch (err) {
    next(err);
  }
});

