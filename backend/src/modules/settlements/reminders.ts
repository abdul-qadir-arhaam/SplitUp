import { db } from '../../db/knex.js';
import { notificationsStore } from '../notifications/store.js';

export async function runSettlementRemindersJob(daysThreshold = 2): Promise<{ remindedCount: number }> {
  let remindedCount = 0;
  const now = Date.now();
  const thresholdMs = daysThreshold * 24 * 60 * 60 * 1000;

  const pendingSettlements = await db('settlements')
    .where({ status: 'PENDING' });

  for (const row of pendingSettlements) {
    const baseTime = row.last_reminded_at
      ? new Date(row.last_reminded_at).getTime()
      : new Date(row.created_at).getTime();

    if (now - baseTime >= thresholdMs) {
      const newReminderCount = Number(row.reminder_count || 0) + 1;
      const remindedAt = new Date();

      await db('settlements')
        .where({ id: row.id })
        .update({
          reminder_count: newReminderCount,
          last_reminded_at: remindedAt,
        });

      remindedCount += 1;

      // Send reminder notification
      await notificationsStore.create({
        userId: row.to_user_id,
        type: 'SETTLEMENT_REQUESTED',
        actionState: 'OPEN',
        payload: {
          settlementId: row.id,
          ledgerId: row.ledger_id,
          fromUserId: row.from_user_id,
          toUserId: row.to_user_id,
          amountPaise: Number(row.amount_paise),
          isReminder: true,
          reminderCount: newReminderCount,
        },
      });
    }
  }

  return { remindedCount };
}
