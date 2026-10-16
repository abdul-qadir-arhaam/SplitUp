import { ulid } from 'ulidx';
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

class NotificationsStore {
  private items = new Map<string, NotificationItem>();

  loadFromRows(rows: any[]): void {
    for (const row of rows) {
      let payloadObj = {};
      try {
        payloadObj = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
      } catch (_) {}

      const notif: NotificationItem = {
        id: row.id,
        userId: row.user_id,
        type: row.type as NotificationType,
        payload: payloadObj,
        actionState: row.action_state || null,
        actionResult: row.action_result || null,
        readAt: row.read_at instanceof Date ? row.read_at.toISOString() : (row.read_at ? String(row.read_at) : null),
        createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
      };
      this.items.set(notif.id, notif);
    }
  }

  create(data: {
    userId: string;
    type: NotificationType;
    payload: Record<string, any>;
    actionState?: NotificationActionState | null;
  }): NotificationItem {
    const id = `notif_${ulid()}`;
    const notif: NotificationItem = {
      id,
      userId: data.userId,
      type: data.type,
      payload: data.payload,
      actionState: data.actionState || null,
      actionResult: null,
      readAt: null,
      createdAt: new Date().toISOString(),
    };
    this.items.set(id, notif);

    // Asynchronously persist to MySQL
    db('notifications')
      .insert({
        id: notif.id,
        user_id: notif.userId,
        type: notif.type,
        payload: JSON.stringify(notif.payload || {}),
        action_state: notif.actionState || null,
        action_result: null,
        read_at: null,
        created_at: new Date(notif.createdAt),
      })
      .catch((err) => console.error('[NotificationsStore] Error inserting to MySQL:', err));

    return notif;
  }

  listForUser(userId: string): NotificationItem[] {
    const list: NotificationItem[] = [];
    for (const item of this.items.values()) {
      if (item.userId === userId) {
        list.push(item);
      }
    }
    return list.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  getUnreadCount(userId: string): number {
    let count = 0;
    for (const item of this.items.values()) {
      if (item.userId === userId && item.readAt === null) {
        count++;
      }
    }
    return count;
  }

  markRead(id: string, userId: string): boolean {
    const item = this.items.get(id);
    if (item && item.userId === userId) {
      item.readAt = new Date().toISOString();
      db('notifications')
        .where({ id, user_id: userId })
        .update({ read_at: new Date(item.readAt) })
        .catch((err) => console.error('[NotificationsStore] Error updating read_at in MySQL:', err));
      return true;
    }
    return false;
  }

  markAllRead(userId: string): void {
    const now = new Date().toISOString();
    for (const item of this.items.values()) {
      if (item.userId === userId && item.readAt === null) {
        item.readAt = now;
      }
    }
    db('notifications')
      .where({ user_id: userId })
      .whereNull('read_at')
      .update({ read_at: new Date(now) })
      .catch((err) => console.error('[NotificationsStore] Error marking all read in MySQL:', err));
  }

  updateActionState(
    id: string,
    actionState: NotificationActionState,
    actionResult?: string
  ): boolean {
    const item = this.items.get(id);
    if (item) {
      item.actionState = actionState;
      if (actionResult !== undefined) {
        item.actionResult = actionResult;
      }
      db('notifications')
        .where({ id })
        .update({
          action_state: actionState,
          action_result: actionResult || null,
        })
        .catch((err) => console.error('[NotificationsStore] Error updating action in MySQL:', err));
      return true;
    }
    return false;
  }

  updateSettlementNotification(
    settlementId: string,
    actionState: NotificationActionState,
    actionResult?: string
  ): void {
    for (const item of this.items.values()) {
      if (item.payload?.settlementId === settlementId) {
        item.actionState = actionState;
        if (actionResult !== undefined) {
          item.actionResult = actionResult;
        }
      }
    }
    db('notifications')
      .whereRaw("JSON_UNQUOTE(JSON_EXTRACT(payload, '$.settlementId')) = ?", [settlementId])
      .update({
        action_state: actionState,
        action_result: actionResult || null,
      })
      .catch((err) => console.error('[NotificationsStore] Error updating settlement notification in MySQL:', err));
  }

  dismiss(id: string, userId: string): boolean {
    const item = this.items.get(id);
    if (item && item.userId === userId) {
      this.items.delete(id);
      db('notifications')
        .where({ id, user_id: userId })
        .delete()
        .catch((err) => console.error('[NotificationsStore] Error deleting notification from MySQL:', err));
      return true;
    }
    return false;
  }

  dismissAll(userId: string): void {
    for (const [id, item] of this.items.entries()) {
      if (item.userId === userId) {
        this.items.delete(id);
      }
    }
    db('notifications')
      .where({ user_id: userId })
      .delete()
      .catch((err) => console.error('[NotificationsStore] Error deleting all notifications from MySQL:', err));
  }

  clear(): void {
    this.items.clear();
  }
}

export const notificationsStore = new NotificationsStore();

export async function initNotificationsStore(): Promise<void> {
  try {
    const rows = await db('notifications').select('*').orderBy('created_at', 'desc').limit(1000);
    notificationsStore.loadFromRows(rows);
    console.log(`[NotificationsStore] Loaded ${rows.length} notifications from Cloud MySQL.`);
  } catch (err) {
    console.error('[NotificationsStore] Error initializing from MySQL:', err);
  }
}
