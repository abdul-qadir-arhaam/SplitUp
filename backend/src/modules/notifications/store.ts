import { ulid } from 'ulidx';

export interface NotificationItem {
  id: string;
  userId: string;
  type: 'FRIEND_ADDED' | 'FRIEND_JOINED' | 'EXPENSE_ADDED' | 'SETTLEMENT_REQUEST' | 'SETTLEMENT_CONFIRMED';
  payload: Record<string, any>;
  readAt: string | null;
  createdAt: string;
}

class NotificationsStore {
  private items = new Map<string, NotificationItem>();

  create(data: { userId: string; type: NotificationItem['type']; payload: Record<string, any> }): NotificationItem {
    const id = `notif_${ulid()}`;
    const notif: NotificationItem = {
      id,
      userId: data.userId,
      type: data.type,
      payload: data.payload,
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

  clear(): void {
    this.items.clear();
  }
}

export const notificationsStore = new NotificationsStore();
