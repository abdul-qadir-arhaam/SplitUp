import { ulid } from 'ulidx';
import { db } from '../../db/knex.js';
import { getLedgerBalancesFromDb } from '../balances/sqlBalances.js';
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
import { persistSettlementToDb } from '../ledgers/db_sync.js';

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

export function mapDbSettlementToModel(s: any): Settlement {
  return {
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
    lastRemindedAt: s.last_reminded_at instanceof Date ? s.last_reminded_at.toISOString() : (s.last_reminded_at ? String(s.last_reminded_at) : null),
    createdAt: s.created_at instanceof Date ? s.created_at.toISOString() : String(s.created_at),
    respondedAt: s.responded_at instanceof Date ? s.responded_at.toISOString() : (s.responded_at ? String(s.responded_at) : null),
  };
}

/**
 * Calculates current debt owed by fromUserId to toUserId in the ledger.
 * Returns positive paise if fromUserId owes toUserId, or 0 / negative if not.
 */
export async function getCurrentDebt(
  ledgerId: string,
  fromUserId: string,
  toUserId: string
): Promise<number> {
  // 1. Try DB first
  const dbLedger = await db('ledgers').where({ id: ledgerId }).first();
  if (dbLedger) {
    const balances = await getLedgerBalancesFromDb(ledgerId);
    const fromNet = balances[fromUserId] || 0;
    if (fromNet < 0) {
      return -fromNet;
    }
    return 0;
  }

  // 2. Fallback to inMemoryLedgers
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
  if (fromNet < 0) {
    return -fromNet;
  }
  return 0;
}

export async function createSettlement(params: {
  ledgerId: string;
  fromUserId: string;
  toUserId: string;
  amountPaise: number;
  method?: 'CASH' | 'UPI' | 'OFFSET' | 'OTHER';
  createdBy: string;
}): Promise<Settlement> {
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

  // Verify membership across DB or inMemory
  let memberIds: string[] = [];
  const dbLedger = await db('ledgers').where({ id: ledgerId }).first();
  if (dbLedger) {
    const members = await db('ledger_members')
      .where({ ledger_id: ledgerId })
      .whereNull('left_at')
      .select('user_id');
    memberIds = members.map((m) => m.user_id);
  } else {
    const ledger = inMemoryLedgers.get(ledgerId);
    if (!ledger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }
    memberIds = ledger.memberIds;
  }

  if (!memberIds.includes(fromUserId) || !memberIds.includes(toUserId)) {
    throw new ForbiddenError('Both parties must be members of the ledger');
  }

  // Check current debt
  const currentDebt = await getCurrentDebt(ledgerId, fromUserId, toUserId);
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
  const dbToUser = await db('users').where({ id: toUserId }).first();
  const memToUser = inMemoryUsers.get(toUserId);
  const isPlaceholder = dbToUser ? Boolean(dbToUser.is_placeholder) : (memToUser?.isPlaceholder === true);
  const placeholderCreator = dbToUser?.created_by || memToUser?.createdBy;

  // Placeholder receivers: creator confirms on their behalf (self-confirmed (unverified))
  let status: Settlement['status'] = 'PENDING';
  let confirmedOnBehalf = false;
  let respondedBy: string | null = null;
  let respondedAt: string | null = null;

  if (isPlaceholder && placeholderCreator === createdBy) {
    status = 'CONFIRMED';
    confirmedOnBehalf = true;
    respondedBy = createdBy;
    respondedAt = new Date().toISOString();
  }

  const now = new Date();
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
    createdAt: now.toISOString(),
    respondedAt,
  };

  // Persist to MySQL
  try {
    await db('settlements').insert({
      id,
      ledger_id: ledgerId,
      from_user_id: fromUserId,
      to_user_id: toUserId,
      amount_paise: amountPaise,
      method,
      status,
      offset_id: null,
      replaced_by_id: null,
      created_by: createdBy,
      responded_by: respondedBy,
      confirmed_on_behalf: confirmedOnBehalf ? 1 : 0,
      reminder_count: 0,
      last_reminded_at: null,
      created_at: now,
      responded_at: respondedAt ? new Date(respondedAt) : null,
    });

    await db('settlement_events').insert({
      settlement_id: id,
      status: settlement.status,
      actor_user_id: createdBy,
      created_at: now,
    }).catch(() => {});

    await db('activity_log').insert({
      ledger_id: ledgerId,
      actor_user_id: createdBy,
      action: status === 'CONFIRMED' ? 'SETTLEMENT_CONFIRMED' : 'SETTLEMENT_CREATED',
      entity_type: 'settlement',
      entity_id: id,
      payload: JSON.stringify({
        amountPaise,
        fromUserId,
        toUserId,
        method,
        confirmedOnBehalf,
      }),
      created_at: now,
    }).catch(() => {});
  } catch (err) {
    console.error(`[SettlementsStore] Error inserting settlement ${id} to MySQL:`, err);
  }

  // Also sync to in-memory maps
  inMemorySettlements.set(id, settlement);
  const memLedger = inMemoryLedgers.get(ledgerId);
  if (memLedger) {
    memLedger.settlements.push(settlement);
  }

  // Audit event in-memory
  const event: SettlementEvent = {
    id: `sev_${ulid()}`,
    settlementId: id,
    status: settlement.status,
    actorUserId: createdBy,
    createdAt: now.toISOString(),
  };
  inMemorySettlementEvents.push(event);

  // Activity log in-memory
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
    const notifyTarget = isPlaceholder ? (placeholderCreator || toUserId) : toUserId;
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

export async function getSettlement(id: string): Promise<Settlement> {
  let settlement: Settlement | undefined = inMemorySettlements.get(id);
  const row = await db('settlements').where({ id }).first();
  if (row) {
    settlement = mapDbSettlementToModel(row);
    inMemorySettlements.set(id, settlement);
  }

  if (!settlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  // Stale detection on open (Option a)
  if (settlement.status === 'PENDING') {
    const currentDebt = await getCurrentDebt(
      settlement.ledgerId,
      settlement.fromUserId,
      settlement.toUserId
    );

    if (currentDebt < settlement.amountPaise) {
      settlement.status = 'OUTDATED';

      await db('settlements').where({ id }).update({ status: 'OUTDATED' }).catch(() => {});

      await db('settlement_events').insert({
        settlement_id: id,
        status: 'OUTDATED',
        actor_user_id: 'system',
        created_at: new Date(),
      }).catch(() => {});

      await db('activity_log').insert({
        ledger_id: settlement.ledgerId,
        actor_user_id: 'system',
        action: 'SETTLEMENT_OUTDATED',
        entity_type: 'settlement',
        entity_id: id,
        payload: JSON.stringify({
          originalAmountPaise: settlement.amountPaise,
          currentDebt,
        }),
        created_at: new Date(),
      }).catch(() => {});

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
    }
  }

  return settlement;
}

export async function confirmSettlement(id: string, actorUserId: string): Promise<Settlement> {
  if (settlementLocks.has(id)) {
    throw new ConflictError('Settlement confirmation already in progress');
  }

  try {
    settlementLocks.add(id);

    let settlement: Settlement | undefined = inMemorySettlements.get(id);
    const row = await db('settlements').where({ id }).first();
    if (row) {
      settlement = mapDbSettlementToModel(row);
      inMemorySettlements.set(id, settlement);
    }

    if (!settlement) {
      throw new NotFoundError(`Settlement ${id} not found`);
    }

    if (settlement.status !== 'PENDING') {
      throw new ConflictError(`Settlement cannot be confirmed (current status: ${settlement.status})`);
    }

    // Receiver or placeholder creator only
    const dbToUser = await db('users').where({ id: settlement.toUserId }).first();
    const memToUser = inMemoryUsers.get(settlement.toUserId);
    const isReceiver = settlement.toUserId === actorUserId;
    const isPlaceholder = dbToUser ? Boolean(dbToUser.is_placeholder) : (memToUser?.isPlaceholder === true);
    const placeholderCreator = dbToUser?.created_by || memToUser?.createdBy;
    const isPlaceholderCreator = isPlaceholder && placeholderCreator === actorUserId;

    if (!isReceiver && !isPlaceholderCreator) {
      throw new ForbiddenError('Only the receiver can confirm this settlement');
    }

    // Re-validate validity under lock (Option a)
    const currentDebt = await getCurrentDebt(
      settlement.ledgerId,
      settlement.fromUserId,
      settlement.toUserId
    );

    const now = new Date();
    if (currentDebt < settlement.amountPaise) {
      settlement.status = 'OUTDATED';

      await db('settlements').where({ id }).update({ status: 'OUTDATED' }).catch(() => {});

      await db('settlement_events').insert({
        settlement_id: id,
        status: 'OUTDATED',
        actor_user_id: actorUserId,
        created_at: now,
      }).catch(() => {});

      await db('activity_log').insert({
        ledger_id: settlement.ledgerId,
        actor_user_id: actorUserId,
        action: 'SETTLEMENT_OUTDATED',
        entity_type: 'settlement',
        entity_id: id,
        payload: JSON.stringify({
          originalAmountPaise: settlement.amountPaise,
          currentDebt,
        }),
        created_at: now,
      }).catch(() => {});

      inMemorySettlementEvents.push({
        id: `sev_${ulid()}`,
        settlementId: id,
        status: 'OUTDATED',
        actorUserId,
        createdAt: now.toISOString(),
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
    settlement.respondedAt = now.toISOString();
    if (isPlaceholderCreator && !isReceiver) {
      settlement.confirmedOnBehalf = true;
    }

    // Persist confirmed status to MySQL
    await db('settlements').where({ id }).update({
      status: 'CONFIRMED',
      responded_by: actorUserId,
      responded_at: now,
      confirmed_on_behalf: settlement.confirmedOnBehalf ? 1 : 0,
    }).catch(() => {});

    await db('settlement_events').insert({
      settlement_id: id,
      status: 'CONFIRMED',
      actor_user_id: actorUserId,
      created_at: now,
    }).catch(() => {});

    await db('activity_log').insert({
      ledger_id: settlement.ledgerId,
      actor_user_id: actorUserId,
      action: 'SETTLEMENT_CONFIRMED',
      entity_type: 'settlement',
      entity_id: id,
      payload: JSON.stringify({
        amountPaise: settlement.amountPaise,
        confirmedOnBehalf: settlement.confirmedOnBehalf,
      }),
      created_at: now,
    }).catch(() => {});

    // Audit event in-memory
    inMemorySettlementEvents.push({
      id: `sev_${ulid()}`,
      settlementId: id,
      status: 'CONFIRMED',
      actorUserId,
      createdAt: now.toISOString(),
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
    const confirmNotifId = `notif_${ulid()}`;
    const confirmPayload = {
      settlementId: id,
      ledgerId: settlement.ledgerId,
      amountPaise: settlement.amountPaise,
      receiverUserId: settlement.toUserId,
    };
    notificationsStore.create({
      userId: settlement.fromUserId,
      type: 'SETTLEMENT_CONFIRMED',
      payload: confirmPayload,
    });

    await db('notifications').insert({
      id: confirmNotifId,
      user_id: settlement.fromUserId,
      type: 'SETTLEMENT_CONFIRMED',
      payload: JSON.stringify(confirmPayload),
      action_state: null,
      action_result: null,
      read_at: null,
      created_at: now,
    }).catch(() => {});

    return settlement;
  } finally {
    settlementLocks.delete(id);
  }
}

export async function rejectSettlement(id: string, actorUserId: string): Promise<Settlement> {
  let settlement: Settlement | undefined = inMemorySettlements.get(id);
  const row = await db('settlements').where({ id }).first();
  if (row) {
    settlement = mapDbSettlementToModel(row);
    inMemorySettlements.set(id, settlement);
  }

  if (!settlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  if (settlement.status !== 'PENDING') {
    throw new ConflictError(`Settlement cannot be rejected (current status: ${settlement.status})`);
  }

  const dbToUser = await db('users').where({ id: settlement.toUserId }).first();
  const memToUser = inMemoryUsers.get(settlement.toUserId);
  const isReceiver = settlement.toUserId === actorUserId;
  const isPlaceholder = dbToUser ? Boolean(dbToUser.is_placeholder) : (memToUser?.isPlaceholder === true);
  const placeholderCreator = dbToUser?.created_by || memToUser?.createdBy;
  const isPlaceholderCreator = isPlaceholder && placeholderCreator === actorUserId;

  if (!isReceiver && !isPlaceholderCreator) {
    throw new ForbiddenError('Only the receiver can reject this settlement');
  }

  const now = new Date();
  settlement.status = 'REJECTED';
  settlement.respondedBy = actorUserId;
  settlement.respondedAt = now.toISOString();

  // Persist rejected status to MySQL
  await db('settlements').where({ id }).update({
    status: 'REJECTED',
    responded_by: actorUserId,
    responded_at: now,
  }).catch(() => {});

  await db('settlement_events').insert({
    settlement_id: id,
    status: 'REJECTED',
    actor_user_id: actorUserId,
    created_at: now,
  }).catch(() => {});

  await db('activity_log').insert({
    ledger_id: settlement.ledgerId,
    actor_user_id: actorUserId,
    action: 'SETTLEMENT_REJECTED',
    entity_type: 'settlement',
    entity_id: id,
    payload: JSON.stringify({
      amountPaise: settlement.amountPaise,
    }),
    created_at: now,
  }).catch(() => {});

  inMemorySettlementEvents.push({
    id: `sev_${ulid()}`,
    settlementId: id,
    status: 'REJECTED',
    actorUserId,
    createdAt: now.toISOString(),
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

  const rejectNotifId = `notif_${ulid()}`;
  const rejectPayload = {
    settlementId: id,
    ledgerId: settlement.ledgerId,
    amountPaise: settlement.amountPaise,
    receiverUserId: settlement.toUserId,
  };
  notificationsStore.create({
    userId: settlement.fromUserId,
    type: 'SETTLEMENT_REJECTED',
    payload: rejectPayload,
  });

  await db('notifications').insert({
    id: rejectNotifId,
    user_id: settlement.fromUserId,
    type: 'SETTLEMENT_REJECTED',
    payload: JSON.stringify(rejectPayload),
    action_state: null,
    action_result: null,
    read_at: null,
    created_at: now,
  }).catch(() => {});

  return settlement;
}

export async function cancelSettlement(id: string, actorUserId: string): Promise<Settlement> {
  let settlement: Settlement | undefined = inMemorySettlements.get(id);
  const row = await db('settlements').where({ id }).first();
  if (row) {
    settlement = mapDbSettlementToModel(row);
    inMemorySettlements.set(id, settlement);
  }

  if (!settlement) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  if (settlement.status !== 'PENDING') {
    throw new ConflictError(`Settlement cannot be cancelled (current status: ${settlement.status})`);
  }

  if (settlement.fromUserId !== actorUserId) {
    throw new ForbiddenError('Only the sender can cancel a pending settlement');
  }

  const now = new Date();
  settlement.status = 'CANCELLED';

  // Persist cancelled status to MySQL
  await db('settlements').where({ id }).update({
    status: 'CANCELLED',
  }).catch(() => {});

  await db('settlement_events').insert({
    settlement_id: id,
    status: 'CANCELLED',
    actor_user_id: actorUserId,
    created_at: now,
  }).catch(() => {});

  inMemorySettlementEvents.push({
    id: `sev_${ulid()}`,
    settlementId: id,
    status: 'CANCELLED',
    actorUserId,
    createdAt: now.toISOString(),
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

export async function resubmitSettlement(params: {
  id: string;
  actorUserId: string;
  newAmountPaise?: number;
}): Promise<Settlement> {
  const { id, actorUserId, newAmountPaise } = params;
  let oldSettlement: Settlement | undefined = inMemorySettlements.get(id);
  const row = await db('settlements').where({ id }).first();
  if (row) {
    oldSettlement = mapDbSettlementToModel(row);
    inMemorySettlements.set(id, oldSettlement);
  }

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
  const currentDebt = await getCurrentDebt(
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
  const newSettlement = await createSettlement({
    ledgerId: oldSettlement.ledgerId,
    fromUserId: oldSettlement.fromUserId,
    toUserId: oldSettlement.toUserId,
    amountPaise: targetAmount,
    method: oldSettlement.method,
    createdBy: actorUserId,
  });

  // Link replaced_by_id on the old record
  oldSettlement.replacedById = newSettlement.id;
  await db('settlements').where({ id: oldSettlement.id }).update({ replaced_by_id: newSettlement.id }).catch(() => {});

  // If suppressed, remove the notification created in createSettlement
  if (suppressNotification) {
    notificationsStore.updateSettlementNotification(newSettlement.id, 'DONE', 'SUPPRESSED');
  }

  return newSettlement;
}
