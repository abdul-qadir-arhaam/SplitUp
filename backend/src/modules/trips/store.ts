import { ulid } from 'ulidx';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { inMemoryUsers } from '../users/store.js';
import { calculateNetBalances, simplifyDebts, calculatePairwiseDebts } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';
import { activityStore } from '../activity/store.js';
import {
  ValidationError,
  NotFoundError,
  ForbiddenError,
} from '../../lib/errors.js';
import { persistLedgerToDb } from '../ledgers/db_sync.js';

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

  if (spentPercent < 60) {
    level = 'UNDER_60';
    statusMessage = 'On track';
  } else if (spentPercent < 80) {
    level = '60_TO_80';
    statusMessage = 'Heads up';
  } else if (spentPercent <= 100) {
    level = '80_TO_100';
    statusMessage = `Warning, remaining ₹${(remainingPaise / 100).toFixed(0)}`;
  } else {
    level = 'OVER_100';
    const over = totalSpentPaise - budgetPaise;
    statusMessage = `Over budget by ₹${(over / 100).toFixed(0)}`;
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

export function createTrip(params: {
  name: string;
  budgetPaise: number;
  startDate?: string | null;
  endDate?: string | null;
  creatorUserId: string;
  memberUserIds: string[];
  sourceGroupId?: string | null;
  photoUrl?: string | null;
}): any {
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

  const membersSet = new Set<string>([creatorUserId, ...memberUserIds]);

  // "Add all members of an existing group" (copies members, no live link)
  if (sourceGroupId) {
    const sourceGroup = inMemoryLedgers.get(sourceGroupId);
    if (sourceGroup && sourceGroup.type === 'GROUP') {
      for (const mId of sourceGroup.memberIds) {
        membersSet.add(mId);
      }
    }
  }

  const allMembers = Array.from(membersSet);
  const id = `trp_${ulid()}`;
  const now = new Date().toISOString();

  const tripRecord = {
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
    notifiedThresholds: [] as number[],
    expenses: [],
    settlements: [],
    createdAt: now,
    updatedAt: now,
  };

  inMemoryLedgers.set(id, tripRecord as any);

  // Persist trip to MySQL
  persistLedgerToDb(tripRecord as any).catch((err) => {
    console.error(`[TripsStore] Error persisting trip ${id} to MySQL:`, err);
  });

  // Log activity
  activityStore.log({
    ledgerId: id,
    actorUserId: creatorUserId,
    action: 'LEDGER_CREATED',
    entityType: 'ledger',
    entityId: id,
    payload: { name: tripRecord.name, budgetPaise },
  });

  // Notify members
  for (const mId of allMembers) {
    if (mId === creatorUserId) continue;
    const user = inMemoryUsers.get(mId);
    if (user && !user.isPlaceholder) {
      notificationsStore.create({
        userId: mId,
        type: 'ADDED_TO_TRIP' as any,
        payload: {
          tripId: id,
          tripName: tripRecord.name,
          addedBy: creatorUserId,
          budgetPaise,
        },
      });
    }
  }

  return tripRecord;
}

export function listUserTrips(userId: string) {
  const userTrips: any[] = [];

  for (const ledger of inMemoryLedgers.values()) {
    if (ledger.type === 'TRIP' && ledger.memberIds.includes(userId)) {
      const anyLedger = ledger as any;
      const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
      const totalSpentPaise = activeExpenses.reduce(
        (sum: number, exp: any) => sum + exp.totalPaise,
        0
      );

      const confirmedSettlements = ledger.settlements.filter(
        (s: any) => s.status === 'CONFIRMED'
      );
      const netResult = calculateNetBalances(
        ledger.memberIds,
        activeExpenses,
        confirmedSettlements
      );

      const budgetMeter = computeBudgetMeter(
        anyLedger.budgetPaise || 0,
        totalSpentPaise,
        anyLedger.startDate,
        anyLedger.endDate
      );

      userTrips.push({
        id: ledger.id,
        name: ledger.name,
        photoUrl: anyLedger.photoUrl || null,
        budgetPaise: anyLedger.budgetPaise || 0,
        startDate: anyLedger.startDate || null,
        endDate: anyLedger.endDate || null,
        status: anyLedger.status || 'ACTIVE',
        isCompleted: anyLedger.status === 'COMPLETED',
        creatorUserId: anyLedger.creatorUserId,
        isAdmin: anyLedger.creatorUserId === userId,
        membersCount: ledger.memberIds.length,
        myNetPaise: netResult.balances[userId] || 0,
        totalSpentPaise,
        budgetMeter,
        createdAt: anyLedger.createdAt,
      });
    }
  }

  // Sort by created descending
  userTrips.sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  return {
    all: userTrips,
    active: userTrips.filter((t) => !t.isCompleted),
    completed: userTrips.filter((t) => t.isCompleted),
  };
}

export function getTripDetails(tripId: string, callerUserId: string) {
  const ledger = inMemoryLedgers.get(tripId);
  if (!ledger || ledger.type !== 'TRIP') {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const anyLedger = ledger as any;
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );

  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const totalSpentPaise = activeExpenses.reduce(
    (sum: number, exp: any) => sum + exp.totalPaise,
    0
  );

  const membersInfo: TripMemberInfo[] = ledger.memberIds.map((mId) => {
    const user = inMemoryUsers.get(mId);
    return {
      userId: mId,
      name: user?.name || mId,
      phoneE164: user?.phoneE164 || '',
      photoUrl: user?.photoUrl || null,
      role: anyLedger.creatorUserId === mId ? 'CREATOR' : 'MEMBER',
      netPaise: netResult.balances[mId] || 0,
      isAppUser: user ? !user.isPlaceholder : true,
    };
  });

  const budgetMeter = computeBudgetMeter(
    anyLedger.budgetPaise || 0,
    totalSpentPaise,
    anyLedger.startDate,
    anyLedger.endDate
  );

  return {
    id: ledger.id,
    name: ledger.name,
    photoUrl: anyLedger.photoUrl || null,
    budgetPaise: anyLedger.budgetPaise || 0,
    startDate: anyLedger.startDate || null,
    endDate: anyLedger.endDate || null,
    status: anyLedger.status || 'ACTIVE',
    isCompleted: anyLedger.status === 'COMPLETED',
    creatorUserId: anyLedger.creatorUserId,
    isAdmin: anyLedger.creatorUserId === callerUserId,
    memberIds: ledger.memberIds,
    members: membersInfo,
    myNetPaise: netResult.balances[callerUserId] || 0,
    totalSpentPaise,
    budgetMeter,
    expenses: activeExpenses,
    settlements: ledger.settlements,
    createdAt: anyLedger.createdAt,
    updatedAt: anyLedger.updatedAt,
  };
}

export function updateTripBudget(
  tripId: string,
  actorUserId: string,
  newBudgetPaise: number
) {
  if (newBudgetPaise <= 0 || !Number.isInteger(newBudgetPaise)) {
    throw new ValidationError('Budget must be a positive integer in paise');
  }

  const ledger = inMemoryLedgers.get(tripId);
  if (!ledger || ledger.type !== 'TRIP') {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const anyLedger = ledger as any;
  if (anyLedger.creatorUserId !== actorUserId) {
    throw new ForbiddenError('Only the trip creator can update the budget');
  }

  const oldBudgetPaise = anyLedger.budgetPaise;
  anyLedger.budgetPaise = newBudgetPaise;
  anyLedger.updatedAt = new Date().toISOString();
  persistLedgerToDb(ledger).catch((err) => {
    console.error(`[TripsStore] Error updating trip budget in MySQL:`, err);
  });

  // Log activity
  activityStore.log({
    ledgerId: tripId,
    actorUserId,
    action: 'BUDGET_CHANGED' as any,
    entityType: 'ledger',
    entityId: tripId,
    payload: { oldBudgetPaise, newBudgetPaise },
  });

  // Re-check budget thresholds
  checkTripBudgetThresholds(tripId);

  return getTripDetails(tripId, actorUserId);
}

export function updateTrip(
  tripId: string,
  actorUserId: string,
  data: {
    name?: string;
    photoUrl?: string | null;
    startDate?: string | null;
    endDate?: string | null;
  }
) {
  const ledger = inMemoryLedgers.get(tripId);
  if (!ledger || ledger.type !== 'TRIP') {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const anyLedger = ledger as any;
  if (anyLedger.creatorUserId !== actorUserId) {
    throw new ForbiddenError('Only the trip creator can update trip details');
  }

  if (data.name !== undefined) {
    if (data.name.trim().length === 0) {
      throw new ValidationError('Trip name cannot be empty');
    }
    const oldName = ledger.name;
    ledger.name = data.name.trim();

    activityStore.log({
      ledgerId: tripId,
      actorUserId,
      action: 'LEDGER_RENAMED',
      entityType: 'ledger',
      entityId: tripId,
      payload: { oldName, newName: ledger.name },
    });
  }

  if (data.photoUrl !== undefined) anyLedger.photoUrl = data.photoUrl;
  if (data.startDate !== undefined) anyLedger.startDate = data.startDate;
  if (data.endDate !== undefined) anyLedger.endDate = data.endDate;

  anyLedger.updatedAt = new Date().toISOString();
  persistLedgerToDb(ledger).catch((err) => {
    console.error(`[TripsStore] Error updating trip in MySQL:`, err);
  });
  return getTripDetails(tripId, actorUserId);
}

export function completeTrip(tripId: string, actorUserId: string) {
  const ledger = inMemoryLedgers.get(tripId);
  if (!ledger || ledger.type !== 'TRIP') {
    throw new NotFoundError(`Trip ${tripId} not found`);
  }

  const anyLedger = ledger as any;
  if (anyLedger.creatorUserId !== actorUserId) {
    throw new ForbiddenError('Only the trip creator can mark a trip as completed');
  }

  anyLedger.status = 'COMPLETED';
  anyLedger.updatedAt = new Date().toISOString();
  persistLedgerToDb(ledger).catch((err) => {
    console.error(`[TripsStore] Error updating completed trip in MySQL:`, err);
  });

  activityStore.log({
    ledgerId: tripId,
    actorUserId,
    action: 'TRIP_COMPLETED' as any,
    entityType: 'ledger',
    entityId: tripId,
  });

  return getTripDetails(tripId, actorUserId);
}

export function checkTripBudgetThresholds(tripId: string) {
  const ledger = inMemoryLedgers.get(tripId);
  if (!ledger || ledger.type !== 'TRIP') return;

  const anyLedger = ledger as any;
  const budgetPaise = anyLedger.budgetPaise || 0;
  if (budgetPaise <= 0) return;

  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const totalSpentPaise = activeExpenses.reduce(
    (sum: number, exp: any) => sum + exp.totalPaise,
    0
  );

  const spentPercent = (totalSpentPaise / budgetPaise) * 100;
  if (!anyLedger.notifiedThresholds) {
    anyLedger.notifiedThresholds = [];
  }

  // 80% threshold warning
  if (spentPercent >= 80 && !anyLedger.notifiedThresholds.includes(80)) {
    anyLedger.notifiedThresholds.push(80);
    // Send notification to all trip members
    for (const memberId of ledger.memberIds) {
      notificationsStore.create({
        userId: memberId,
        type: 'TRIP_BUDGET_WARNING' as any,
        payload: {
          tripId,
          tripName: ledger.name,
          percent: 80,
          spentPaise: totalSpentPaise,
          budgetPaise,
        },
      });
    }
  }

  // 100% threshold exceeded
  if (spentPercent >= 100 && !anyLedger.notifiedThresholds.includes(100)) {
    anyLedger.notifiedThresholds.push(100);
    for (const memberId of ledger.memberIds) {
      notificationsStore.create({
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
      });
    }
  }
}

export function getTripDashboard(tripId: string, callerUserId: string) {
  const details = getTripDetails(tripId, callerUserId);
  const ledger = inMemoryLedgers.get(tripId)!;
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);

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
  const memberBars = details.members.map((mem) => ({
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

export function getTripGraph(
  tripId: string,
  callerUserId: string,
  mode: 'simplified' | 'actual' = 'simplified'
) {
  const details = getTripDetails(tripId, callerUserId);
  const ledger = inMemoryLedgers.get(tripId)!;
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );
  const pendingSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'PENDING'
  );

  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const nodes = details.members.map((mem) => ({
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
