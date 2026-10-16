import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import {
  createSettlement,
  getSettlement,
  confirmSettlement,
  rejectSettlement,
  cancelSettlement,
  resubmitSettlement,
  mapDbSettlementToModel,
} from './store.js';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { NotFoundError } from '../../lib/errors.js';

export const settlementsRouter = Router();

const createSettlementSchema = z.object({
  ledgerId: z.string(),
  toUserId: z.string(),
  amountPaise: z.number().int().positive(),
  method: z.enum(['CASH', 'UPI', 'OFFSET', 'OTHER']).default('CASH'),
});

const resubmitSettlementSchema = z.object({
  amountPaise: z.number().int().positive().optional(),
});

// POST /v1/settlements
settlementsRouter.post('/settlements', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = createSettlementSchema.parse(req.body);

    const settlement = await createSettlement({
      ledgerId: body.ledgerId,
      fromUserId: callerId,
      toUserId: body.toUserId,
      amountPaise: body.amountPaise,
      method: body.method,
      createdBy: callerId,
    });

    res.status(201).json({
      data: settlement,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/settlements/:id
settlementsRouter.get('/settlements/:id', async (req, res, next) => {
  try {
    const settlement = await getSettlement(req.params.id);
    res.json({
      data: settlement,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/confirm
settlementsRouter.post('/settlements/:id/confirm', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const settlement = await confirmSettlement(req.params.id, callerId);
    res.json({
      data: settlement,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/reject
settlementsRouter.post('/settlements/:id/reject', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const settlement = await rejectSettlement(req.params.id, callerId);
    res.json({
      data: settlement,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/cancel
settlementsRouter.post('/settlements/:id/cancel', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const settlement = await cancelSettlement(req.params.id, callerId);
    res.json({
      data: settlement,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/resubmit
settlementsRouter.post('/settlements/:id/resubmit', async (req, res, next) => {
  try {
    const callerId = req.user?.id || 'usr_arhaam';
    const body = resubmitSettlementSchema.parse(req.body || {});
    const settlement = await resubmitSettlement({
      id: req.params.id,
      actorUserId: callerId,
      newAmountPaise: body.amountPaise,
    });
    res.json({
      data: settlement,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/ledgers/:id/settlements
settlementsRouter.get('/ledgers/:id/settlements', async (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const dbRows = await db('settlements')
      .where({ ledger_id: ledgerId })
      .orderBy('created_at', 'desc');

    if (dbRows.length > 0) {
      return res.json({
        data: dbRows.map(mapDbSettlementToModel),
      });
    }

    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      const dbLedger = await db('ledgers').where({ id: ledgerId }).first();
      if (!dbLedger) {
        throw new NotFoundError(`Ledger ${ledgerId} not found`);
      }
      return res.json({ data: [] });
    }

    res.json({
      data: ledger.settlements || [],
    });
  } catch (err) {
    next(err);
  }
});
