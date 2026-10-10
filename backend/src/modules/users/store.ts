import { ulid } from 'ulidx';
import type { User, MergeSummary } from './types.js';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { calculateNetBalances } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';

export const inMemoryUsers = new Map<string, User>();
export type MergeHook = (placeholderId: string, realId: string) => void;
export const mergeHooks: MergeHook[] = [];

export function registerMergeHook(hook: MergeHook): void {
  mergeHooks.push(hook);
}

// Seed default users for development and testing
export function seedDefaultUsers(): void {
  const users: User[] = [
    {
      id: 'usr_arhaam',
      firebaseUid: 'fb_arhaam',
      phoneE164: '+919876543210',
      name: 'Arhaam',
      email: 'arhaam@example.com',
      photoUrl: null,
      isPlaceholder: false,
      status: 'ACTIVE',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    {
      id: 'usr_rahul',
      firebaseUid: 'fb_rahul',
      phoneE164: '+919876543211',
      name: 'Rahul',
      email: 'rahul@example.com',
      photoUrl: null,
      isPlaceholder: false,
      status: 'ACTIVE',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    {
      id: 'usr_priya',
      firebaseUid: 'fb_priya',
      phoneE164: '+919876543212',
      name: 'Priya',
      email: 'priya@example.com',
      photoUrl: null,
      isPlaceholder: false,
      status: 'ACTIVE',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    {
      id: 'usr_amit',
      firebaseUid: 'fb_amit',
      phoneE164: '+919876543213',
      name: 'Amit',
      email: null,
      photoUrl: null,
      isPlaceholder: false,
      status: 'ACTIVE',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    {
      id: 'usr_sneha',
      firebaseUid: 'fb_sneha',
      phoneE164: '+919876543214',
      name: 'Sneha',
      email: null,
      photoUrl: null,
      isPlaceholder: false,
      status: 'ACTIVE',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  ];

  inMemoryUsers.clear();
  for (const u of users) {
    inMemoryUsers.set(u.id, u);
  }
}

// Initial seed
seedDefaultUsers();

export function findUserById(id: string): User | undefined {
  return inMemoryUsers.get(id);
}

export function findUserByPhone(phoneE164: string): User | undefined {
  for (const user of inMemoryUsers.values()) {
    if (user.phoneE164 === phoneE164) {
      return user;
    }
  }
  return undefined;
}

export function findUserByFirebaseUid(uid: string): User | undefined {
  for (const user of inMemoryUsers.values()) {
    if (user.firebaseUid === uid) {
      return user;
    }
  }
  return undefined;
}

export function createUser(data: Omit<User, 'id' | 'createdAt' | 'updatedAt'> & { id?: string }): User {
  const now = new Date().toISOString();
  const id = data.id || `usr_${ulid()}`;
  const user: User = {
    id,
    ...data,
    createdAt: now,
    updatedAt: now,
  };
  inMemoryUsers.set(id, user);
  return user;
}

export function updateUser(id: string, updates: Partial<Pick<User, 'name' | 'email' | 'photoUrl' | 'status' | 'firebaseUid'>>): User | undefined {
  const existing = inMemoryUsers.get(id);
  if (!existing) return undefined;

  const updated: User = {
    ...existing,
    ...updates,
    updatedAt: new Date().toISOString(),
  };
  inMemoryUsers.set(id, updated);
  return updated;
}

/**
 * 6-step placeholder merge as defined in DATABASE.md Section 5.1
 */
export function mergePlaceholder(placeholder: User, realUser: User): MergeSummary {
  const placeholderId = placeholder.id;
  const realId = realUser.id;
  const affectedLedgerIds = new Set<string>();
  let expenseCount = 0;
  let totalPaise = 0;

  // 1. Re-point ledger references & update ledgers
  for (const [ledgerId, ledger] of inMemoryLedgers.entries()) {
    let affected = false;

    // Check membership
    if (ledger.memberIds.includes(placeholderId)) {
      affected = true;
      affectedLedgerIds.add(ledgerId);
      // Remove placeholder, keep real if already member or add real
      ledger.memberIds = ledger.memberIds.filter((m) => m !== placeholderId);
      if (!ledger.memberIds.includes(realId)) {
        ledger.memberIds.push(realId);
      }
    }

    // Check individual ledger pair IDs
    const anyLedger = ledger as any;
    if (anyLedger.pair_low_user_id === placeholderId || anyLedger.pair_high_user_id === placeholderId) {
      affected = true;
      affectedLedgerIds.add(ledgerId);
      const otherId = anyLedger.pair_low_user_id === placeholderId 
        ? anyLedger.pair_high_user_id 
        : anyLedger.pair_low_user_id;

      // Re-order pair_low < pair_high
      const sorted = [realId, otherId].sort();
      anyLedger.pair_low_user_id = sorted[0];
      anyLedger.pair_high_user_id = sorted[1];
    }

    // Check expenses in ledger
    for (const expense of ledger.expenses) {
      let isUserInvolved = false;

      // Expense createdBy
      if (expense.createdBy === placeholderId) {
        expense.createdBy = realId;
      }

      // Payers
      for (const payer of expense.payers) {
        if (payer.userId === placeholderId) {
          payer.userId = realId;
          isUserInvolved = true;
        }
      }
      // Combine duplicates if real was already a payer
      const combinedPayers = new Map<string, number>();
      for (const payer of expense.payers) {
        combinedPayers.set(payer.userId, (combinedPayers.get(payer.userId) || 0) + payer.paidPaise);
      }
      expense.payers = Array.from(combinedPayers.entries()).map(([userId, paidPaise]) => ({ userId, paidPaise }));

      // Splits
      if (expense.splits) {
        for (const split of expense.splits) {
          if (split.userId === placeholderId) {
            split.userId = realId;
            isUserInvolved = true;
          }
        }
        const combinedSplits = new Map<string, any>();
        for (const split of expense.splits) {
          if (combinedSplits.has(split.userId)) {
            const existing = combinedSplits.get(split.userId);
            existing.owedPaise += split.owedPaise;
          } else {
            combinedSplits.set(split.userId, { ...split });
          }
        }
        expense.splits = Array.from(combinedSplits.values());
      }

      if (isUserInvolved) {
        expenseCount++;
        totalPaise += expense.totalPaise;
      }
    }

    // Check settlements in ledger
    for (const settlement of ledger.settlements) {
      if (settlement.fromUserId === placeholderId) settlement.fromUserId = realId;
      if (settlement.toUserId === placeholderId) settlement.toUserId = realId;
      if (settlement.createdBy === placeholderId) settlement.createdBy = realId;
      if (settlement.respondedBy === placeholderId) settlement.respondedBy = realId;
    }

    // If affected, verify zero-sum invariant holds!
    if (affected) {
      const netResult = calculateNetBalances(ledger.memberIds, ledger.expenses, ledger.settlements);
      const sum = Object.values(netResult.balances).reduce((a, b) => a + b, 0);
      if (sum !== 0) {
        throw new Error(`Zero-sum invariant violated after merge in ledger ${ledgerId}: sum = ${sum}`);
      }
    }
  }

  // 2. Repoint friendships synchronously via registered hooks
  for (const hook of mergeHooks) {
    hook(placeholderId, realId);
  }

  // 3. Keep real user's name if not empty
  if (!realUser.name || realUser.name.trim() === '') {
    updateUser(realId, { name: placeholder.name });
  }

  // 4. Delete the placeholder row
  inMemoryUsers.delete(placeholderId);

  // 5. Write notification for inviter
  if (placeholder.createdBy && placeholder.createdBy !== realId) {
    notificationsStore.create({
      userId: placeholder.createdBy,
      type: 'FRIEND_JOINED',
      payload: {
        friendId: realId,
        friendName: realUser.name,
        phone: realUser.phoneE164,
      },
    });
  }

  return {
    merged: true,
    placeholderId,
    realUserId: realId,
    expenseCount,
    totalPaise,
    affectedLedgerIds: Array.from(affectedLedgerIds),
  };
}
