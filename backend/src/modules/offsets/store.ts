import { ulid } from 'ulidx';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { inMemoryUsers } from '../users/store.js';
import { calculateNetBalances } from '../balances/index.js';
import { inMemorySettlements, inMemorySettlementEvents, Settlement } from '../settlements/store.js';
import { notificationsStore } from '../notifications/store.js';
import { activityStore } from '../activity/store.js';
import {
  ValidationError,
  NotFoundError,
  ForbiddenError,
  SettlementOutdatedError,
  ConflictError,
} from '../../lib/errors.js';

export interface OffsetRecord {
  id: string;
  groupLedgerId: string;
  individualLedgerId: string;
  fromUserId: string; // The person who owes in GROUP and initiates
  toUserId: string;   // The creditor in GROUP who owes in INDIVIDUAL (receiver)
  amountPaise: number;
  status: 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'OUTDATED' | 'CANCELLED';
  createdBy: string;
  createdAt: string;
  respondedAt?: string | null;
}

export const inMemoryOffsets = new Map<string, OffsetRecord>();

function getIndividualLedgerId(userA: string, userB: string): string | null {
  for (const ledger of inMemoryLedgers.values()) {
    if (
      ledger.type === 'INDIVIDUAL' &&
      ledger.memberIds.length === 2 &&
      ledger.memberIds.includes(userA) &&
      ledger.memberIds.includes(userB)
    ) {
      return ledger.id;
    }
  }
  return null;
}

function getNetBalanceInLedger(ledgerId: string, userId: string): number {
  const ledger = inMemoryLedgers.get(ledgerId);
  if (!ledger) return 0;

  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter((s: any) => s.status === 'CONFIRMED');

  const netResult = calculateNetBalances(ledger.memberIds, activeExpenses, confirmedSettlements);
  return netResult.balances[userId] || 0;
}

export function getOffsetSuggestions(groupLedgerId: string, callerUserId: string) {
  const group = inMemoryLedgers.get(groupLedgerId);
  if (!group || group.type !== 'GROUP') {
    throw new NotFoundError(`Group ${groupLedgerId} not found`);
  }

  const suggestions: any[] = [];
  const groupNet = getNetBalanceInLedger(groupLedgerId, callerUserId);
  if (groupNet >= 0) {
    return suggestions; // Caller doesn't owe money in group overall
  }

  for (const memberId of group.memberIds) {
    if (memberId === callerUserId) continue;

    // Check individual ledger between caller and member
    const indLedgerId = getIndividualLedgerId(callerUserId, memberId);
    if (!indLedgerId) continue;

    const indNet = getNetBalanceInLedger(indLedgerId, callerUserId);
    // If indNet > 0, memberId owes callerUserId money individually!
    if (indNet > 0) {
      const groupDebt = Math.abs(groupNet); // Max owed in group
      const individualCredit = indNet;
      const maxOffsetPaise = Math.min(groupDebt, individualCredit);

      const user = inMemoryUsers.get(memberId);
      suggestions.push({
        toUserId: memberId,
        toUserName: user?.name || memberId,
        groupLedgerId,
        individualLedgerId: indLedgerId,
        groupDebtPaise: groupDebt,
        individualCreditPaise: individualCredit,
        maxOffsetPaise,
        remainingGroupDebtPaise: groupDebt - maxOffsetPaise,
      });
    }
  }

  return suggestions;
}

export function createOffset(params: {
  groupLedgerId: string;
  fromUserId: string;
  toUserId: string;
  amountPaise: number;
}): OffsetRecord {
  const { groupLedgerId, fromUserId, toUserId, amountPaise } = params;

  if (amountPaise <= 0 || !Number.isInteger(amountPaise)) {
    throw new ValidationError('Offset amount must be a positive integer in paise');
  }

  const group = inMemoryLedgers.get(groupLedgerId);
  if (!group || group.type !== 'GROUP') {
    throw new NotFoundError(`Group ledger ${groupLedgerId} not found`);
  }

  const indLedgerId = getIndividualLedgerId(fromUserId, toUserId);
  if (!indLedgerId) {
    throw new ValidationError('No individual ledger exists between these members');
  }

  const groupNet = getNetBalanceInLedger(groupLedgerId, fromUserId);
  if (groupNet >= 0) {
    throw new ValidationError('You do not owe money in this group');
  }
  const groupDebt = Math.abs(groupNet);

  const indNet = getNetBalanceInLedger(indLedgerId, fromUserId);
  if (indNet <= 0) {
    throw new ValidationError('The other member does not owe you money individually');
  }
  const individualCredit = indNet;

  const maxAllowed = Math.min(groupDebt, individualCredit);
  if (amountPaise > maxAllowed) {
    throw new ValidationError(
      `Offset amount (${amountPaise} paise) exceeds max available offset (${maxAllowed} paise)`
    );
  }

  const offsetId = `ofs_${ulid()}`;
  const now = new Date().toISOString();

  const offsetRecord: OffsetRecord = {
    id: offsetId,
    groupLedgerId,
    individualLedgerId: indLedgerId,
    fromUserId,
    toUserId,
    amountPaise,
    status: 'PENDING',
    createdBy: fromUserId,
    createdAt: now,
    respondedAt: null,
  };

  inMemoryOffsets.set(offsetId, offsetRecord);

  // Create Entry 1: In GROUP ledger (from caller to toUserId)
  const groupSettlementId = `stl_${ulid()}`;
  const groupSettlement: Settlement = {
    id: groupSettlementId,
    ledgerId: groupLedgerId,
    fromUserId,
    toUserId,
    amountPaise,
    method: 'OFFSET',
    status: 'PENDING',
    offsetId,
    confirmedOnBehalf: false,
    reminderCount: 0,
    createdBy: fromUserId,
    createdAt: now,
  };
  inMemorySettlements.set(groupSettlementId, groupSettlement);
  group.settlements.push(groupSettlement);

  // Create Entry 2: In INDIVIDUAL ledger (from toUserId to caller - opposite direction!)
  const indLedger = inMemoryLedgers.get(indLedgerId)!;
  const indSettlementId = `stl_${ulid()}`;
  const indSettlement: Settlement = {
    id: indSettlementId,
    ledgerId: indLedgerId,
    fromUserId: toUserId,
    toUserId: fromUserId,
    amountPaise,
    method: 'OFFSET',
    status: 'PENDING',
    offsetId,
    confirmedOnBehalf: false,
    reminderCount: 0,
    createdBy: fromUserId,
    createdAt: now,
  };
  inMemorySettlements.set(indSettlementId, indSettlement);
  indLedger.settlements.push(indSettlement);

  // Notify receiver
  notificationsStore.create({
    userId: toUserId,
    type: 'OFFSET_REQUESTED' as any,
    actionState: 'OPEN',
    payload: {
      offsetId,
      groupLedgerId,
      individualLedgerId: indLedgerId,
      fromUserId,
      amountPaise,
    },
  });

  return offsetRecord;
}

export function confirmOffset(offsetId: string, actorUserId: string): OffsetRecord {
  const offset = inMemoryOffsets.get(offsetId);
  if (!offset) {
    throw new NotFoundError(`Offset ${offsetId} not found`);
  }

  if (offset.status !== 'PENDING') {
    throw new ConflictError(`Offset cannot be confirmed (current status: ${offset.status})`);
  }

  if (offset.toUserId !== actorUserId) {
    throw new ForbiddenError('Only the receiver can confirm this offset');
  }

  // Re-check BOTH balances under lock (Rule: if either changed, OUTDATED!)
  const groupNet = getNetBalanceInLedger(offset.groupLedgerId, offset.fromUserId);
  const indNet = getNetBalanceInLedger(offset.individualLedgerId, offset.fromUserId);

  const groupStillValid = groupNet < 0 && Math.abs(groupNet) >= offset.amountPaise;
  const indStillValid = indNet > 0 && indNet >= offset.amountPaise;

  if (!groupStillValid || !indStillValid) {
    offset.status = 'OUTDATED';

    // Update both settlements to OUTDATED
    for (const stl of inMemorySettlements.values()) {
      if (stl.offsetId === offsetId) {
        stl.status = 'OUTDATED';
      }
    }

    notificationsStore.updateSettlementNotification(offsetId, 'EXPIRED');
    notificationsStore.create({
      userId: offset.fromUserId,
      type: 'SETTLEMENT_OUTDATED',
      payload: {
        offsetId,
        message: 'Offset is outdated because one or both balances changed',
      },
    });

    throw new SettlementOutdatedError(
      'Offset is outdated because one or both balances changed before confirmation'
    );
  }

  // Confirm atomically
  const now = new Date().toISOString();
  offset.status = 'CONFIRMED';
  offset.respondedAt = now;

  for (const stl of inMemorySettlements.values()) {
    if (stl.offsetId === offsetId) {
      stl.status = 'CONFIRMED';
      stl.respondedBy = actorUserId;
      stl.respondedAt = now;

      inMemorySettlementEvents.push({
        id: `sev_${ulid()}`,
        settlementId: stl.id,
        status: 'CONFIRMED',
        actorUserId,
        createdAt: now,
      });
    }
  }

  notificationsStore.create({
    userId: offset.fromUserId,
    type: 'OFFSET_RESULT' as any,
    payload: {
      offsetId,
      result: 'CONFIRMED',
      amountPaise: offset.amountPaise,
    },
  });

  return offset;
}

export function rejectOffset(offsetId: string, actorUserId: string): OffsetRecord {
  const offset = inMemoryOffsets.get(offsetId);
  if (!offset) {
    throw new NotFoundError(`Offset ${offsetId} not found`);
  }

  if (offset.status !== 'PENDING') {
    throw new ConflictError(`Offset cannot be rejected (current status: ${offset.status})`);
  }

  if (offset.toUserId !== actorUserId) {
    throw new ForbiddenError('Only the receiver can reject this offset');
  }

  const now = new Date().toISOString();
  offset.status = 'REJECTED';
  offset.respondedAt = now;

  for (const stl of inMemorySettlements.values()) {
    if (stl.offsetId === offsetId) {
      stl.status = 'REJECTED';
      stl.respondedBy = actorUserId;
      stl.respondedAt = now;

      inMemorySettlementEvents.push({
        id: `sev_${ulid()}`,
        settlementId: stl.id,
        status: 'REJECTED',
        actorUserId,
        createdAt: now,
      });
    }
  }

  notificationsStore.create({
    userId: offset.fromUserId,
    type: 'OFFSET_RESULT' as any,
    payload: {
      offsetId,
      result: 'REJECTED',
      amountPaise: offset.amountPaise,
    },
  });

  return offset;
}
