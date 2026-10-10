import { Router } from 'express';
import { z } from 'zod';
import {
  createOffset,
  confirmOffset,
  rejectOffset,
  getOffsetSuggestions,
  inMemoryOffsets,
} from './store.js';

export const offsetsRouter = Router();

const createOffsetSchema = z.object({
  groupLedgerId: z.string(),
  toUserId: z.string(),
  amountPaise: z.number().int().positive(),
});

// POST /v1/offsets
offsetsRouter.post('/offsets', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = createOffsetSchema.parse(req.body);

    const offset = createOffset({
      groupLedgerId: body.groupLedgerId,
      fromUserId: callerId,
      toUserId: body.toUserId,
      amountPaise: body.amountPaise,
    });

    res.status(201).json({
      data: offset,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/offsets/:id
offsetsRouter.get('/offsets/:id', (req, res, next) => {
  try {
    const offset = inMemoryOffsets.get(req.params.id);
    if (!offset) {
      return res.status(404).json({
        error: {
          code: 'NOT_FOUND',
          message: `Offset ${req.params.id} not found`,
        },
      });
    }

    res.json({
      data: offset,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/offsets/:id/confirm
offsetsRouter.post('/offsets/:id/confirm', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const updated = confirmOffset(req.params.id, callerId);

    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/offsets/:id/reject
offsetsRouter.post('/offsets/:id/reject', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const updated = rejectOffset(req.params.id, callerId);

    res.json({
      data: updated,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/offsets/suggestions
offsetsRouter.get('/offsets/suggestions', (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const groupLedgerId = req.query.groupLedgerId as string;
    if (!groupLedgerId) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'groupLedgerId query param is required',
        },
      });
    }

    const suggestions = getOffsetSuggestions(groupLedgerId, callerId);
    res.json({
      data: suggestions,
    });
  } catch (err) {
    next(err);
  }
});
