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
  listSettlementsForLedger,
} from './store.js';
import { NotFoundError, UnauthenticatedError } from '../../lib/errors.js';
import { assertLedgerMember } from '../ledgers/routes.js';

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
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const body = createSettlementSchema.parse(req.body);

    const result = await createSettlement({
      ledgerId: body.ledgerId,
      fromUserId: callerId,
      toUserId: body.toUserId,
      amountPaise: body.amountPaise,
      method: body.method,
      createdBy: callerId,
    });

    res.status(201).json({
      data: result.settlement,
      balances: result.balances,
    });
  } catch (err: any) {
    if (err.statusCode === 409 && err.existingSettlement) {
      return res.status(409).json({
        error: {
          code: 'CONFLICT',
          message: err.message,
          existingSettlement: err.existingSettlement,
        },
      });
    }
    next(err);
  }
});

// GET /v1/settlements/:id
settlementsRouter.get('/settlements/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const settlement = await getSettlement(req.params.id);
    await assertLedgerMember(settlement.ledgerId, callerId);

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
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const result = await confirmSettlement(req.params.id, callerId);
    res.json({
      data: result.settlement,
      balances: result.balances,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/reject
settlementsRouter.post('/settlements/:id/reject', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const result = await rejectSettlement(req.params.id, callerId);
    res.json({
      data: result.settlement,
      balances: result.balances,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/cancel
settlementsRouter.post('/settlements/:id/cancel', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const result = await cancelSettlement(req.params.id, callerId);
    res.json({
      data: result.settlement,
      balances: result.balances,
    });
  } catch (err) {
    next(err);
  }
});

// POST /v1/settlements/:id/resubmit
settlementsRouter.post('/settlements/:id/resubmit', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const body = resubmitSettlementSchema.parse(req.body || {});
    const result = await resubmitSettlement({
      id: req.params.id,
      actorUserId: callerId,
      newAmountPaise: body.amountPaise,
    });
    res.json({
      data: result.settlement,
      balances: result.balances,
    });
  } catch (err) {
    next(err);
  }
});

// GET /v1/ledgers/:id/settlements
settlementsRouter.get('/ledgers/:id/settlements', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }
    const ledgerId = req.params.id;
    const dbLedger = await db('ledgers').where({ id: ledgerId }).first();
    if (!dbLedger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }
    await assertLedgerMember(ledgerId, callerId);

    const settlements = await listSettlementsForLedger(ledgerId);
    res.json({
      data: settlements,
    });
  } catch (err) {
    next(err);
  }
});
