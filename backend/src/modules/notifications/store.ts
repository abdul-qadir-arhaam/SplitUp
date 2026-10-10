import { ulid } from 'ulidx';

export type NotificationType =
  | 'FRIEND_ADDED'
  | 'FRIEND_JOINED'
  | 'EXPENSE_ADDED'
  | 'EXPENSE_DISPUTED'
  | 'SETTLEMENT_REQUEST'
  | 'SETTLEMENT_REQUESTED'
  | 'SETTLEMENT_CONFIRMED'
  | 'SETTLEMENT_REJECTED'
  | 'SETTLEMENT_OUTDATED';

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
  }

  clear(): void {
    this.items.clear();
  }
}

export const notificationsStore = new NotificationsStore();
