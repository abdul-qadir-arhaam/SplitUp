import { Router } from 'express';
import { z } from 'zod';
import {
  createTrip,
  listUserTrips,
  getTripDetails,
  updateTrip,
  updateTripBudget,
  completeTrip,
  getTripDashboard,
  getTripGraph,
} from './store.js';
import { UnauthenticatedError } from '../../lib/errors.js';

export const tripsRouter = Router();

const createTripSchema = z.object({
  name: z.string().min(1).max(100),
  budgetPaise: z.number().int().positive(),
  startDate: z.string().nullable().optional(),
  endDate: z.string().nullable().optional(),
  memberUserIds: z.array(z.string()).default([]),
  sourceGroupId: z.string().nullable().optional(),
  photoUrl: z.string().url().nullable().optional(),
});

const updateTripSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  photoUrl: z.string().url().nullable().optional(),
  startDate: z.string().nullable().optional(),
  endDate: z.string().nullable().optional(),
});

const updateBudgetSchema = z.object({
  budgetPaise: z.number().int().positive(),
});

// POST /v1/trips
tripsRouter.post('/trips', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const body = createTripSchema.parse(req.body);

    const trip = await createTrip({
      name: body.name,
      budgetPaise: body.budgetPaise,
      startDate: body.startDate,
      endDate: body.endDate,
      creatorUserId: callerId,
      memberUserIds: body.memberUserIds,
      sourceGroupId: body.sourceGroupId,
      photoUrl: body.photoUrl,
    });

    res.status(201).json({
      data: trip,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips
tripsRouter.get('/trips', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const result = await listUserTrips(callerId);

    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips/:id
tripsRouter.get('/trips/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const details = await getTripDetails(req.params.id, callerId);

    res.json({
      data: details,
    });
  } catch (err) {
    next(err);
  }
});

// PATCH /v1/trips/:id
tripsRouter.patch('/trips/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const body = updateTripSchema.parse(req.body);

    const updated = await updateTrip(req.params.id, callerId, body);
    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// PATCH /v1/trips/:id/budget
tripsRouter.patch('/trips/:id/budget', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const body = updateBudgetSchema.parse(req.body);

    const updated = await updateTripBudget(req.params.id, callerId, body.budgetPaise);
    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/trips/:id/complete
tripsRouter.post('/trips/:id/complete', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const updated = await completeTrip(req.params.id, callerId);

    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips/:id/dashboard
tripsRouter.get('/trips/:id/dashboard', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const dashboard = await getTripDashboard(req.params.id, callerId);

    res.json({
      data: dashboard,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips/:id/graph
tripsRouter.get('/trips/:id/graph', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const mode = req.query.mode === 'actual' ? 'actual' : 'simplified';
    const graph = await getTripGraph(req.params.id, callerId, mode);

    res.json({
      data: graph,
    });
  } catch (err) {
    next(err);
  }
});
