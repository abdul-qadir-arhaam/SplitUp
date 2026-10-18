import { ulid } from 'ulidx';
import { calculateNetBalances, simplifyDebts, calculatePairwiseDebts } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';
import { activityStore } from '../activity/store.js';
import {
  ValidationError,
  NotFoundError,
  ForbiddenError,
} from '../../lib/errors.js';
import { db } from '../../db/knex.js';

export interface TripMemberInfo {
  userId: string;
  name: string;
  phoneE164: string;
  photoUrl?: string | null;
  role: 'CREATOR' | 'MEMBER';
  netPaise: number;
  isAppUser: boolean;
}

export interface BudgetMeter {
  budgetPaise: number;
  totalSpentPaise: number;
  spentPercent: number;
  level: 'UNDER_60' | '60_TO_80' | '80_TO_100' | 'OVER_100';
  statusMessage: string;
  remainingPaise: number;
  remainingPerDayPaise?: number | null;
  daysRemaining?: number | null;
}

function calculateRemainingPerDay(
  startDate?: string | null,
  endDate?: string | null,
  remainingPaise: number = 0
): { remainingPerDayPaise: number | null; daysRemaining: number | null } {
  if (!endDate) return { remainingPerDayPaise: null, daysRemaining: null };

  const end = new Date(endDate);
  const now = new Date();
  const diffMs = end.getTime() - now.getTime();
  const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

  // If today is on or before end date, count at least 1 day
  const days = Math.max(1, diffDays);
  const perDay = Math.max(0, Math.floor(remainingPaise / days));

  return {
    remainingPerDayPaise: perDay,
    daysRemaining: days,
  };
}

export function computeBudgetMeter(
  budgetPaise: number,
  totalSpentPaise: number,
  startDate?: string | null,
  endDate?: string | null
): BudgetMeter {
  const spentPercent = budgetPaise > 0 ? (totalSpentPaise / budgetPaise) * 100 : 0;
  const remainingPaise = budgetPaise - totalSpentPaise;

  let level: 'UNDER_60' | '60_TO_80' | '80_TO_100' | 'OVER_100';
  let statusMessage: string;

function formatRupeesFromPaise(paise: number): string {
  const isNegative = paise < 0;
  const absPaise = Math.abs(paise);
  const rupees = Math.floor(absPaise / 100);
  const rem = absPaise % 100;
  let formatted = rupees.toLocaleString('en-IN');
  if (rem > 0) {
    formatted += '.' + rem.toString().padStart(2, '0');
  }
  return `${isNegative ? '-' : ''}₹${formatted}`;
}

  if (spentPercent < 60) {
    level = 'UNDER_60';
    statusMessage = 'On track';
  } else if (spentPercent < 80) {
    level = '60_TO_80';
    statusMessage = 'Heads up';
  } else if (spentPercent <= 100) {
    level = '80_TO_100';
    statusMessage = `Warning, remaining ${formatRupeesFromPaise(remainingPaise)}`;
  } else {
    level = 'OVER_100';
    const over = totalSpentPaise - budgetPaise;
    statusMessage = `Over budget by ${formatRupeesFromPaise(over)}`;
  }

  const perDayInfo = calculateRemainingPerDay(startDate, endDate, remainingPaise);

  return {
    budgetPaise,
    totalSpentPaise,
    spentPercent: Math.round(spentPercent * 10) / 10,
    level,
    statusMessage,
    remainingPaise,
    remainingPerDayPaise: perDayInfo.remainingPerDayPaise,
    daysRemaining: perDayInfo.daysRemaining,
  };
}

export async function createTrip(params: {
  name: string;
  budgetPaise: number;
  startDate?: string | null;
  endDate?: string | null;
  creatorUserId: string;
  memberUserIds: string[];
  sourceGroupId?: string | null;
  photoUrl?: string | null;
}): Promise<any> {
  const {
    name,
    budgetPaise,
    startDate,
    endDate,
    creatorUserId,
    memberUserIds,
    sourceGroupId,
    photoUrl,
  } = params;

  if (!name || name.trim().length === 0) {
    throw new ValidationError('Trip name is required');
  }

  if (budgetPaise <= 0 || !Number.isInteger(budgetPaise)) {
    throw new ValidationError('Budget must be a positive integer in paise');
  }

  const membersSet = new Set<string>([creatorUserId, ...(memberUserIds || [])]);

  // "Add all members of an existing group" (copies members, no live link)
  if (sourceGroupId) {
    const groupMembers = await db('ledger_members')
      .where({ ledger_id: sourceGroupId })
      .whereNull('left_at')
      .select('user_id');
    for (const gm of groupMembers) {
      membersSet.add(gm.user_id);
    }
  }

  const allMembers = Array.from(membersSet);
  const id = `trp_${ulid()}`;
  const now = new Date();

  // ONE AWAITED TRANSACTION: ledgers + ledger_members + activity_log
  await db.transaction(async (trx) => {
    // Ensure placeholder user rows exist so foreign keys don't fail
    for (const uid of allMembers) {
      const uExists = await trx('users').where({ id: uid }).first();
      if (!uExists) {
        await trx('users').insert({
          id: uid,
          phone_e164: `+9100000${uid.slice(-5)}`,
          name: uid === creatorUserId ? 'Creator' : 'Member',
          is_placeholder: 1,
          created_at: now,
          updated_at: now,
        }).catch(() => {});
      }
    }

    await trx('ledgers').insert({
      id,
      type: 'TRIP',
      name: name.trim(),
      photo_url: photoUrl || null,
      budget_paise: budgetPaise,
      start_date: startDate ? new Date(startDate) : null,
      end_date: endDate ? new Date(endDate) : null,
      status: 'ACTIVE',
      created_by: creatorUserId,
      created_at: now,
      updated_at: now,
    });

    const memberRows = allMembers.map((uid) => ({
      ledger_id: id,
      user_id: uid,
      role: uid === creatorUserId ? 'ADMIN' : 'MEMBER',
      joined_at: now,
    }));
    await trx('ledger_members').insert(memberRows);

    await trx('activity_log').insert({
      ledger_id: id,
      actor_user_id: creatorUserId,
      action: 'LEDGER_CREATED',
      entity_type: 'ledger',
      entity_id: id,
      payload: JSON.stringify({ name: name.trim(), budgetPaise, memberCount: allMembers.length }),
      created_at: now,
    });
  });

  // Notify members (except creator)
  for (const mId of allMembers) {
    if (mId === creatorUserId) continue;
    try {
      await notificationsStore.create({
        userId: mId,
        type: 'ADDED_TO_TRIP' as any,
        payload: {
          tripId: id,
          tripName: name.trim(),
          addedBy: creatorUserId,
          budgetPaise,
        },
      });
    } catch (e) {
      console.error(`[TripsStore] Error notifying member ${mId}:`, e);
    }
  }

  return {
    id,
    name: name.trim(),
    type: 'TRIP' as const,
    budgetPaise,
    startDate: startDate || null,
    endDate: endDate || null,
    status: 'ACTIVE' as const,
    photoUrl: photoUrl || null,
    creatorUserId,
    adminUserIds: [creatorUserId],
    memberIds: allMembers,
    expenses: [],
    settlements: [],
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
  };
}

export async function listUserTrips(userId: string): Promise<{ all: any[]; active: any[]; completed: any[] }> {
  // Query trips where user is an active member
  const ledgerRows = await db('ledgers')
    .join('ledger_members', 'ledgers.id', 'ledger_members.ledger_id')
    .where('ledger_members.user_id', userId)
    .whereNull('ledger_members.left_at')
    .where('ledgers.type', 'TRIP')
    .select('ledgers.*')
    .orderBy('ledgers.created_at', 'desc');

  const userTrips: any[] = [];

  for (const ledger of ledgerRows) {
    const tripId = ledger.id;

    // Get all active members for this trip
    const memberRows = await db('ledger_members')
      .where({ ledger_id: tripId })
      .whereNull('left_at')
      .select('user_id');
    const memberIds = memberRows.map((m) => m.user_id);

    // Get active expenses
    const expenseRows = await db('expenses')
      .where({ ledger_id: tripId })
      .whereNull('deleted_at');

    const totalSpentPaise = expenseRows.reduce(
      (sum: number, exp: any) => sum + Number(exp.total_paise),
      0
    );

    // Get expense payers and splits for net calculation
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

    const formattedExpenses = expenseRows.map((e) => ({
      id: e.id,
      ledgerId: e.ledger_id,
      title: e.title,
      totalPaise: Number(e.total_paise),
      payers: payersByExpense.get(e.id) || [],
      splits: splitsByExpense.get(e.id) || [],
    }));

    const settlementRows = await db('settlements')
      .where({ ledger_id: tripId, status: 'CONFIRMED' });

    const formattedSettlements = settlementRows.map((s) => ({
      id: s.id,
      fromUserId: s.from_user_id,
      toUserId: s.to_user_id,
      amountPaise: Number(s.amount_paise),
      status: s.status,
    }));

    const netResult = calculateNetBalances(
      memberIds,
      formattedExpenses,
      formattedSettlements
    );

    const budgetPaise = Number(ledger.budget_paise) || 0;
    const startDateStr = ledger.start_date instanceof Date
      ? ledger.start_date.toISOString().slice(0, 10)
      : (ledger.start_date ? String(ledger.start_date) : null);
    const endDateStr = ledger.end_date instanceof Date
      ? ledger.end_date.toISOString().slice(0, 10)
      : (ledger.end_date ? String(ledger.end_date) : null);

    const budgetMeter = computeBudgetMeter(
      budgetPaise,
      totalSpentPaise,
      startDateStr,
      endDateStr
    );

    userTrips.push({
      id: ledger.id,
      name: ledger.name,
      photoUrl: ledger.photo_url || null,
      budgetPaise,
      startDate: startDateStr,
      endDate: endDateStr,
      status: ledger.status || 'ACTIVE',
      isCompleted: ledger.status === 'COMPLETED',
      creatorUserId: ledger.created_by,
      isAdmin: ledger.created_by === userId,
      membersCount: memberIds.length,
      myNetPaise: netResult.balances[userId] || 0,
      totalSpentPaise,
      budgetMeter,
      createdAt: ledger.created_at instanceof Date ? ledger.created_at.toISOString() : String(ledger.created_at),
    });
  }

  return {
    all: userTrips,
    active: userTrips.filter((t) => !t.isCompleted),
    completed: userTrips.filter((t) => t.isCompleted),
  };
}

export async function getTripDetails(tripId: string, callerUserId: string): Promise<any> {
  const ledger = await db('ledgers').where({ id: tripId, type: 'TRIP' }).first();
  if (!ledger) {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  // Requirement: GET /v1/trips/:id must check membership (403 for non-members)
  const membership = await db('ledger_members')
    .where({ ledger_id: tripId, user_id: callerUserId })
    .whereNull('left_at')
    .first();
  if (!membership) {
    throw new ForbiddenError(`User is not a member of trip ${tripId}`);
  }

  const memberRows = await db('ledger_members')
    .leftJoin('users', 'ledger_members.user_id', 'users.id')
    .where({ 'ledger_members.ledger_id': tripId })
    .whereNull('ledger_members.left_at')
    .select(
      'ledger_members.user_id',
      'ledger_members.role',
      'users.name',
      'users.phone_e164',
      'users.photo_url',
      'users.is_placeholder'
    );

  const memberIds = memberRows.map((m) => m.user_id);

  // Active expenses
  const expenseRows = await db('expenses')
    .where({ ledger_id: tripId })
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

  const activeExpenses = expenseRows.map((e) => ({
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
    payers: payersByExpense.get(e.id) || [],
    splits: splitsByExpense.get(e.id) || [],
  }));

  const settlementRows = await db('settlements').where({ ledger_id: tripId });
  const confirmedSettlements = settlementRows
    .filter((s) => s.status === 'CONFIRMED')
    .map((s) => ({
      id: s.id,
      fromUserId: s.from_user_id,
      toUserId: s.to_user_id,
      amountPaise: Number(s.amount_paise),
      status: s.status,
    }));

  const netResult = calculateNetBalances(
    memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const totalSpentPaise = activeExpenses.reduce(
    (sum: number, exp: any) => sum + exp.totalPaise,
    0
  );

  const membersInfo: TripMemberInfo[] = memberRows.map((m) => ({
    userId: m.user_id,
    name: m.name || m.user_id,
    phoneE164: m.phone_e164 || '',
    photoUrl: m.photo_url || null,
    role: ledger.created_by === m.user_id ? 'CREATOR' : 'MEMBER',
    netPaise: netResult.balances[m.user_id] || 0,
    isAppUser: !m.is_placeholder,
  }));

  const budgetPaise = Number(ledger.budget_paise) || 0;
  const startDateStr = ledger.start_date instanceof Date
    ? ledger.start_date.toISOString().slice(0, 10)
    : (ledger.start_date ? String(ledger.start_date) : null);
  const endDateStr = ledger.end_date instanceof Date
    ? ledger.end_date.toISOString().slice(0, 10)
    : (ledger.end_date ? String(ledger.end_date) : null);

  const budgetMeter = computeBudgetMeter(
    budgetPaise,
    totalSpentPaise,
    startDateStr,
    endDateStr
  );

  const formattedSettlements = settlementRows.map((s) => ({
    id: s.id,
    ledgerId: s.ledger_id,
    fromUserId: s.from_user_id,
    toUserId: s.to_user_id,
    amountPaise: Number(s.amount_paise),
    status: s.status,
    method: s.method,
    createdAt: s.created_at instanceof Date ? s.created_at.toISOString() : String(s.created_at),
    updatedAt: s.updated_at instanceof Date ? s.updated_at.toISOString() : String(s.updated_at),
  }));

  return {
    id: ledger.id,
    name: ledger.name,
    photoUrl: ledger.photo_url || null,
    budgetPaise,
    startDate: startDateStr,
    endDate: endDateStr,
    status: ledger.status || 'ACTIVE',
    isCompleted: ledger.status === 'COMPLETED',
    creatorUserId: ledger.created_by,
    isAdmin: ledger.created_by === callerUserId || membership.role === 'ADMIN',
    memberIds,
    members: membersInfo,
    myNetPaise: netResult.balances[callerUserId] || 0,
    totalSpentPaise,
    budgetMeter,
    expenses: activeExpenses,
    settlements: formattedSettlements,
    createdAt: ledger.created_at instanceof Date ? ledger.created_at.toISOString() : String(ledger.created_at),
    updatedAt: ledger.updated_at instanceof Date ? ledger.updated_at.toISOString() : String(ledger.updated_at),
  };
}

export async function updateTripBudget(
  tripId: string,
  actorUserId: string,
  newBudgetPaise: number
): Promise<any> {
  if (newBudgetPaise <= 0 || !Number.isInteger(newBudgetPaise)) {
    throw new ValidationError('Budget must be a positive integer in paise');
  }

  const ledger = await db('ledgers').where({ id: tripId, type: 'TRIP' }).first();
  if (!ledger) {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const membership = await db('ledger_members')
    .where({ ledger_id: tripId, user_id: actorUserId })
    .whereNull('left_at')
    .first();

  const isCreator = ledger.created_by === actorUserId;
  const isAdmin = membership && (membership.role === 'ADMIN' || membership.role === 'CREATOR');

  if (!isCreator && !isAdmin) {
    throw new ForbiddenError('Only the trip creator or admin can update the budget');
  }

  const oldBudgetPaise = Number(ledger.budget_paise) || 0;
  const now = new Date();

  await db.transaction(async (trx) => {
    await trx('ledgers')
      .where({ id: tripId })
      .update({
        budget_paise: newBudgetPaise,
        updated_at: now,
      });

    await trx('activity_log').insert({
      ledger_id: tripId,
      actor_user_id: actorUserId,
      action: 'BUDGET_CHANGED',
      entity_type: 'ledger',
      entity_id: tripId,
      payload: JSON.stringify({ oldBudgetPaise, newBudgetPaise }),
      created_at: now,
    });
  });

  // Re-check budget thresholds
  await checkTripBudgetThresholds(tripId);

  return getTripDetails(tripId, actorUserId);
}

export async function updateTrip(
  tripId: string,
  actorUserId: string,
  data: {
    name?: string;
    photoUrl?: string | null;
    startDate?: string | null;
    endDate?: string | null;
  }
): Promise<any> {
  const ledger = await db('ledgers').where({ id: tripId, type: 'TRIP' }).first();
  if (!ledger) {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const membership = await db('ledger_members')
    .where({ ledger_id: tripId, user_id: actorUserId })
    .whereNull('left_at')
    .first();

  const isCreator = ledger.created_by === actorUserId;
  const isAdmin = membership && (membership.role === 'ADMIN' || membership.role === 'CREATOR');

  if (!isCreator && !isAdmin) {
    throw new ForbiddenError('Only the trip creator or admin can update trip details');
  }

  const updates: Record<string, any> = {
    updated_at: new Date(),
  };

  if (data.name !== undefined) {
    if (data.name.trim().length === 0) {
      throw new ValidationError('Trip name cannot be empty');
    }
    updates.name = data.name.trim();
  }
  if (data.photoUrl !== undefined) updates.photo_url = data.photoUrl;
  if (data.startDate !== undefined) updates.start_date = data.startDate ? new Date(data.startDate) : null;
  if (data.endDate !== undefined) updates.end_date = data.endDate ? new Date(data.endDate) : null;

  await db.transaction(async (trx) => {
    await trx('ledgers').where({ id: tripId }).update(updates);

    if (data.name !== undefined && data.name.trim() !== ledger.name) {
      await trx('activity_log').insert({
        ledger_id: tripId,
        actor_user_id: actorUserId,
        action: 'LEDGER_RENAMED',
        entity_type: 'ledger',
        entity_id: tripId,
        payload: JSON.stringify({ oldName: ledger.name, newName: data.name.trim() }),
        created_at: updates.updated_at,
      });
    }
  });

  return getTripDetails(tripId, actorUserId);
}

export async function completeTrip(tripId: string, actorUserId: string): Promise<any> {
  const ledger = await db('ledgers').where({ id: tripId, type: 'TRIP' }).first();
  if (!ledger) {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const membership = await db('ledger_members')
    .where({ ledger_id: tripId, user_id: actorUserId })
    .whereNull('left_at')
    .first();

  const isCreator = ledger.created_by === actorUserId;
  const isAdmin = membership && (membership.role === 'ADMIN' || membership.role === 'CREATOR');

  if (!isCreator && !isAdmin) {
    throw new ForbiddenError('Only the trip creator or admin can mark a trip as completed');
  }

  const now = new Date();
  await db.transaction(async (trx) => {
    await trx('ledgers')
      .where({ id: tripId })
      .update({
        status: 'COMPLETED',
        updated_at: now,
      });

    await trx('activity_log').insert({
      ledger_id: tripId,
      actor_user_id: actorUserId,
      action: 'TRIP_COMPLETED',
      entity_type: 'ledger',
      entity_id: tripId,
      created_at: now,
    });
  });

  return getTripDetails(tripId, actorUserId);
}

export async function checkTripBudgetThresholds(tripId: string): Promise<void> {
  const ledger = await db('ledgers').where({ id: tripId, type: 'TRIP' }).first();
  if (!ledger) return;

  const budgetPaise = Number(ledger.budget_paise) || 0;
  if (budgetPaise <= 0) return;

  const expenseRows = await db('expenses')
    .where({ ledger_id: tripId })
    .whereNull('deleted_at');

  const totalSpentPaise = expenseRows.reduce(
    (sum: number, exp: any) => sum + Number(exp.total_paise),
    0
  );

  const spentPercent = (totalSpentPaise / budgetPaise) * 100;

  // Check activity_log to see what thresholds were already notified
  const existingAlerts = await db('activity_log')
    .where({ ledger_id: tripId })
    .whereIn('action', ['TRIP_BUDGET_WARNING', 'TRIP_BUDGET_EXCEEDED'])
    .select('action');

  const alertedWarning = existingAlerts.some((a) => a.action === 'TRIP_BUDGET_WARNING');
  const alertedExceeded = existingAlerts.some((a) => a.action === 'TRIP_BUDGET_EXCEEDED');

  const memberRows = await db('ledger_members')
    .where({ ledger_id: tripId })
    .whereNull('left_at')
    .select('user_id');
  const memberIds = memberRows.map((m) => m.user_id);

  // 80% threshold warning
  if (spentPercent >= 80 && !alertedWarning) {
    await db('activity_log').insert({
      ledger_id: tripId,
      actor_user_id: ledger.created_by,
      action: 'TRIP_BUDGET_WARNING',
      entity_type: 'ledger',
      entity_id: tripId,
      payload: JSON.stringify({ spentPercent, totalSpentPaise, budgetPaise }),
      created_at: new Date(),
    });

    for (const memberId of memberIds) {
      await notificationsStore.create({
        userId: memberId,
        type: 'TRIP_BUDGET_WARNING' as any,
        payload: {
          tripId,
          tripName: ledger.name,
          percent: 80,
          spentPaise: totalSpentPaise,
          budgetPaise,
        },
      }).catch(() => {});
    }
  }

  // 100% threshold exceeded
  if (spentPercent >= 100 && !alertedExceeded) {
    await db('activity_log').insert({
      ledger_id: tripId,
      actor_user_id: ledger.created_by,
      action: 'TRIP_BUDGET_EXCEEDED',
      entity_type: 'ledger',
      entity_id: tripId,
      payload: JSON.stringify({ spentPercent, totalSpentPaise, budgetPaise, overPaise: totalSpentPaise - budgetPaise }),
      created_at: new Date(),
    });

    for (const memberId of memberIds) {
      await notificationsStore.create({
        userId: memberId,
        type: 'TRIP_BUDGET_EXCEEDED' as any,
        payload: {
          tripId,
          tripName: ledger.name,
          percent: 100,
          spentPaise: totalSpentPaise,
          budgetPaise,
          overPaise: totalSpentPaise - budgetPaise,
        },
      }).catch(() => {});
    }
  }
}

export async function getTripDashboard(tripId: string, callerUserId: string): Promise<any> {
  const details = await getTripDetails(tripId, callerUserId);
  const activeExpenses = details.expenses;

  // 1. Categories
  const categoryTotals: Record<string, number> = {};
  for (const exp of activeExpenses) {
    const cat = exp.category || 'other';
    categoryTotals[cat] = (categoryTotals[cat] || 0) + exp.totalPaise;
  }
  const categories = Object.entries(categoryTotals).map(([category, totalPaise]) => ({
    category,
    totalPaise,
    percentage:
      details.totalSpentPaise > 0
        ? Math.round((totalPaise / details.totalSpentPaise) * 100)
        : 0,
  }));

  // 2. Member paid vs share
  const memberPaidShare: Record<string, { paid: number; share: number }> = {};
  for (const mem of details.members) {
    memberPaidShare[mem.userId] = { paid: 0, share: 0 };
  }
  for (const exp of activeExpenses) {
    for (const p of exp.payers) {
      if (memberPaidShare[p.userId]) {
        memberPaidShare[p.userId].paid += p.paidPaise;
      }
    }
    for (const s of exp.splits) {
      if (s.included && memberPaidShare[s.userId]) {
        memberPaidShare[s.userId].share += s.owedPaise;
      }
    }
  }
  const memberBars = details.members.map((mem: any) => ({
    userId: mem.userId,
    name: mem.name,
    paidPaise: memberPaidShare[mem.userId]?.paid || 0,
    sharePaise: memberPaidShare[mem.userId]?.share || 0,
  }));

  // 3. Daily spending bars
  const spendingByDay: Record<string, number> = {};
  for (const exp of activeExpenses) {
    const day = exp.expenseDate || exp.createdAt?.split('T')[0] || 'Today';
    spendingByDay[day] = (spendingByDay[day] || 0) + exp.totalPaise;
  }
  const dailySpending = Object.entries(spendingByDay)
    .sort(([dateA], [dateB]) => dateA.localeCompare(dateB))
    .map(([date, totalPaise]) => ({
      date,
      totalPaise,
    }));

  return {
    tripId,
    budgetMeter: details.budgetMeter,
    categories,
    categoryBreakdown: categories,
    memberBars,
    memberMetrics: memberBars,
    dailySpending,
    spendingByDay: dailySpending,
  };
}

export async function getTripGraph(
  tripId: string,
  callerUserId: string,
  mode: 'simplified' | 'actual' = 'simplified'
): Promise<any> {
  const details = await getTripDetails(tripId, callerUserId);
  const activeExpenses = details.expenses;
  const confirmedSettlements = details.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );
  const pendingSettlements = details.settlements.filter(
    (s: any) => s.status === 'PENDING'
  );

  const netResult = calculateNetBalances(
    details.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const nodes = details.members.map((mem: any) => ({
    userId: mem.userId,
    name: mem.name,
    netPaise: netResult.balances[mem.userId] || 0,
  }));

  let links: any[] = [];
  if (mode === 'simplified') {
    const plan = simplifyDebts(netResult.balances);
    links = plan.map((p) => ({
      fromUserId: p.from,
      toUserId: p.to,
      amountPaise: p.amountPaise,
      isPending: false,
    }));
  } else {
    const debts = calculatePairwiseDebts(activeExpenses, confirmedSettlements);
    links = debts.map((d) => ({
      fromUserId: d.from,
      toUserId: d.to,
      amountPaise: d.amountPaise,
      isPending: false,
    }));
  }

  for (const s of pendingSettlements) {
    links.push({
      settlementId: s.id,
      fromUserId: s.fromUserId,
      toUserId: s.toUserId,
      amountPaise: s.amountPaise,
      isPending: true,
      method: s.method,
    });
  }

  return {
    tripId,
    mode,
    nodes,
    links,
  };
}
