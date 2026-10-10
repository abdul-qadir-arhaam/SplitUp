import { Router } from 'express';
import { z } from 'zod';
import { ulid } from 'ulidx';
import { calculateSplits, calculateNetBalances, simplifyDebts, calculatePairwiseDebts } from '../balances/index.js';
import { assertMember } from '../../middleware/auth.js';
import { ValidationError, NotFoundError } from '../../lib/errors.js';

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

const createExpenseSchema = z.object({
  title: z.string().min(1).max(120),
  totalPaise: z.number().int().positive(),
  category: z.enum(['food', 'travel', 'stay', 'fuel', 'tickets', 'shopping', 'groceries', 'other']).default('other'),
  splitType: z.enum(['EQUAL', 'EXACT', 'PERCENT', 'SHARES']),
  payers: z.array(
    z.object({
      userId: z.string(),
      paidPaise: z.number().int().positive(),
    })
  ).nonempty(),
  participants: z.array(
    z.object({
      userId: z.string(),
      included: z.boolean(),
      splitValue: z.number().int().optional(),
    })
  ).nonempty(),
  expenseDate: z.string().default(() => new Date().toISOString().split('T')[0]),
  note: z.string().max(500).optional(),
});

// Create Expense in Ledger
ledgersRouter.post('/ledgers/:id/expenses', (req, res, next) => {
  try {
    const ledgerId = req.params.id;
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    // Check membership authorization
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
      splits,
      createdBy: callerId,
      createdAt: new Date().toISOString(),
    };

    ledger.expenses.push(expenseRecord);

    res.status(201).json({
      data: expenseRecord,
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

    const result = calculateNetBalances(ledger.memberIds, ledger.expenses, ledger.settlements);

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

    const netResult = calculateNetBalances(ledger.memberIds, ledger.expenses, ledger.settlements);
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

    const debts = calculatePairwiseDebts(ledger.expenses, ledger.settlements);

    res.json({
      data: {
        debts,
      },
    });
  } catch (err) {
    next(err);
  }
});
