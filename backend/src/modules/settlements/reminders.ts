import { inMemorySettlements } from './store.js';
import { notificationsStore } from '../notifications/store.js';

export function runSettlementRemindersJob(daysThreshold = 2): { remindedCount: number } {
  let remindedCount = 0;
  const now = Date.now();
  const thresholdMs = daysThreshold * 24 * 60 * 60 * 1000;

  for (const settlement of inMemorySettlements.values()) {
    if (settlement.status !== 'PENDING') continue;

    const baseTime = settlement.lastRemindedAt
      ? new Date(settlement.lastRemindedAt).getTime()
      : new Date(settlement.createdAt).getTime();

    if (now - baseTime >= thresholdMs) {
      settlement.reminderCount += 1;
      settlement.lastRemindedAt = new Date().toISOString();
      remindedCount += 1;

      // Send reminder notification
      notificationsStore.create({
        userId: settlement.toUserId,
        type: 'SETTLEMENT_REQUESTED',
        actionState: 'OPEN',
        payload: {
          settlementId: settlement.id,
          ledgerId: settlement.ledgerId,
          fromUserId: settlement.fromUserId,
          toUserId: settlement.toUserId,
          amountPaise: settlement.amountPaise,
          isReminder: true,
          reminderCount: settlement.reminderCount,
        },
      });
    }
  }

  return { remindedCount };
}
