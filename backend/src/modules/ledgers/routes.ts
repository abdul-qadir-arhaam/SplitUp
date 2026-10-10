import { Router } from 'express';
import { z } from 'zod';
import { ulid } from 'ulidx';
import { calculateSplits, calculateNetBalances, simplifyDebts, calculatePairwiseDebts } from '../balances/index.js';
import { assertMember } from '../../middleware/auth.js';
import { ValidationError, NotFoundError, ForbiddenError } from '../../lib/errors.js';
import { activityStore } from '../activity/store.js';
import { notificationsStore } from '../notifications/store.js';

export const ledgersRouter = Router();

// In-memory data store for Phase 1 endpoints
interface StoredLedger {
  id: string;
  name: string;
  type: 'INDIVIDUAL' | 'GROUP' | 'TRIP';
  memberIds: string[];
  expenses: any[];
  settlements: any[];
}

export const inMemoryLedgers = new Map<string, StoredLedger>();

// Initialize default test ledger
inMemoryLedgers.set('ledger_test_1', {
  id: 'ledger_test_1',
  name: 'Friday Gang',
  type: 'GROUP',
  memberIds: ['usr_arhaam', 'usr_rahul', 'usr_priya', 'usr_amit', 'usr_sneha'],
  expenses: [],
  settlements: [],
});

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

function findExpenseAndLedger(expenseId: string): { expense: any; ledger: StoredLedger } | null {
  for (const ledger of inMemoryLedgers.values()) {
    const exp = ledger.expenses.find((e: any) => e.id === expenseId);
    if (exp) {
      return { expense: exp, ledger };
    }
  }
  return null;
}

// Create Expense in Ledger
ledgersRouter.post('/ledgers/:id/expenses', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

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
    for (const payer of body.payers) {
      assertMember(ledger.memberIds, payer.userId);
    }
    for (const part of body.participants) {
      assertMember(ledger.memberIds, part.userId);
      if (!part.included) {
        const isPayer = body.payers.some((p) => p.userId === part.userId);
        if (isPayer) {
          throw new ValidationError(`Excluded member ${part.userId} cannot be a payer for this expense`);
        }
      }
    }

    // Compute splits with deterministic rounding
    const splits = calculateSplits(body.totalPaise, body.splitType, body.participants);

    const expenseRecord = {
      id: ulid(),
      ledgerId,
      title: body.title,
      totalPaise: body.totalPaise,
      category: body.category,
      splitType: body.splitType,
      expenseDate: body.expenseDate,
      note: body.note,
      payers: body.payers,
      participants: body.participants,
      splits,
      createdBy: callerId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      deletedAt: null,
      deletedBy: null,
    };

    ledger.expenses.push(expenseRecord);

    // Activity log
    activityStore.log({
      ledgerId,
      actorUserId: callerId,
      action: 'EXPENSE_CREATED',
      entityType: 'expense',
      entityId: expenseRecord.id,
      payload: {
        title: body.title,
        totalPaise: body.totalPaise,
      },
    });

    if (ledger.type === 'TRIP') {
      import('../trips/store.js').then((m) => {
        m.checkTripBudgetThresholds(ledgerId);
      });
    }

    res.status(201).json({
      data: expenseRecord,
    });
  } catch (err) {
    next(err);
  }
});

// List Expenses for a Ledger
ledgersRouter.get('/ledgers/:id/expenses', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    const activeExpenses = ledger.expenses
      .filter((e: any) => !e.deletedAt)
      .map((e: any) => ({
        ...e,
        isDisputed: activityStore.isExpenseDisputed(e.id),
      }))
      .sort((a: any, b: any) => b.createdAt.localeCompare(a.createdAt));

    res.json({
      data: activeExpenses,
    });
  } catch (err) {
    next(err);
  }
});

// Get Expense Detail (receipt-style)
ledgersRouter.get('/expenses/:id', (req, res, next) => {
  try {
    const match = findExpenseAndLedger(req.params.id);
    if (!match) {
      throw new NotFoundError(`Expense ${req.params.id} not found`);
    }

    const { expense, ledger } = match;
    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    res.json({
      data: {
        ...expense,
        isDisputed: activityStore.isExpenseDisputed(expense.id),
        disputes: activityStore.listDisputesForExpense(expense.id),
        activityLog: activityStore.listForExpense(expense.id),
      },
    });
  } catch (err) {
    next(err);
  }
});

// Edit Expense
ledgersRouter.patch('/expenses/:id', (req, res, next) => {
  try {
    const match = findExpenseAndLedger(req.params.id);
    if (!match) {
      throw new NotFoundError(`Expense ${req.params.id} not found`);
    }

    const { expense, ledger } = match;
    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    if (expense.deletedAt) {
      throw new ValidationError('Cannot edit a deleted expense');
    }

    const body = updateExpenseSchema.parse(req.body);

    const oldValues = {
      title: expense.title,
      totalPaise: expense.totalPaise,
      category: expense.category,
      payers: JSON.parse(JSON.stringify(expense.payers)),
    };

    if (body.title !== undefined) expense.title = body.title;
    if (body.category !== undefined) expense.category = body.category;
    if (body.expenseDate !== undefined) expense.expenseDate = body.expenseDate;
    if (body.note !== undefined) expense.note = body.note;

    // If payers/participants/totals changed, re-evaluate splits
    const totalPaise = body.totalPaise !== undefined ? body.totalPaise : expense.totalPaise;
    const splitType = body.splitType !== undefined ? body.splitType : expense.splitType;
    const payers = body.payers !== undefined ? body.payers : expense.payers;
    const participants = body.participants !== undefined
      ? body.participants
      : (expense.participants || expense.splits.map((s: any) => ({ userId: s.userId, included: s.included, splitValue: s.splitValue })));

    if (body.totalPaise !== undefined || body.payers !== undefined || body.participants !== undefined || body.splitType !== undefined) {
      const sumPaid = payers.reduce((sum: number, p: any) => sum + p.paidPaise, 0);
      if (sumPaid !== totalPaise) {
        throw new ValidationError(`Sum of payer amounts (${sumPaid} paise) does not equal expense total (${totalPaise} paise)`);
      }

      const editPayerUserIds = new Set<string>();
      for (const p of payers) {
        if (editPayerUserIds.has(p.userId)) {
          throw new ValidationError(`Duplicate payer ${p.userId} in expense payers`);
        }
        editPayerUserIds.add(p.userId);
        assertMember(ledger.memberIds, p.userId);
      }

      for (const part of participants) {
        assertMember(ledger.memberIds, part.userId);
        if (!part.included && payers.some((p: any) => p.userId === part.userId)) {
          throw new ValidationError(`Excluded member ${part.userId} cannot be a payer`);
        }
      }

      expense.totalPaise = totalPaise;
      expense.splitType = splitType;
      expense.payers = payers;
      expense.participants = participants;
      expense.splits = calculateSplits(totalPaise, splitType, participants);
    }

    expense.updatedAt = new Date().toISOString();

    activityStore.log({
      ledgerId: ledger.id,
      actorUserId: callerId,
      action: 'EXPENSE_EDITED',
      entityType: 'expense',
      entityId: expense.id,
      payload: {
        before: oldValues,
        after: {
          title: expense.title,
          totalPaise: expense.totalPaise,
          category: expense.category,
          payers: expense.payers,
        },
      },
    });

    res.json({
      data: expense,
    });
  } catch (err) {
    next(err);
  }
});

// Delete Expense (Soft delete)
ledgersRouter.delete('/expenses/:id', (req, res, next) => {
  try {
    const match = findExpenseAndLedger(req.params.id);
    if (!match) {
      throw new NotFoundError(`Expense ${req.params.id} not found`);
    }

    const { expense, ledger } = match;
    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    expense.deletedAt = new Date().toISOString();
    expense.deletedBy = callerId;

    activityStore.log({
      ledgerId: ledger.id,
      actorUserId: callerId,
      action: 'EXPENSE_DELETED',
      entityType: 'expense',
      entityId: expense.id,
      payload: {
        title: expense.title,
        totalPaise: expense.totalPaise,
      },
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
ledgersRouter.post('/expenses/:id/dispute', (req, res, next) => {
  try {
    const match = findExpenseAndLedger(req.params.id);
    if (!match) {
      throw new NotFoundError(`Expense ${req.params.id} not found`);
    }

    const { expense, ledger } = match;
    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    const dispute = activityStore.createDispute(expense.id, callerId);

    activityStore.log({
      ledgerId: ledger.id,
      actorUserId: callerId,
      action: 'EXPENSE_DISPUTED',
      entityType: 'expense',
      entityId: expense.id,
    });

    // Notify creator
    if (expense.createdBy !== callerId) {
      notificationsStore.create({
        userId: expense.createdBy,
        type: 'EXPENSE_DISPUTED',
        payload: {
          expenseId: expense.id,
          ledgerId: ledger.id,
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
ledgersRouter.get('/ledgers/:id/activity', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    const activities = activityStore.listForLedger(ledgerId);
    res.json({
      data: activities,
    });
  } catch (err) {
    next(err);
  }
});

// Get Net Balances of Ledger
ledgersRouter.get('/ledgers/:id/balances', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
    const result = calculateNetBalances(ledger.memberIds, activeExpenses, ledger.settlements);

    res.json({
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// Get Simplified Payment Plan
ledgersRouter.get('/ledgers/:id/simplified', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
    const netResult = calculateNetBalances(ledger.memberIds, activeExpenses, ledger.settlements);
    const plan = simplifyDebts(netResult.balances);

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
ledgersRouter.get('/ledgers/:id/pairwise', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    const callerId = req.user?.id || 'usr_arhaam';
    assertMember(ledger.memberIds, callerId);

    const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
    const debts = calculatePairwiseDebts(activeExpenses, ledger.settlements);

    res.json({
      data: {
        debts,
      },
    });
  } catch (err) {
    next(err);
  }
});
