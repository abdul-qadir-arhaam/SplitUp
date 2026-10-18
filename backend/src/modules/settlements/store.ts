import { ulid } from 'ulidx';
import type { Knex } from 'knex';
import { db } from '../../db/knex.js';
import { getLedgerBalancesFromDb } from '../balances/sqlBalances.js';
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

// Deprecated in-memory references kept only for backwards compatibility with non-migrated modules (e.g. offsets)
export const inMemorySettlements = new Map<string, Settlement>();
export const inMemorySettlementEvents: SettlementEvent[] = [];

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
 * Calculates current debt owed by fromUserId to toUserId in the ledger using SQL.
 * Returns positive paise if fromUserId owes toUserId, or 0 / negative if not.
 */
export async function getCurrentDebt(
  ledgerId: string,
  fromUserId: string,
  toUserId: string,
  trxOrDb: Knex | Knex.Transaction = db
): Promise<number> {
  const balances = await getLedgerBalancesFromDb(ledgerId, trxOrDb as Knex);
  const fromNet = balances[fromUserId] || 0;
  const toNet = balances[toUserId] || 0;

  if (fromNet < 0 && toNet > 0) {
    return Math.min(-fromNet, toNet);
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
}): Promise<{ settlement: Settlement; balances: Record<string, number> }> {
  const { ledgerId, fromUserId, toUserId, amountPaise, createdBy } = params;
  const method = params.method || 'CASH';

  // Rule R1/R2: Only the sender can initiate a settlement
  if (fromUserId !== createdBy) {
    throw new ForbiddenError('Only the sender can initiate a settlement');
  }

  if (fromUserId === toUserId) {
    throw new ValidationError('Sender and receiver cannot be the same user');
  }

  if (amountPaise <= 0 || !Number.isInteger(amountPaise)) {
    throw new ValidationError('Amount must be a positive integer in paise');
  }

  return await db.transaction(async (trx) => {
    // Verify ledger existence
    const dbLedger = await trx('ledgers').where({ id: ledgerId }).first();
    if (!dbLedger) {
      throw new NotFoundError(`Ledger ${ledgerId} not found`);
    }

    // Verify membership: both must be active members
    const members = await trx('ledger_members')
      .where({ ledger_id: ledgerId })
      .whereIn('user_id', [fromUserId, toUserId])
      .whereNull('left_at')
      .select('user_id');

    const memberSet = new Set(members.map((m) => m.user_id));
    if (!memberSet.has(fromUserId) || !memberSet.has(toUserId)) {
      throw new ForbiddenError('Both parties must be members of the ledger');
    }

    // Rule R3: At most ONE PENDING settlement per (ledger, sender, receiver)
    const existingPending = await trx('settlements')
      .where({
        ledger_id: ledgerId,
        from_user_id: fromUserId,
        to_user_id: toUserId,
        status: 'PENDING',
      })
      .forUpdate()
      .first();

    if (existingPending) {
      const conflictErr = new ConflictError(
        'A pending settlement already exists between these users in this ledger'
      );
      (conflictErr as any).existingSettlement = mapDbSettlementToModel(existingPending);
      throw conflictErr;
    }

    // Rule R2: Net values come from SQL balance query
    const balances = await getLedgerBalancesFromDb(ledgerId, trx);
    const senderNet = balances[fromUserId] || 0;
    const receiverNet = balances[toUserId] || 0;

    if (senderNet >= 0) {
      throw new ValidationError('You do not owe any money in this ledger');
    }
    if (receiverNet <= 0) {
      throw new ValidationError('Receiver is not owed any money in this ledger');
    }

    const maxAllowed = Math.min(-senderNet, receiverNet);
    if (amountPaise > maxAllowed) {
      throw new ValidationError(
        `Settlement amount (${amountPaise} paise) exceeds current balance owed (${maxAllowed} paise)`
      );
    }

    // Check placeholder receiver logic
    const toUser = await trx('users').where({ id: toUserId }).first();
    const isPlaceholder = toUser ? Boolean(toUser.is_placeholder) : false;
    const placeholderCreator = toUser?.created_by;

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

    const id = `stl_${ulid()}`;
    const now = new Date();

    await trx('settlements').insert({
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

    await trx('settlement_events').insert({
      settlement_id: id,
      status,
      actor_user_id: createdBy,
      created_at: now,
    });

    await trx('activity_log').insert({
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
    });

    // Rule R8: Notifications written in same transaction
    if (status === 'PENDING') {
      const notifyTarget = isPlaceholder ? (placeholderCreator || toUserId) : toUserId;
      await notificationsStore.create(
        {
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
        },
        trx
      );
    }

    const updatedBalances = await getLedgerBalancesFromDb(ledgerId, trx);
    const createdRow = await trx('settlements').where({ id }).first();
    const settlement = mapDbSettlementToModel(createdRow);

    return { settlement, balances: updatedBalances };
  });
}

export async function getSettlement(id: string): Promise<Settlement> {
  const row = await db('settlements').where({ id }).first();
  if (!row) {
    throw new NotFoundError(`Settlement ${id} not found`);
  }

  let settlement = mapDbSettlementToModel(row);

  // Rule R6: Outdated is also evaluated lazily when a settlement is read
  if (settlement.status === 'PENDING') {
    const currentDebt = await getCurrentDebt(
      settlement.ledgerId,
      settlement.fromUserId,
      settlement.toUserId
    );

    if (currentDebt < settlement.amountPaise) {
      await db.transaction(async (trx) => {
        const locked = await trx('settlements').where({ id }).forUpdate().first();
        if (locked && locked.status === 'PENDING') {
          const now = new Date();
          await trx('settlements').where({ id }).update({ status: 'OUTDATED' });
          await trx('settlement_events').insert({
            settlement_id: id,
            status: 'OUTDATED',
            actor_user_id: 'system',
            created_at: now,
          });
          await trx('activity_log').insert({
            ledger_id: settlement.ledgerId,
            actor_user_id: 'system',
            action: 'SETTLEMENT_OUTDATED',
            entity_type: 'settlement',
            entity_id: id,
            payload: JSON.stringify({
              originalAmountPaise: settlement.amountPaise,
              currentDebt,
            }),
            created_at: now,
          });

          await notificationsStore.updateSettlementNotification(id, 'EXPIRED', undefined, trx);
          await notificationsStore.create(
            {
              userId: settlement.fromUserId,
              type: 'SETTLEMENT_OUTDATED',
              payload: {
                settlementId: id,
                ledgerId: settlement.ledgerId,
                originalAmountPaise: settlement.amountPaise,
                currentDebt,
              },
            },
            trx
          );
        }
      });

      const updatedRow = await db('settlements').where({ id }).first();
      settlement = mapDbSettlementToModel(updatedRow);
    }
  }

  return settlement;
}

export async function confirmSettlement(
  id: string,
  actorUserId: string
): Promise<{ settlement: Settlement; balances: Record<string, number> }> {
  let isOutdated = false;
  const result = await db.transaction(async (trx) => {
    // Lock the settlement row
    const row = await trx('settlements').where({ id }).forUpdate().first();
    if (!row) {
      throw new NotFoundError(`Settlement ${id} not found`);
    }

    if (row.status !== 'PENDING') {
      throw new ConflictError(
        `Settlement cannot be confirmed (current status: ${row.status})`
      );
    }

    // Receiver or placeholder creator only
    const dbToUser = await trx('users').where({ id: row.to_user_id }).first();
    const isReceiver = row.to_user_id === actorUserId;
    const isPlaceholder = dbToUser ? Boolean(dbToUser.is_placeholder) : false;
    const placeholderCreator = dbToUser?.created_by;
    const isPlaceholderCreator = isPlaceholder && placeholderCreator === actorUserId;

    if (!isReceiver && !isPlaceholderCreator) {
      throw new ForbiddenError('Only the receiver can confirm this settlement');
    }

    // Lock ledger members
    await trx('ledger_members').where({ ledger_id: row.ledger_id }).forUpdate();

    // Rule R5: Re-validate validity under lock
    const balances = await getLedgerBalancesFromDb(row.ledger_id, trx);
    const senderNet = balances[row.from_user_id] || 0;
    const receiverNet = balances[row.to_user_id] || 0;
    const maxValid = (senderNet < 0 && receiverNet > 0) ? Math.min(-senderNet, receiverNet) : 0;

    const now = new Date();
    if (row.amount_paise > maxValid) {
      isOutdated = true;
      // Mark OUTDATED - no balance change
      await trx('settlements').where({ id }).update({ status: 'OUTDATED' });
      await trx('settlement_events').insert({
        settlement_id: id,
        status: 'OUTDATED',
        actor_user_id: actorUserId,
        created_at: now,
      });
      await trx('activity_log').insert({
        ledger_id: row.ledger_id,
        actor_user_id: actorUserId,
        action: 'SETTLEMENT_OUTDATED',
        entity_type: 'settlement',
        entity_id: id,
        payload: JSON.stringify({
          originalAmountPaise: row.amount_paise,
          maxValid,
        }),
        created_at: now,
      });

      await notificationsStore.updateSettlementNotification(id, 'EXPIRED', undefined, trx);
      await notificationsStore.create(
        {
          userId: row.from_user_id,
          type: 'SETTLEMENT_OUTDATED',
          payload: {
            settlementId: id,
            ledgerId: row.ledger_id,
            originalAmountPaise: row.amount_paise,
            maxValid,
          },
        },
        trx
      );

      const updatedRow = await trx('settlements').where({ id }).first();
      return {
        settlement: mapDbSettlementToModel(updatedRow),
        balances,
      };
    }

    const confirmedOnBehalf = isPlaceholderCreator && !isReceiver;

    await trx('settlements').where({ id }).update({
      status: 'CONFIRMED',
      responded_by: actorUserId,
      responded_at: now,
      confirmed_on_behalf: confirmedOnBehalf ? 1 : 0,
    });

    await trx('settlement_events').insert({
      settlement_id: id,
      status: 'CONFIRMED',
      actor_user_id: actorUserId,
      created_at: now,
    });

    await trx('activity_log').insert({
      ledger_id: row.ledger_id,
      actor_user_id: actorUserId,
      action: 'SETTLEMENT_CONFIRMED',
      entity_type: 'settlement',
      entity_id: id,
      payload: JSON.stringify({
        amountPaise: row.amount_paise,
        confirmedOnBehalf,
      }),
      created_at: now,
    });

    // Mark receiver notification DONE
    await notificationsStore.updateSettlementNotification(id, 'DONE', 'CONFIRMED', trx);

    // Notify sender
    await notificationsStore.create(
      {
        userId: row.from_user_id,
        type: 'SETTLEMENT_CONFIRMED',
        payload: {
          settlementId: id,
          ledgerId: row.ledger_id,
          amountPaise: row.amount_paise,
          receiverUserId: row.to_user_id,
        },
      },
      trx
    );

    const updatedBalances = await getLedgerBalancesFromDb(row.ledger_id, trx);
    const updatedRow = await trx('settlements').where({ id }).first();

    return {
      settlement: mapDbSettlementToModel(updatedRow),
      balances: updatedBalances,
    };
  });

  if (isOutdated) {
    const err = new SettlementOutdatedError(
      'Amount is no longer valid due to recent expenses or changes'
    );
    (err as any).settlement = result.settlement;
    (err as any).balances = result.balances;
    throw err;
  }

  return result;
}

export async function rejectSettlement(
  id: string,
  actorUserId: string
): Promise<{ settlement: Settlement; balances: Record<string, number> }> {
  return await db.transaction(async (trx) => {
    const row = await trx('settlements').where({ id }).forUpdate().first();
    if (!row) {
      throw new NotFoundError(`Settlement ${id} not found`);
    }

    if (row.status !== 'PENDING') {
      throw new ConflictError(
        `Settlement cannot be rejected (current status: ${row.status})`
      );
    }

    const dbToUser = await trx('users').where({ id: row.to_user_id }).first();
    const isReceiver = row.to_user_id === actorUserId;
    const isPlaceholder = dbToUser ? Boolean(dbToUser.is_placeholder) : false;
    const placeholderCreator = dbToUser?.created_by;
    const isPlaceholderCreator = isPlaceholder && placeholderCreator === actorUserId;

    if (!isReceiver && !isPlaceholderCreator) {
      throw new ForbiddenError('Only the receiver can reject this settlement');
    }

    const now = new Date();
    await trx('settlements').where({ id }).update({
      status: 'REJECTED',
      responded_by: actorUserId,
      responded_at: now,
    });

    await trx('settlement_events').insert({
      settlement_id: id,
      status: 'REJECTED',
      actor_user_id: actorUserId,
      created_at: now,
    });

    await trx('activity_log').insert({
      ledger_id: row.ledger_id,
      actor_user_id: actorUserId,
      action: 'SETTLEMENT_REJECTED',
      entity_type: 'settlement',
      entity_id: id,
      payload: JSON.stringify({
        amountPaise: row.amount_paise,
      }),
      created_at: now,
    });

    await notificationsStore.updateSettlementNotification(id, 'DONE', 'REJECTED', trx);

    await notificationsStore.create(
      {
        userId: row.from_user_id,
        type: 'SETTLEMENT_REJECTED',
        payload: {
          settlementId: id,
          ledgerId: row.ledger_id,
          amountPaise: row.amount_paise,
          receiverUserId: row.to_user_id,
        },
      },
      trx
    );

    const updatedBalances = await getLedgerBalancesFromDb(row.ledger_id, trx);
    const updatedRow = await trx('settlements').where({ id }).first();

    return {
      settlement: mapDbSettlementToModel(updatedRow),
      balances: updatedBalances,
    };
  });
}

export async function cancelSettlement(
  id: string,
  actorUserId: string
): Promise<{ settlement: Settlement; balances: Record<string, number> }> {
  return await db.transaction(async (trx) => {
    const row = await trx('settlements').where({ id }).forUpdate().first();
    if (!row) {
      throw new NotFoundError(`Settlement ${id} not found`);
    }

    if (row.status !== 'PENDING') {
      throw new ConflictError(
        `Settlement cannot be cancelled (current status: ${row.status})`
      );
    }

    if (row.from_user_id !== actorUserId) {
      throw new ForbiddenError('Only the sender can cancel a pending settlement');
    }

    const now = new Date();
    await trx('settlements').where({ id }).update({
      status: 'CANCELLED',
    });

    await trx('settlement_events').insert({
      settlement_id: id,
      status: 'CANCELLED',
      actor_user_id: actorUserId,
      created_at: now,
    });

    await trx('activity_log').insert({
      ledger_id: row.ledger_id,
      actor_user_id: actorUserId,
      action: 'SETTLEMENT_CANCELLED',
      entity_type: 'settlement',
      entity_id: id,
      created_at: now,
    });

    await notificationsStore.updateSettlementNotification(id, 'EXPIRED', undefined, trx);

    const updatedBalances = await getLedgerBalancesFromDb(row.ledger_id, trx);
    const updatedRow = await trx('settlements').where({ id }).first();

    return {
      settlement: mapDbSettlementToModel(updatedRow),
      balances: updatedBalances,
    };
  });
}

export async function resubmitSettlement(params: {
  id: string;
  actorUserId: string;
  newAmountPaise?: number;
}): Promise<{ settlement: Settlement; balances: Record<string, number> }> {
  const { id, actorUserId, newAmountPaise } = params;

  return await db.transaction(async (trx) => {
    const oldRow = await trx('settlements').where({ id }).forUpdate().first();
    if (!oldRow) {
      throw new NotFoundError(`Settlement ${id} not found`);
    }

    if (oldRow.from_user_id !== actorUserId) {
      throw new ForbiddenError('Only the sender can resubmit');
    }

    if (oldRow.status !== 'REJECTED' && oldRow.status !== 'OUTDATED') {
      throw new ConflictError('Only REJECTED or OUTDATED settlements can be resubmitted');
    }

    // Rule R7: Check current debt
    const balances = await getLedgerBalancesFromDb(oldRow.ledger_id, trx);
    const senderNet = balances[oldRow.from_user_id] || 0;
    const receiverNet = balances[oldRow.to_user_id] || 0;

    if (senderNet >= 0 || receiverNet <= 0) {
      throw new NothingDueError('No amount due anymore');
    }

    const maxAllowed = Math.min(-senderNet, receiverNet);
    const targetAmount = newAmountPaise !== undefined ? newAmountPaise : Math.min(oldRow.amount_paise, maxAllowed);

    if (targetAmount <= 0 || !Number.isInteger(targetAmount)) {
      throw new ValidationError('Resubmitted amount must be a positive integer in paise');
    }

    if (targetAmount > maxAllowed) {
      throw new ValidationError(
        `Amount (${targetAmount} paise) exceeds current balance owed (${maxAllowed} paise)`
      );
    }

    // 24-hour notification guard
    let suppressNotification = false;
    if (
      oldRow.status === 'REJECTED' &&
      oldRow.amount_paise === targetAmount &&
      oldRow.responded_at
    ) {
      const elapsedMs = Date.now() - new Date(oldRow.responded_at).getTime();
      if (elapsedMs < 24 * 60 * 60 * 1000) {
        suppressNotification = true;
      }
    }

    // Create new settlement
    const newId = `stl_${ulid()}`;
    const now = new Date();

    await trx('settlements').insert({
      id: newId,
      ledger_id: oldRow.ledger_id,
      from_user_id: oldRow.from_user_id,
      to_user_id: oldRow.to_user_id,
      amount_paise: targetAmount,
      method: oldRow.method,
      status: 'PENDING',
      offset_id: null,
      replaced_by_id: null,
      created_by: actorUserId,
      responded_by: null,
      confirmed_on_behalf: 0,
      reminder_count: 0,
      last_reminded_at: null,
      created_at: now,
      responded_at: null,
    });

    await trx('settlement_events').insert({
      settlement_id: newId,
      status: 'PENDING',
      actor_user_id: actorUserId,
      created_at: now,
    });

    await trx('activity_log').insert({
      ledger_id: oldRow.ledger_id,
      actor_user_id: actorUserId,
      action: 'SETTLEMENT_CREATED',
      entity_type: 'settlement',
      entity_id: newId,
      payload: JSON.stringify({
        amountPaise: targetAmount,
        fromUserId: oldRow.from_user_id,
        toUserId: oldRow.to_user_id,
        method: oldRow.method,
        confirmedOnBehalf: false,
        resubmittedFromId: oldRow.id,
      }),
      created_at: now,
    });

    // Link replaced_by_id on the old record
    await trx('settlements').where({ id: oldRow.id }).update({ replaced_by_id: newId });

    if (!suppressNotification) {
      await notificationsStore.create(
        {
          userId: oldRow.to_user_id,
          type: 'SETTLEMENT_REQUESTED',
          actionState: 'OPEN',
          payload: {
            settlementId: newId,
            ledgerId: oldRow.ledger_id,
            fromUserId: oldRow.from_user_id,
            toUserId: oldRow.to_user_id,
            amountPaise: targetAmount,
            method: oldRow.method,
          },
        },
        trx
      );
    }

    const updatedBalances = await getLedgerBalancesFromDb(oldRow.ledger_id, trx);
    const newRow = await trx('settlements').where({ id: newId }).first();

    return {
      settlement: mapDbSettlementToModel(newRow),
      balances: updatedBalances,
    };
  });
}

export async function listSettlementsForLedger(ledgerId: string): Promise<Settlement[]> {
  const rows = await db('settlements')
    .where({ ledger_id: ledgerId })
    .orderBy('created_at', 'desc');

  return rows.map(mapDbSettlementToModel);
}
