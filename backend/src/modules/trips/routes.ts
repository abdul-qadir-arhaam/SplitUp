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
tripsRouter.post('/trips', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = createTripSchema.parse(req.body);

    const trip = createTrip({
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
tripsRouter.get('/trips', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const result = listUserTrips(callerId);

    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips/:id
tripsRouter.get('/trips/:id', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const details = getTripDetails(req.params.id, callerId);

    res.json({
      data: details,
    });
  } catch (err) {
    next(err);
  }
});

// PATCH /v1/trips/:id
tripsRouter.patch('/trips/:id', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = updateTripSchema.parse(req.body);

    const updated = updateTrip(req.params.id, callerId, body);
    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// PATCH /v1/trips/:id/budget
tripsRouter.patch('/trips/:id/budget', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = updateBudgetSchema.parse(req.body);

    const updated = updateTripBudget(req.params.id, callerId, body.budgetPaise);
    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/trips/:id/complete
tripsRouter.post('/trips/:id/complete', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const updated = completeTrip(req.params.id, callerId);

    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips/:id/dashboard
tripsRouter.get('/trips/:id/dashboard', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const dashboard = getTripDashboard(req.params.id, callerId);

    res.json({
      data: dashboard,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/trips/:id/graph
tripsRouter.get('/trips/:id/graph', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const mode = req.query.mode === 'actual' ? 'actual' : 'simplified';
    const graph = getTripGraph(req.params.id, callerId, mode);

    res.json({
      data: graph,
    });
  } catch (err) {
    next(err);
  }
});
