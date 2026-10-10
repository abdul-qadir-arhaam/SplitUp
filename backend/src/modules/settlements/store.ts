import { ulid } from 'ulidx';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { inMemoryUsers } from '../users/store.js';
import { calculateNetBalances } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';
import { activityStore } from '../activity/store.js';
import {
  ValidationError,
  NotFoundError,
  ForbiddenError,
  ConflictError,
  SettlementOutdatedError,
  NothingDueError,
} from '../../lib/errors.js';

export interface Settlement {
  id: string;
  ledgerId: string;
  fromUserId: string; // sender
  toUserId: string; // receiver
  amountPaise: number;
  method: 'CASH' | 'UPI' | 'OFFSET' | 'OTHER';
  status: 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'OUTDATED' | 'CANCELLED';
  offsetId?: string | null;
  replacedById?: string | null;
  createdBy: string;
  respondedBy?: string | null;
  confirmedOnBehalf: boolean;
  reminderCount: number;
  lastRemindedAt?: string | null;
  createdAt: string;
  respondedAt?: string | null;
}

export interface SettlementEvent {
  id: string;
  settlementId: string;
  status: string;
  actorUserId: string;
  createdAt: string;
}

export const inMemorySettlements = new Map<string, Settlement>();
export const inMemorySettlementEvents: SettlementEvent[] = [];

// Concurrency locks
const settlementLocks = new Set<string>();

/**
 * Calculates current debt owed by fromUserId to toUserId in the ledger.
 * Returns positive paise if fromUserId owes toUserId, or 0 / negative if not.
 */
export function getCurrentDebt(
  ledgerId: string,
  fromUserId: string,
  toUserId: string
): number {
  const ledger = inMemoryLedgers.get(ledgerId);
  if (!ledger) {
    throw new NotFoundError(`Ledger ${ledgerId} not found`);
  }

  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );

  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const fromNet = netResult.balances[fromUserId] || 0;
  // If fromNet < 0, fromUserId owes -fromNet paise
  if (fromNet < 0) {
    return -fromNet;
  }
  return 0;
}

export function createSettlement(params: {
  ledgerId: string;
  fromUserId: string;
  toUserId: string;
  amountPaise: number;
  method?: 'CASH' | 'UPI' | 'OFFSET' | 'OTHER';
  createdBy: string;
}): Settlement {
  const { ledgerId, fromUserId, toUserId, amountPaise, createdBy } = params;
  const method = params.method || 'CASH';

  // Rule 1: Only the person who sends money creates a settlement
  if (fromUserId !== createdBy) {
    throw new ForbiddenError('Only the sender can initiate a settlement');
  }

  if (fromUserId === toUserId) {
    throw new ValidationError('Sender and receiver cannot be the same user');
  }

  if (amountPaise <= 0 || !Number.isInteger(amountPaise)) {
    throw new ValidationError('Amount must be a positive integer in paise');
  }

  const ledger = inMemoryLedgers.get(ledgerId);
  if (!ledger) {
    throw new NotFoundError(`Ledger ${ledgerId} not found`);
  }

  if (!ledger.memberIds.includes(fromUserId) || !ledger.memberIds.includes(toUserId)) {
    throw new ForbiddenError('Both parties must be members of the ledger');
  }

  // Check current debt
  const currentDebt = getCurrentDebt(ledgerId, fromUserId, toUserId);
  if (currentDebt <= 0) {
    throw new ValidationError('You do not owe any money to this friend in this ledger');
  }

  // Rule 7: Partial settlements are allowed up to the amount owed. Overpayment is blocked.
  if (amountPaise > currentDebt) {
    throw new ValidationError(
      `Settlement amount (${amountPaise} paise) exceeds current balance owed (${currentDebt} paise)`
    );
  }

  const id = `stl_${ulid()}`;
  const toUser = inMemoryUsers.get(toUserId);
  const isPlaceholder = toUser?.isPlaceholder === true;

  // Placeholder receivers: creator confirms on their behalf (self-confirmed (unverified))
  let status: Settlement['status'] = 'PENDING';
  let confirmedOnBehalf = false;
  let respondedBy: string | null = null;
  let respondedAt: string | null = null;

  if (isPlaceholder && toUser?.createdBy === createdBy) {
    status = 'CONFIRMED';
    confirmedOnBehalf = true;
    respondedBy = createdBy;
    respondedAt = new Date().toISOString();
  }

  const settlement: Settlement = {
    id,
    ledgerId,
    fromUserId,
    toUserId,
    amountPaise,
    method,
    status,
    confirmedOnBehalf,
    reminderCount: 0,
    createdBy,
    respondedBy,
    createdAt: new Date().toISOString(),
    respondedAt,
  };

  inMemorySettlements.set(id, settlement);
  ledger.settlements.push(settlement);

  // Audit event
  const event: SettlementEvent = {
    id: `sev_${ulid()}`,
    settlementId: id,
    status: settlement.status,
    actorUserId: createdBy,
    createdAt: new Date().toISOString(),
  };
  inMemorySettlementEvents.push(event);

  // Activity log
  activityStore.log({
    ledgerId,
    actorUserId: createdBy,
    action: status === 'CONFIRMED' ? 'SETTLEMENT_CONFIRMED' : 'SETTLEMENT_CREATED',
    entityType: 'settlement',
    entityId: id,
    payload: {
      amountPaise,
      fromUserId,
      toUserId,
      method,
      confirmedOnBehalf,
    },
  });

  // Notifications
  if (status === 'PENDING') {
    const notifyTarget = isPlaceholder ? (toUser?.createdBy || toUserId) : toUserId;
    notificationsStore.create({
      userId: notifyTarget,
      type: 'SETTLEMENT_REQUESTED',
      actionState: 'OPEN',
      payload: {
        settlementId: id,
        ledgerId,
        fromUserId,
        toUserId,
        amountPaise,
        method,
      },
    });
  }

  return settlement;
}

export function getSettlement(id: string): Settlement {
  const settlement = inMemorySettlements.get(id);
  if (!settlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  // Stale detection on open (Option a)
  if (settlement.status === 'PENDING') {
    const currentDebt = getCurrentDebt(
      settlement.ledgerId,
      settlement.fromUserId,
      settlement.toUserId
    );

    if (currentDebt < settlement.amountPaise) {
      settlement.status = 'OUTDATED';

      inMemorySettlementEvents.push({
        id: `sev_${ulid()}`,
        settlementId: id,
        status: 'OUTDATED',
        actorUserId: 'system',
        createdAt: new Date().toISOString(),
      });

      activityStore.log({
        ledgerId: settlement.ledgerId,
        actorUserId: 'system',
        action: 'SETTLEMENT_OUTDATED',
        entityType: 'settlement',
        entityId: id,
        payload: {
          originalAmountPaise: settlement.amountPaise,
          currentDebt,
        },
      });

      // Update receiver's notification action state
      notificationsStore.updateSettlementNotification(id, 'EXPIRED');

      // Notify sender
      notificationsStore.create({
        userId: settlement.fromUserId,
        type: 'SETTLEMENT_OUTDATED',
        payload: {
          settlementId: id,
          ledgerId: settlement.ledgerId,
          originalAmountPaise: settlement.amountPaise,
          currentDebt,
        },
      });
    }
  }

  return settlement;
}

export function confirmSettlement(id: string, actorUserId: string): Settlement {
  if (settlementLocks.has(id)) {
    throw new ConflictError('Settlement confirmation already in progress');
  }

  try {
    settlementLocks.add(id);

    const settlement = inMemorySettlements.get(id);
    if (!settlement) {
      throw new NotFoundError(`Settlement ${id} not found`);
    }

    if (settlement.status !== 'PENDING') {
      throw new ConflictError(`Settlement cannot be confirmed (current status: ${settlement.status})`);
    }

    // Receiver or placeholder creator only
    const toUser = inMemoryUsers.get(settlement.toUserId);
    const isReceiver = settlement.toUserId === actorUserId;
    const isPlaceholderCreator = toUser?.isPlaceholder && toUser.createdBy === actorUserId;

    if (!isReceiver && !isPlaceholderCreator) {
      throw new ForbiddenError('Only the receiver can confirm this settlement');
    }

    // Re-validate validity under lock (Option a)
    const currentDebt = getCurrentDebt(
      settlement.ledgerId,
      settlement.fromUserId,
      settlement.toUserId
    );

    if (currentDebt < settlement.amountPaise) {
      settlement.status = 'OUTDATED';

      inMemorySettlementEvents.push({
        id: `sev_${ulid()}`,
        settlementId: id,
        status: 'OUTDATED',
        actorUserId,
        createdAt: new Date().toISOString(),
      });

      activityStore.log({
        ledgerId: settlement.ledgerId,
        actorUserId,
        action: 'SETTLEMENT_OUTDATED',
        entityType: 'settlement',
        entityId: id,
        payload: {
          originalAmountPaise: settlement.amountPaise,
          currentDebt,
        },
      });

      notificationsStore.updateSettlementNotification(id, 'EXPIRED');
      notificationsStore.create({
        userId: settlement.fromUserId,
        type: 'SETTLEMENT_OUTDATED',
        payload: {
          settlementId: id,
          ledgerId: settlement.ledgerId,
          originalAmountPaise: settlement.amountPaise,
          currentDebt,
        },
      });

      throw new SettlementOutdatedError('Amount is no longer valid due to recent expenses or changes');
    }

    settlement.status = 'CONFIRMED';
    settlement.respondedBy = actorUserId;
    settlement.respondedAt = new Date().toISOString();
    if (isPlaceholderCreator && !isReceiver) {
      settlement.confirmedOnBehalf = true;
    }

    // Audit event
    inMemorySettlementEvents.push({
      id: `sev_${ulid()}`,
      settlementId: id,
      status: 'CONFIRMED',
      actorUserId,
      createdAt: new Date().toISOString(),
    });

    activityStore.log({
      ledgerId: settlement.ledgerId,
      actorUserId,
      action: 'SETTLEMENT_CONFIRMED',
      entityType: 'settlement',
      entityId: id,
      payload: {
        amountPaise: settlement.amountPaise,
        confirmedOnBehalf: settlement.confirmedOnBehalf,
      },
    });

    notificationsStore.updateSettlementNotification(id, 'DONE', 'CONFIRMED');

    // Notify sender
    notificationsStore.create({
      userId: settlement.fromUserId,
      type: 'SETTLEMENT_CONFIRMED',
      payload: {
        settlementId: id,
        ledgerId: settlement.ledgerId,
        amountPaise: settlement.amountPaise,
        receiverUserId: settlement.toUserId,
      },
    });

    return settlement;
  } finally {
    settlementLocks.delete(id);
  }
}

export function rejectSettlement(id: string, actorUserId: string): Settlement {
  const settlement = inMemorySettlements.get(id);
  if (!settlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  if (settlement.status !== 'PENDING') {
    throw new ConflictError(`Settlement cannot be rejected (current status: ${settlement.status})`);
  }

  const toUser = inMemoryUsers.get(settlement.toUserId);
  const isReceiver = settlement.toUserId === actorUserId;
  const isPlaceholderCreator = toUser?.isPlaceholder && toUser.createdBy === actorUserId;

  if (!isReceiver && !isPlaceholderCreator) {
    throw new ForbiddenError('Only the receiver can reject this settlement');
  }

  settlement.status = 'REJECTED';
  settlement.respondedBy = actorUserId;
  settlement.respondedAt = new Date().toISOString();

  inMemorySettlementEvents.push({
    id: `sev_${ulid()}`,
    settlementId: id,
    status: 'REJECTED',
    actorUserId,
    createdAt: new Date().toISOString(),
  });

  activityStore.log({
    ledgerId: settlement.ledgerId,
    actorUserId,
    action: 'SETTLEMENT_REJECTED',
    entityType: 'settlement',
    entityId: id,
    payload: {
      amountPaise: settlement.amountPaise,
    },
  });

  notificationsStore.updateSettlementNotification(id, 'DONE', 'REJECTED');

  notificationsStore.create({
    userId: settlement.fromUserId,
    type: 'SETTLEMENT_REJECTED',
    payload: {
      settlementId: id,
      ledgerId: settlement.ledgerId,
      amountPaise: settlement.amountPaise,
      receiverUserId: settlement.toUserId,
    },
  });

  return settlement;
}

export function cancelSettlement(id: string, actorUserId: string): Settlement {
  const settlement = inMemorySettlements.get(id);
  if (!settlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  if (settlement.status !== 'PENDING') {
    throw new ConflictError(`Settlement cannot be cancelled (current status: ${settlement.status})`);
  }

  if (settlement.fromUserId !== actorUserId) {
    throw new ForbiddenError('Only the sender can cancel a pending settlement');
  }

  settlement.status = 'CANCELLED';

  inMemorySettlementEvents.push({
    id: `sev_${ulid()}`,
    settlementId: id,
    status: 'CANCELLED',
    actorUserId,
    createdAt: new Date().toISOString(),
  });

  activityStore.log({
    ledgerId: settlement.ledgerId,
    actorUserId,
    action: 'SETTLEMENT_CANCELLED',
    entityType: 'settlement',
    entityId: id,
  });

  notificationsStore.updateSettlementNotification(id, 'EXPIRED');

  return settlement;
}

export function resubmitSettlement(params: {
  id: string;
  actorUserId: string;
  newAmountPaise?: number;
}): Settlement {
  const { id, actorUserId, newAmountPaise } = params;
  const oldSettlement = inMemorySettlements.get(id);
  if (!oldSettlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  if (oldSettlement.fromUserId !== actorUserId) {
    throw new ForbiddenError('Only the sender can resubmit');
  }

  if (oldSettlement.status !== 'REJECTED' && oldSettlement.status !== 'OUTDATED') {
    throw new ConflictError('Only REJECTED or OUTDATED settlements can be resubmitted');
  }

  // Check current debt
  const currentDebt = getCurrentDebt(
    oldSettlement.ledgerId,
    oldSettlement.fromUserId,
    oldSettlement.toUserId
  );

  if (currentDebt <= 0) {
    throw new NothingDueError('No amount due anymore');
  }

  const targetAmount = newAmountPaise !== undefined ? newAmountPaise : Math.min(oldSettlement.amountPaise, currentDebt);

  if (targetAmount <= 0 || !Number.isInteger(targetAmount)) {
    throw new ValidationError('Resubmitted amount must be a positive integer in paise');
  }

  if (targetAmount > currentDebt) {
    throw new ValidationError(
      `Amount (${targetAmount} paise) exceeds current balance owed (${currentDebt} paise)`
    );
  }

  // Check 24-hour notification guard
  let suppressNotification = false;
  if (
    oldSettlement.status === 'REJECTED' &&
    oldSettlement.amountPaise === targetAmount &&
    oldSettlement.respondedAt
  ) {
    const elapsedMs = Date.now() - new Date(oldSettlement.respondedAt).getTime();
    if (elapsedMs < 24 * 60 * 60 * 1000) {
      suppressNotification = true;
    }
  }

  // Create new settlement
  const newSettlement = createSettlement({
    ledgerId: oldSettlement.ledgerId,
    fromUserId: oldSettlement.fromUserId,
    toUserId: oldSettlement.toUserId,
    amountPaise: targetAmount,
    method: oldSettlement.method,
    createdBy: actorUserId,
  });

  // Link replaced_by_id on the old record
  oldSettlement.replacedById = newSettlement.id;

  // If suppressed, remove the notification created in createSettlement
  if (suppressNotification) {
    notificationsStore.updateSettlementNotification(newSettlement.id, 'DONE', 'SUPPRESSED');
  }

  return newSettlement;
}
