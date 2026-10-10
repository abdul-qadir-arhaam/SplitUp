import { ulid } from 'ulidx';

export interface ActivityLogItem {
  id: string;
  ledgerId: string;
  actorUserId: string;
  action: string; // EXPENSE_CREATED, EXPENSE_EDITED, EXPENSE_DELETED, EXPENSE_DISPUTED, SETTLEMENT_CREATED, SETTLEMENT_CONFIRMED, SETTLEMENT_REJECTED, SETTLEMENT_OUTDATED, SETTLEMENT_CANCELLED
  entityType: 'expense' | 'settlement' | 'ledger' | 'member';
  entityId?: string | null;
  payload?: any;
  createdAt: string;
}

export interface DisputeItem {
  id: string;
  expenseId: string;
  raisedBy: string;
  createdAt: string;
}

class ActivityStore {
  private activities: ActivityLogItem[] = [];
  private disputes: DisputeItem[] = [];

  log(data: {
    ledgerId: string;
    actorUserId: string;
    action: string;
    entityType: 'expense' | 'settlement' | 'ledger' | 'member';
    entityId?: string | null;
    payload?: any;
  }): ActivityLogItem {
    const item: ActivityLogItem = {
      id: `act_${ulid()}`,
      ledgerId: data.ledgerId,
      actorUserId: data.actorUserId,
      action: data.action,
      entityType: data.entityType,
      entityId: data.entityId || null,
      payload: data.payload || null,
      createdAt: new Date().toISOString(),
    };
    this.activities.push(item);
    return item;
  }

  listForLedger(ledgerId: string): ActivityLogItem[] {
    return this.activities
      .filter((a) => a.ledgerId === ledgerId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  listForExpense(expenseId: string): ActivityLogItem[] {
    return this.activities
      .filter((a) => a.entityType === 'expense' && a.entityId === expenseId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  createDispute(expenseId: string, raisedBy: string): DisputeItem {
    const existing = this.disputes.find(
      (d) => d.expenseId === expenseId && d.raisedBy === raisedBy
    );
    if (existing) {
      return existing;
    }
    const dispute: DisputeItem = {
      id: `dsp_${ulid()}`,
      expenseId,
      raisedBy,
      createdAt: new Date().toISOString(),
    };
    this.disputes.push(dispute);
    return dispute;
  }

  isExpenseDisputed(expenseId: string): boolean {
    return this.disputes.some((d) => d.expenseId === expenseId);
  }

  listDisputesForExpense(expenseId: string): DisputeItem[] {
    return this.disputes.filter((d) => d.expenseId === expenseId);
  }

  clear(): void {
    this.activities = [];
    this.disputes = [];
  }
}

export const activityStore = new ActivityStore();
