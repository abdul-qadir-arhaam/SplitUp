import { Router } from 'express';
import { z } from 'zod';
import { ulid } from 'ulidx';
import crypto from 'node:crypto';
import { db } from '../../db/knex.js';
import { getLedgerBalancesFromDb } from '../balances/sqlBalances.js';
import { calculateSplits, simplifyDebts, calculatePairwiseDebts } from '../balances/index.js';
import {
  UnauthenticatedError,
  ValidationError,
  NotFoundError,
  ForbiddenError,
  ConflictError,
} from '../../lib/errors.js';
import { activityStore } from '../activity/store.js';
import { notificationsStore } from '../notifications/store.js';

export const ledgersRouter = Router();

// In-memory data store kept for backward compatibility with un-refactored modules
export interface StoredLedger {
  id: string;
  name: string;
  type: 'INDIVIDUAL' | 'GROUP' | 'TRIP';
  memberIds: string[];
  expenses: any[];
  settlements: any[];
}

export const inMemoryLedgers = new Map<string, StoredLedger>();

async function assertLedgerMember(ledgerId: string, userId: string): Promise<void> {
  const row = await db('ledger_members')
    .where({ ledger_id: ledgerId, user_id: userId })
    .whereNull('left_at')
    .first();
  if (!row) {
    throw new ForbiddenError(`User is not an active member of ledger ${ledgerId}`);
  }
}

async function getLedgerMemberIds(ledgerId: string): Promise<string[]> {
  const rows = await db('ledger_members')
    .where({ ledger_id: ledgerId })
    .whereNull('left_at')
    .select('user_id');
  return rows.map((r) => r.user_id);
}

const categorySchema = z
  .string()
  .transform((c) => c.toLowerCase())
  .pipe(
    z.enum([
      'food',
      'food_and_drinks',
      'travel',
      'stay',
      'fuel',
      'tickets',
      'shopping',
      'groceries',
      'general',
      'other',
    ])
  );

const participantSchema = z
  .object({
    userId: z.string(),
    included: z.boolean(),
    splitValue: z.number().int().optional(),
    owedPaise: z.number().int().optional(),
  })
  .transform((p) => ({
    userId: p.userId,
    included: p.included,
    splitValue: p.splitValue !== undefined ? p.splitValue : p.owedPaise,
  }));

const payerItemSchema = z
  .object({
    userId: z.string().optional(),
    user_id: z.string().optional(),
    paidPaise: z.number().int().positive().optional(),
    paid_paise: z.number().int().positive().optional(),
  })
  .transform((p) => {
    const uid = p.userId || p.user_id;
    const paise = p.paidPaise !== undefined ? p.paidPaise : p.paid_paise;
    if (!uid) throw new ValidationError('Missing userId for payer');
    if (paise === undefined || paise <= 0) throw new ValidationError('Payer amount must be a positive integer');
    return { userId: uid, paidPaise: paise };
  });

const createExpenseSchema = z.preprocess((val: any) => {
  if (val && typeof val === 'object') {
    // Backward compatibility if single payer is sent
    if (!val.payers) {
      const singleUserId =
        val.payerId ||
        val.payerUserId ||
        val.paidBy ||
        (val.payer && (val.payer.userId || val.payer.user_id));
      if (singleUserId && val.totalPaise) {
        val.payers = [{ userId: singleUserId, paidPaise: val.totalPaise }];
      }
    }
  }
  return val;
}, z.object({
  title: z.string().min(1).max(120),
  totalPaise: z.number().int().positive(),
  category: categorySchema.default('other'),
  splitType: z.enum(['EQUAL', 'EXACT', 'PERCENT', 'SHARES']),
  payers: z.array(payerItemSchema).nonempty(),
  participants: z.array(participantSchema).nonempty(),
  expenseDate: z.string().default(() => new Date().toISOString().split('T')[0]),
  note: z.string().max(500).optional(),
}));

const updateExpenseSchema = z.preprocess((val: any) => {
  if (val && typeof val === 'object') {
    if (!val.payers) {
      const singleUserId =
        val.payerId ||
        val.payerUserId ||
        val.paidBy ||
        (val.payer && (val.payer.userId || val.payer.user_id));
      if (singleUserId && val.totalPaise) {
        val.payers = [{ userId: singleUserId, paidPaise: val.totalPaise }];
      }
    }
  }
  return val;
}, z.object({
  title: z.string().min(1).max(120).optional(),
  category: categorySchema.optional(),
  totalPaise: z.number().int().positive().optional(),
  splitType: z.enum(['EQUAL', 'EXACT', 'PERCENT', 'SHARES']).optional(),
  payers: z.array(payerItemSchema).nonempty().optional(),
  participants: z.array(participantSchema).nonempty().optional(),
  expenseDate: z.string().optional(),
  note: z.string().max(500).optional(),
}));

// Create Expense in Ledger
ledgersRouter.post('/ledgers/:id/expenses', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const ledgerId = req.params.id;
    await assertLedgerMember(ledgerId, callerId);

    const body = createExpenseSchema.parse(req.body);

    // Validate Rule 1: SUM(payers.paidPaise) = totalPaise
    const sumPaid = body.payers.reduce((sum, p) => sum + p.paidPaise, 0);
    if (sumPaid !== body.totalPaise) {
      throw new ValidationError(
        `Sum of payer amounts (${sumPaid} paise) does not equal expense total (${body.totalPaise} paise)`
      );
    }

    // Check for duplicate payers
    const payerUserIds = new Set<string>();
    for (const p of body.payers) {
      if (payerUserIds.has(p.userId)) {
        throw new ValidationError(`Duplicate payer ${p.userId} in expense payers`);
      }
      payerUserIds.add(p.userId);
    }

    // Validate Rule 2 & 3: Participants must be current ledger members and excluded cannot be payers
    const memberIds = await getLedgerMemberIds(ledgerId);
    const memberSet = new Set(memberIds);

    for (const p of body.payers) {
      if (!memberSet.has(p.userId)) {
        throw new ForbiddenError(`Payer ${p.userId} is not a member of ledger ${ledgerId}`);
      }
    }
    for (const part of body.participants) {
      if (!memberSet.has(part.userId)) {
        throw new ForbiddenError(`Participant ${part.userId} is not a member of ledger ${ledgerId}`);
      }
      if (!part.included && payerUserIds.has(part.userId)) {
        throw new ValidationError(`Excluded member ${part.userId} cannot be a payer for this expense`);
      }
    }

    // Compute splits with deterministic integer paise rounding
    const splits = calculateSplits(body.totalPaise, body.splitType, body.participants);

    // Verify split sum invariant
    const sumSplits = splits.reduce((sum, s) => sum + (s.included ? s.owedPaise : 0), 0);
    if (sumSplits !== body.totalPaise) {
      throw new ValidationError(
        `Sum of splits (${sumSplits} paise) does not equal total expense (${body.totalPaise} paise)`
      );
    }

    // Check idempotency header
    const idempotencyKey = (req.headers['idempotency-key'] as string | undefined)?.trim();
    const reqBodyStr = JSON.stringify(req.body || {});
    const reqHash = crypto
      .createHash('sha256')
      .update(`${req.method}:${req.baseUrl + req.path}:${reqBodyStr}`)
      .digest('hex');

    if (idempotencyKey) {
      const cached = await db('idempotency_keys')
        .where({ user_id: callerId, key_value: idempotencyKey })
        .first();

      if (cached && new Date(cached.expires_at) > new Date()) {
        if (cached.request_hash !== reqHash) {
          throw new ConflictError('Idempotency key was previously used with a different request payload');
        }
        if (cached.response_status) {
          const respBody = typeof cached.response_body === 'string'
            ? JSON.parse(cached.response_body)
            : cached.response_body;
          return res.status(cached.response_status).json(respBody);
        }
      }
    }

    const expenseId = ulid();
    const now = new Date();

    const expenseRecord = {
      id: expenseId,
      ledgerId,
      title: body.title,
      totalPaise: body.totalPaise,
      category: body.category,
      splitType: body.splitType,
      expenseDate: body.expenseDate,
      note: body.note || null,
      payers: body.payers,
      participants: body.participants,
      splits,
      createdBy: callerId,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
      deletedAt: null,
      deletedBy: null,
    };

    // ATOMIC TRANSACTION: Write expense, payers, splits, activity_log, and idempotency key
    await db.transaction(async (trx) => {
      await trx('expenses').insert({
        id: expenseId,
        ledger_id: ledgerId,
        title: body.title,
        total_paise: body.totalPaise,
        category: body.category,
        split_type: body.splitType,
        expense_date: body.expenseDate ? new Date(body.expenseDate) : now,
        note: body.note || null,
        created_by: callerId,
        created_at: now,
        updated_at: now,
      });

      await trx('expense_payers').insert(
        body.payers.map((p) => ({
          expense_id: expenseId,
          user_id: p.userId,
          paid_paise: p.paidPaise,
        }))
      );

      await trx('expense_splits').insert(
        splits.map((s) => {
          const part = body.participants.find((p) => p.userId === s.userId);
          return {
            expense_id: expenseId,
            user_id: s.userId,
            owed_paise: s.owedPaise,
            split_value: part?.splitValue ?? 1,
            included: s.included !== false ? 1 : 0,
          };
        })
      );


      await trx('activity_log').insert({
        ledger_id: ledgerId,
        actor_user_id: callerId,
        action: 'EXPENSE_CREATED',
        entity_type: 'expense',
        entity_id: expenseId,
        payload: JSON.stringify({
          title: body.title,
          totalPaise: body.totalPaise,
        }),
        created_at: now,
      });

      if (idempotencyKey) {
        await trx('idempotency_keys')
          .insert({
            user_id: callerId,
            key_value: idempotencyKey,
            request_hash: reqHash,
            resource_type: 'expense',
            resource_id: expenseId,
            response_status: 201,
            response_body: JSON.stringify({ data: expenseRecord }),
            created_at: now,
            expires_at: new Date(now.getTime() + 24 * 60 * 60 * 1000),
          })
          .onConflict(['user_id', 'key_value'])
          .merge({
            request_hash: reqHash,
            resource_id: expenseId,
            response_status: 201,
            response_body: JSON.stringify({ data: expenseRecord }),
            expires_at: new Date(now.getTime() + 24 * 60 * 60 * 1000),
          });
      }
    });

    // Notify participants asynchronously
    for (const split of splits) {
      if (split.userId !== callerId && split.owedPaise > 0) {
        notificationsStore.create({
          userId: split.userId,
          type: 'EXPENSE_ADDED',
          payload: {
            expenseId: expenseRecord.id,
            ledgerId,
            title: body.title,
            totalPaise: body.totalPaise,
            owedPaise: split.owedPaise,
            createdBy: callerId,
          },
        });
      }
    }

    res.status(201).json({
      data: expenseRecord,
    });
  } catch (err) {
    next(err);
  }
});

// List Expenses for a Ledger
ledgersRouter.get('/ledgers/:id/expenses', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const ledgerId = req.params.id;
    await assertLedgerMember(ledgerId, callerId);

    const expenseRows = await db('expenses')
      .where({ ledger_id: ledgerId })
      .whereNull('deleted_at')
      .orderBy('created_at', 'desc');

    const expenseIds = expenseRows.map((e) => e.id);
    const payerRows = expenseIds.length > 0
      ? await db('expense_payers').whereIn('expense_id', expenseIds)
      : [];
    const splitRows = expenseIds.length > 0
      ? await db('expense_splits').whereIn('expense_id', expenseIds)
      : [];

    const payersByExpense = new Map<string, any[]>();
    for (const p of payerRows) {
      const list = payersByExpense.get(p.expense_id) || [];
      list.push({ userId: p.user_id, paidPaise: Number(p.paid_paise) });
      payersByExpense.set(p.expense_id, list);
    }

    const splitsByExpense = new Map<string, any[]>();
    for (const s of splitRows) {
      const list = splitsByExpense.get(s.expense_id) || [];
      list.push({
        userId: s.user_id,
        owedPaise: Number(s.owed_paise),
        splitValue: s.split_value,
        included: Boolean(s.included),
      });
      splitsByExpense.set(s.expense_id, list);
    }

    const activeExpenses = expenseRows.map((e) => {
      const payers = payersByExpense.get(e.id) || [];
      const splits = splitsByExpense.get(e.id) || [];
      const participants = splits.map((s) => ({
        userId: s.userId,
        included: s.included,
        splitValue: s.splitValue,
      }));

      return {
        id: e.id,
        ledgerId: e.ledger_id,
        title: e.title,
        totalPaise: Number(e.total_paise),
        category: e.category,
        splitType: e.split_type,
        expenseDate: e.expense_date instanceof Date
          ? e.expense_date.toISOString().slice(0, 10)
          : String(e.expense_date),
        note: e.note || null,
        createdBy: e.created_by,
        createdAt: e.created_at instanceof Date ? e.created_at.toISOString() : String(e.created_at),
        updatedAt: e.updated_at instanceof Date ? e.updated_at.toISOString() : String(e.updated_at),
        payers,
        participants,
        splits,
        isDisputed: false,
      };
    });

    res.json({
      data: activeExpenses,
    });
  } catch (err) {
    next(err);
  }
});

// Get Expense Detail (receipt-style)
ledgersRouter.get('/expenses/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const expenseId = req.params.id;
    const exp = await db('expenses').where({ id: expenseId }).first();
    if (!exp) {
      throw new NotFoundError(`Expense ${expenseId} not found`);
    }

    await assertLedgerMember(exp.ledger_id, callerId);

    const payers = await db('expense_payers').where({ expense_id: expenseId });
    const splits = await db('expense_splits').where({ expense_id: expenseId });
    const activities = await db('activity_log')
      .where({ entity_type: 'expense', entity_id: expenseId })
      .orderBy('created_at', 'desc');

    res.json({
      data: {
        id: exp.id,
        ledgerId: exp.ledger_id,
        title: exp.title,
        totalPaise: Number(exp.total_paise),
        category: exp.category,
        splitType: exp.split_type,
        expenseDate: exp.expense_date instanceof Date ? exp.expense_date.toISOString().slice(0, 10) : String(exp.expense_date),
        note: exp.note || null,
        createdBy: exp.created_by,
        createdAt: exp.created_at instanceof Date ? exp.created_at.toISOString() : String(exp.created_at),
        updatedAt: exp.updated_at instanceof Date ? exp.updated_at.toISOString() : String(exp.updated_at),
        deletedAt: exp.deleted_at ? (exp.deleted_at instanceof Date ? exp.deleted_at.toISOString() : String(exp.deleted_at)) : null,
        deletedBy: exp.deleted_by || null,
        payers: payers.map((p) => ({ userId: p.user_id, paidPaise: Number(p.paid_paise) })),
        splits: splits.map((s) => ({
          userId: s.user_id,
          owedPaise: Number(s.owed_paise),
          splitValue: s.split_value,
          included: Boolean(s.included),
        })),
        isDisputed: false,
        disputes: [],
        activityLog: activities,
      },
    });
  } catch (err) {
    next(err);
  }
});

// Edit Expense
ledgersRouter.patch('/expenses/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const expenseId = req.params.id;
    const expense = await db('expenses').where({ id: expenseId }).first();
    if (!expense) {
      throw new NotFoundError(`Expense ${expenseId} not found`);
    }

    await assertLedgerMember(expense.ledger_id, callerId);

    if (expense.deleted_at) {
      throw new ValidationError('Cannot edit a deleted expense');
    }

    const body = updateExpenseSchema.parse(req.body);

    const oldPayers = await db('expense_payers').where({ expense_id: expenseId });
    const oldSplits = await db('expense_splits').where({ expense_id: expenseId });

    const totalPaise = body.totalPaise !== undefined ? body.totalPaise : Number(expense.total_paise);
    const splitType = body.splitType !== undefined ? body.splitType : expense.split_type;
    const payers = body.payers !== undefined ? body.payers : oldPayers.map((p) => ({ userId: p.user_id, paidPaise: Number(p.paid_paise) }));
    const participants = body.participants !== undefined
      ? body.participants
      : oldSplits.map((s) => ({ userId: s.user_id, included: Boolean(s.included), splitValue: s.split_value }));

    if (body.totalPaise !== undefined || body.payers !== undefined || body.participants !== undefined || body.splitType !== undefined) {
      const sumPaid = payers.reduce((sum: number, p: any) => sum + p.paidPaise, 0);
      if (sumPaid !== totalPaise) {
        throw new ValidationError(`Sum of payer amounts (${sumPaid} paise) does not equal expense total (${totalPaise} paise)`);
      }

      const memberIds = await getLedgerMemberIds(expense.ledger_id);
      const memberSet = new Set(memberIds);

      const editPayerUserIds = new Set<string>();
      for (const p of payers) {
        if (editPayerUserIds.has(p.userId)) {
          throw new ValidationError(`Duplicate payer ${p.userId} in expense payers`);
        }
        editPayerUserIds.add(p.userId);
        if (!memberSet.has(p.userId)) {
          throw new ForbiddenError(`Payer ${p.userId} is not a member of ledger ${expense.ledger_id}`);
        }
      }

      for (const part of participants) {
        if (!memberSet.has(part.userId)) {
          throw new ForbiddenError(`Participant ${part.userId} is not a member of ledger ${expense.ledger_id}`);
        }
        if (!part.included && editPayerUserIds.has(part.userId)) {
          throw new ValidationError(`Excluded member ${part.userId} cannot be a payer`);
        }
      }
    }

    const newSplits = calculateSplits(totalPaise, splitType, participants);
    const now = new Date();

    await db.transaction(async (trx) => {
      await trx('expenses')
        .where({ id: expenseId })
        .update({
          title: body.title !== undefined ? body.title : expense.title,
          category: body.category !== undefined ? body.category : expense.category,
          total_paise: totalPaise,
          split_type: splitType,
          expense_date: body.expenseDate ? new Date(body.expenseDate) : expense.expense_date,
          note: body.note !== undefined ? body.note : expense.note,
          updated_at: now,
        });

      await trx('expense_payers').where({ expense_id: expenseId }).delete();
      await trx('expense_payers').insert(
        payers.map((p: any) => ({
          expense_id: expenseId,
          user_id: p.userId,
          paid_paise: p.paidPaise,
        }))
      );

      await trx('expense_splits').where({ expense_id: expenseId }).delete();
      await trx('expense_splits').insert(
        newSplits.map((s: any) => {
          const part = participants.find((p: any) => p.userId === s.userId);
          return {
            expense_id: expenseId,
            user_id: s.userId,
            owed_paise: s.owedPaise,
            split_value: part?.splitValue ?? 1,
            included: s.included !== false ? 1 : 0,
          };
        })
      );


      await trx('activity_log').insert({
        ledger_id: expense.ledger_id,
        actor_user_id: callerId,
        action: 'EXPENSE_EDITED',
        entity_type: 'expense',
        entity_id: expenseId,
        payload: JSON.stringify({
          before: { title: expense.title, totalPaise: Number(expense.total_paise) },
          after: { title: body.title || expense.title, totalPaise },
        }),
        created_at: now,
      });
    });

    res.json({
      data: {
        id: expenseId,
        ledgerId: expense.ledger_id,
        title: body.title !== undefined ? body.title : expense.title,
        totalPaise,
        category: body.category !== undefined ? body.category : expense.category,
        splitType,
        expenseDate: body.expenseDate || expense.expense_date,
        note: body.note !== undefined ? body.note : expense.note,
        payers,
        participants,
        splits: newSplits,
        updatedAt: now.toISOString(),
      },
    });
  } catch (err) {
    next(err);
  }
});

// Delete Expense (Soft delete)
ledgersRouter.delete('/expenses/:id', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const expenseId = req.params.id;
    const expense = await db('expenses').where({ id: expenseId }).first();
    if (!expense) {
      throw new NotFoundError(`Expense ${expenseId} not found`);
    }

    await assertLedgerMember(expense.ledger_id, callerId);

    const now = new Date();
    await db.transaction(async (trx) => {
      await trx('expenses')
        .where({ id: expenseId })
        .update({
          deleted_at: now,
          deleted_by: callerId,
        });

      await trx('activity_log').insert({
        ledger_id: expense.ledger_id,
        actor_user_id: callerId,
        action: 'EXPENSE_DELETED',
        entity_type: 'expense',
        entity_id: expenseId,
        payload: JSON.stringify({
          title: expense.title,
          totalPaise: Number(expense.total_paise),
        }),
        created_at: now,
      });
    });

    res.json({
      success: true,
      message: 'Expense deleted successfully',
    });
  } catch (err) {
    next(err);
  }
});

// Dispute Expense
ledgersRouter.post('/expenses/:id/dispute', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const expenseId = req.params.id;
    const expense = await db('expenses').where({ id: expenseId }).first();
    if (!expense) {
      throw new NotFoundError(`Expense ${expenseId} not found`);
    }

    await assertLedgerMember(expense.ledger_id, callerId);

    const dispute = activityStore.createDispute(expense.id, callerId);

    await db('activity_log').insert({
      ledger_id: expense.ledger_id,
      actor_user_id: callerId,
      action: 'EXPENSE_DISPUTED',
      entity_type: 'expense',
      entity_id: expense.id,
      created_at: new Date(),
    });

    // Notify creator
    if (expense.created_by !== callerId) {
      notificationsStore.create({
        userId: expense.created_by,
        type: 'EXPENSE_DISPUTED',
        payload: {
          expenseId: expense.id,
          ledgerId: expense.ledger_id,
          disputedBy: callerId,
          title: expense.title,
        },
      });
    }

    res.status(201).json({
      data: {
        dispute,
        isDisputed: true,
      },
    });
  } catch (err) {
    next(err);
  }
});

// Get Ledger Activity Log
ledgersRouter.get('/ledgers/:id/activity', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const ledgerId = req.params.id;
    await assertLedgerMember(ledgerId, callerId);

    const activities = await db('activity_log')
      .where({ ledger_id: ledgerId })
      .orderBy('created_at', 'desc')
      .limit(100);

    res.json({
      data: activities,
    });
  } catch (err) {
    next(err);
  }
});

// Get Net Balances of Ledger (Authoritative from MySQL)
ledgersRouter.get('/ledgers/:id/balances', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const ledgerId = req.params.id;
    await assertLedgerMember(ledgerId, callerId);

    const balances = await getLedgerBalancesFromDb(ledgerId);

    res.json({
      data: {
        ledgerId,
        balances,
      },
    });
  } catch (err) {
    next(err);
  }
});

// Get Simplified Payment Plan
ledgersRouter.get('/ledgers/:id/simplified', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const ledgerId = req.params.id;
    await assertLedgerMember(ledgerId, callerId);

    const balances = await getLedgerBalancesFromDb(ledgerId);
    const plan = simplifyDebts(balances);

    res.json({
      data: {
        payments: plan,
        count: plan.length,
      },
    });
  } catch (err) {
    next(err);
  }
});

// Get Actual Pairwise Debts
ledgersRouter.get('/ledgers/:id/pairwise', async (req, res, next) => {
  try {
    const callerId = req.user?.id;
    if (!callerId) {
      throw new UnauthenticatedError('Authentication required');
    }

    const ledgerId = req.params.id;
    await assertLedgerMember(ledgerId, callerId);

    const expenseRows = await db('expenses')
      .where({ ledger_id: ledgerId })
      .whereNull('deleted_at');

    const expenseIds = expenseRows.map((e) => e.id);
    const payers = expenseIds.length > 0
      ? await db('expense_payers').whereIn('expense_id', expenseIds)
      : [];
    const splits = expenseIds.length > 0
      ? await db('expense_splits').whereIn('expense_id', expenseIds)
      : [];

    const payersByExpense = new Map<string, any[]>();
    for (const p of payers) {
      const list = payersByExpense.get(p.expense_id) || [];
      list.push({ userId: p.user_id, paidPaise: Number(p.paid_paise) });
      payersByExpense.set(p.expense_id, list);
    }

    const splitsByExpense = new Map<string, any[]>();
    for (const s of splits) {
      const list = splitsByExpense.get(s.expense_id) || [];
      list.push({
        userId: s.user_id,
        owedPaise: Number(s.owed_paise),
        splitValue: s.split_value,
        included: Boolean(s.included),
      });
      splitsByExpense.set(s.expense_id, list);
    }

    const activeExpenses = expenseRows.map((e) => ({
      id: e.id,
      ledgerId: e.ledger_id,
      title: e.title,
      totalPaise: Number(e.total_paise),
      payers: payersByExpense.get(e.id) || [],
      splits: splitsByExpense.get(e.id) || [],
    }));

    const settlementRows = await db('settlements')
      .where({ ledger_id: ledgerId, status: 'CONFIRMED' });

    const settlements = settlementRows.map((s) => ({
      id: s.id,
      fromUserId: s.from_user_id,
      toUserId: s.to_user_id,
      amountPaise: Number(s.amount_paise),
      status: s.status,
    }));

    const debts = calculatePairwiseDebts(activeExpenses, settlements);

    res.json({
      data: {
        debts,
      },
    });
  } catch (err) {
    next(err);
  }
});
