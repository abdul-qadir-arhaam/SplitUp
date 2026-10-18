import { ulid } from 'ulidx';
import type { Knex } from 'knex';
import { db } from '../../db/knex.js';

export type NotificationType =
  | 'FRIEND_ADDED'
  | 'FRIEND_JOINED'
  | 'ADDED_TO_GROUP'
  | 'ADDED_TO_TRIP'
  | 'EXPENSE_ADDED'
  | 'EXPENSE_DISPUTED'
  | 'SETTLEMENT_REQUEST'
  | 'SETTLEMENT_REQUESTED'
  | 'SETTLEMENT_CONFIRMED'
  | 'SETTLEMENT_REJECTED'
  | 'SETTLEMENT_OUTDATED'
  | 'TRIP_BUDGET_WARNING'
  | 'TRIP_BUDGET_EXCEEDED';

export type NotificationActionState = 'OPEN' | 'DONE' | 'EXPIRED';

export interface NotificationItem {
  id: string;
  userId: string;
  type: NotificationType;
  payload: Record<string, any>;
  actionState?: NotificationActionState | null;
  actionResult?: string | null;
  readAt: string | null;
  createdAt: string;
}

export function mapDbNotificationToModel(row: any): NotificationItem {
  let payloadObj: Record<string, any> = {};
  try {
    payloadObj = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
  } catch (_) {}

  return {
    id: row.id,
    userId: row.user_id,
    type: row.type as NotificationType,
    payload: payloadObj,
    actionState: row.action_state || null,
    actionResult: row.action_result || null,
    readAt: row.read_at instanceof Date ? row.read_at.toISOString() : (row.read_at ? String(row.read_at) : null),
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
  };
}

class NotificationsStore {
  async create(
    data: {
      userId: string;
      type: NotificationType;
      payload: Record<string, any>;
      actionState?: NotificationActionState | null;
    },
    trxOrDb: Knex | Knex.Transaction = db
  ): Promise<NotificationItem> {
    const id = `notif_${ulid()}`;
    const now = new Date();
    const notif: NotificationItem = {
      id,
      userId: data.userId,
      type: data.type,
      payload: data.payload,
      actionState: data.actionState || null,
      actionResult: null,
      readAt: null,
      createdAt: now.toISOString(),
    };

    await trxOrDb('notifications').insert({
      id: notif.id,
      user_id: notif.userId,
      type: notif.type,
      payload: JSON.stringify(notif.payload || {}),
      action_state: notif.actionState || null,
      action_result: null,
      read_at: null,
      created_at: now,
    });

    return notif;
  }

  async listForUser(userId: string, trxOrDb: Knex | Knex.Transaction = db): Promise<NotificationItem[]> {
    const rows = await trxOrDb('notifications')
      .where({ user_id: userId })
      .orderBy('created_at', 'desc');

    return rows.map(mapDbNotificationToModel);
  }

  async getUnreadCount(userId: string, trxOrDb: Knex | Knex.Transaction = db): Promise<number> {
    const row = await trxOrDb('notifications')
      .where({ user_id: userId })
      .whereNull('read_at')
      .count<{ count: number | string }>('id as count')
      .first();

    return Number(row?.count || 0);
  }

  async markRead(id: string, userId: string, trxOrDb: Knex | Knex.Transaction = db): Promise<boolean> {
    const updated = await trxOrDb('notifications')
      .where({ id, user_id: userId })
      .update({ read_at: new Date() });

    return updated > 0;
  }

  async markAllRead(userId: string, trxOrDb: Knex | Knex.Transaction = db): Promise<void> {
    await trxOrDb('notifications')
      .where({ user_id: userId })
      .whereNull('read_at')
      .update({ read_at: new Date() });
  }

  async updateActionState(
    id: string,
    actionState: NotificationActionState,
    actionResult?: string,
    trxOrDb: Knex | Knex.Transaction = db
  ): Promise<boolean> {
    const updateData: Record<string, any> = {
      action_state: actionState,
    };
    if (actionResult !== undefined) {
      updateData.action_result = actionResult;
    }

    const updated = await trxOrDb('notifications')
      .where({ id })
      .update(updateData);

    return updated > 0;
  }

  async updateSettlementNotification(
    settlementId: string,
    actionState: NotificationActionState,
    actionResult?: string,
    trxOrDb: Knex | Knex.Transaction = db
  ): Promise<void> {
    const updateData: Record<string, any> = {
      action_state: actionState,
    };
    if (actionResult !== undefined) {
      updateData.action_result = actionResult;
    }

    await trxOrDb('notifications')
      .whereRaw("JSON_UNQUOTE(JSON_EXTRACT(payload, '$.settlementId')) = ?", [settlementId])
      .update(updateData);
  }

  async dismiss(id: string, userId: string, trxOrDb: Knex | Knex.Transaction = db): Promise<boolean> {
    const deleted = await trxOrDb('notifications')
      .where({ id, user_id: userId })
      .delete();

    return deleted > 0;
  }

  async dismissAll(userId: string, trxOrDb: Knex | Knex.Transaction = db): Promise<void> {
    await trxOrDb('notifications')
      .where({ user_id: userId })
      .delete();
  }

  clear(): void {
    // No-op in MySQL backed store
  }
}

export const notificationsStore = new NotificationsStore();

export async function initNotificationsStore(): Promise<void> {
  // Database is the sole source of truth; no need to load into in-memory array
}
