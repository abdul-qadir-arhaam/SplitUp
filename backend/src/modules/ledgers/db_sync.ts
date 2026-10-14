import { db } from '../../db/knex.js';
import { inMemoryLedgers } from './routes.js';
import { inMemorySettlements, Settlement } from '../settlements/store.js';

export async function persistLedgerToDb(ledger: any): Promise<void> {
  try {
    await db('ledgers')
      .insert({
        id: ledger.id,
        type: ledger.type,
        name: ledger.name || null,
        photo_url: ledger.photoUrl || null,
        budget_paise: ledger.budgetPaise || null,
        start_date: ledger.startDate || null,
        end_date: ledger.endDate || null,
        status: ledger.status || 'ACTIVE',
        pair_low_user_id: ledger.pair_low_user_id || null,
        pair_high_user_id: ledger.pair_high_user_id || null,
        created_by: ledger.creatorUserId || ledger.created_by || 'usr_arhaam',
        created_at: new Date(ledger.createdAt || Date.now()),
        updated_at: new Date(ledger.updatedAt || Date.now()),
      })
      .onConflict('id')
      .merge();

    if (Array.isArray(ledger.memberIds)) {
      const memberRows = ledger.memberIds.map((uid: string) => ({
        ledger_id: ledger.id,
        user_id: uid,
        role: ledger.adminUserIds?.includes(uid) ? 'ADMIN' : 'MEMBER',
        joined_at: new Date(),
      }));
      await db('ledger_members').insert(memberRows).onConflict(['ledger_id', 'user_id']).ignore();
    }
  } catch (err) {
    console.error(`[DbSync] Error persisting ledger ${ledger.id} to MySQL:`, err);
  }
}

export async function persistExpenseToDb(expense: any, ledgerId: string): Promise<void> {
  try {
    await db('expenses')
      .insert({
        id: expense.id,
        ledger_id: ledgerId,
        title: expense.title,
        total_paise: expense.totalPaise,
        category: expense.category || 'other',
        split_type: expense.splitType || 'EQUAL',
        expense_date: expense.expenseDate ? new Date(expense.expenseDate) : new Date(),
        note: expense.note || null,
        created_by: expense.createdBy || 'usr_arhaam',
        created_at: new Date(expense.createdAt || Date.now()),
        updated_at: new Date(expense.updatedAt || Date.now()),
        deleted_at: expense.deletedAt ? new Date(expense.deletedAt) : null,
        deleted_by: expense.deletedBy || null,
      })
      .onConflict('id')
      .merge();

    if (Array.isArray(expense.payers)) {
      await db('expense_payers').where({ expense_id: expense.id }).delete();
      const payerRows = expense.payers.map((p: any) => ({
        expense_id: expense.id,
        user_id: p.userId,
        paid_paise: p.paidPaise,
      }));
      if (payerRows.length > 0) {
        await db('expense_payers').insert(payerRows);
      }
    }

    if (Array.isArray(expense.splits)) {
      await db('expense_splits').where({ expense_id: expense.id }).delete();
      const splitRows = expense.splits.map((s: any) => ({
        expense_id: expense.id,
        user_id: s.userId,
        owed_paise: s.owedPaise,
        split_value: s.splitValue ?? 1,
        included: s.included !== false,
      }));
      if (splitRows.length > 0) {
        await db('expense_splits').insert(splitRows);
      }
    }
  } catch (err) {
    console.error(`[DbSync] Error persisting expense ${expense.id} to MySQL:`, err);
  }
}

export async function persistSettlementToDb(s: Settlement): Promise<void> {
  try {
    await db('settlements')
      .insert({
        id: s.id,
        ledger_id: s.ledgerId,
        from_user_id: s.fromUserId,
        to_user_id: s.toUserId,
        amount_paise: s.amountPaise,
        method: s.method || 'CASH',
        status: s.status || 'PENDING',
        offset_id: s.offsetId || null,
        replaced_by_id: s.replacedById || null,
        created_by: s.createdBy || s.fromUserId,
        responded_by: s.respondedBy || null,
        confirmed_on_behalf: s.confirmedOnBehalf ? 1 : 0,
        reminder_count: s.reminderCount || 0,
        last_reminded_at: s.lastRemindedAt ? new Date(s.lastRemindedAt) : null,
        created_at: new Date(s.createdAt),
        responded_at: s.respondedAt ? new Date(s.respondedAt) : null,
      })
      .onConflict('id')
      .merge();
  } catch (err) {
    console.error(`[DbSync] Error persisting settlement ${s.id} to MySQL:`, err);
  }
}

export async function initLedgersStore(): Promise<void> {
  try {
    const ledgerRows = await db('ledgers').select('*');
    const memberRows = await db('ledger_members').whereNull('left_at').select('*');
    const expenseRows = await db('expenses').whereNull('deleted_at').select('*');
    const payerRows = await db('expense_payers').select('*');
    const splitRows = await db('expense_splits').select('*');
    const settlementRows = await db('settlements').select('*');

    // Group members by ledger
    const membersByLedger = new Map<string, string[]>();
    for (const m of memberRows) {
      const list = membersByLedger.get(m.ledger_id) || [];
      list.push(m.user_id);
      membersByLedger.set(m.ledger_id, list);
    }

    // Group payers and splits by expense
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

    // Group expenses by ledger
    const expensesByLedger = new Map<string, any[]>();
    for (const e of expenseRows) {
      const list = expensesByLedger.get(e.ledger_id) || [];
      list.push({
        id: e.id,
        ledgerId: e.ledger_id,
        title: e.title,
        totalPaise: Number(e.total_paise),
        category: e.category,
        splitType: e.split_type,
        expenseDate: e.expense_date instanceof Date ? e.expense_date.toISOString().slice(0, 10) : String(e.expense_date),
        note: e.note || null,
        createdBy: e.created_by,
        createdAt: e.created_at instanceof Date ? e.created_at.toISOString() : String(e.created_at),
        updatedAt: e.updated_at instanceof Date ? e.updated_at.toISOString() : String(e.updated_at),
        payers: payersByExpense.get(e.id) || [],
        splits: splitsByExpense.get(e.id) || [],
      });
      expensesByLedger.set(e.ledger_id, list);
    }

    // Group settlements by ledger
    const settlementsByLedger = new Map<string, any[]>();
    for (const s of settlementRows) {
      const model: Settlement = {
        id: s.id,
        ledgerId: s.ledger_id,
        fromUserId: s.from_user_id,
        toUserId: s.to_user_id,
        amountPaise: Number(s.amount_paise),
        method: s.method,
        status: s.status,
        offsetId: s.offset_id || null,
        replacedById: s.replaced_by_id || null,
        createdBy: s.created_by,
        respondedBy: s.responded_by || null,
        confirmedOnBehalf: Boolean(s.confirmed_on_behalf),
        reminderCount: Number(s.reminder_count || 0),
        lastRemindedAt: s.last_reminded_at ? String(s.last_reminded_at) : null,
        createdAt: s.created_at instanceof Date ? s.created_at.toISOString() : String(s.created_at),
        respondedAt: s.responded_at ? String(s.responded_at) : null,
      };
      inMemorySettlements.set(model.id, model);

      const list = settlementsByLedger.get(s.ledger_id) || [];
      list.push(model);
      settlementsByLedger.set(s.ledger_id, list);
    }

    // Populate inMemoryLedgers
    for (const row of ledgerRows) {
      inMemoryLedgers.set(row.id, {
        id: row.id,
        name: row.name || 'Ledger',
        type: row.type,
        photoUrl: row.photo_url || null,
        creatorUserId: row.created_by,
        adminUserIds: [row.created_by],
        memberIds: membersByLedger.get(row.id) || [row.created_by],
        expenses: expensesByLedger.get(row.id) || [],
        settlements: settlementsByLedger.get(row.id) || [],
        pair_low_user_id: row.pair_low_user_id || undefined,
        pair_high_user_id: row.pair_high_user_id || undefined,
        created_by: row.created_by,
        createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
        updatedAt: row.updated_at instanceof Date ? row.updated_at.toISOString() : String(row.updated_at),
      } as any);
    }

    console.log(`[LedgersStore] Loaded ${ledgerRows.length} ledgers, ${expenseRows.length} expenses, ${settlementRows.length} settlements from Cloud MySQL.`);
  } catch (err) {
    console.error('[LedgersStore] Error initializing from MySQL:', err);
  }
}
