import crypto from 'node:crypto';
import { ulid } from 'ulidx';
import type { User, MergeSummary } from './types.js';
import { db } from '../../db/knex.js';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { calculateNetBalances } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';

export const inMemoryUsers = new Map<string, User>();
export type MergeHook = (placeholderId: string, realId: string) => void;
export const mergeHooks: MergeHook[] = [];

export function registerMergeHook(hook: MergeHook): void {
  mergeHooks.push(hook);
}

/**
 * SHA-256 + salt password hashing (fast, secure, zero external binary dependency)
 */
export function hashPassword(password: string): string {
  const salt = 'splitup_salt_v1';
  return crypto.createHash('sha256').update(`${salt}:${password}`).digest('hex');
}

export function verifyPassword(password: string, hash: string): boolean {
  return hashPassword(password) === hash;
}

function mapRowToUser(row: any): User {
  return {
    id: row.id,
    firebaseUid: row.firebase_uid || null,
    phoneE164: row.phone_e164,
    name: row.name,
    email: row.email || null,
    photoUrl: row.photo_url || null,
    passwordHash: row.password_hash || null,
    isPlaceholder: Boolean(row.is_placeholder),
    status: row.status as 'ACTIVE' | 'BLOCKED' | 'DELETED',
    createdBy: row.created_by || null,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
    updatedAt: row.updated_at instanceof Date ? row.updated_at.toISOString() : String(row.updated_at),
  };
}

export async function persistUserToDb(user: User): Promise<void> {
  await db('users')
    .insert({
      id: user.id,
      firebase_uid: user.firebaseUid || null,
      phone_e164: user.phoneE164,
      name: user.name,
      email: user.email || null,
      photo_url: user.photoUrl || null,
      password_hash: user.passwordHash || null,
      is_placeholder: user.isPlaceholder ? 1 : 0,
      status: user.status || 'ACTIVE',
      created_by: user.createdBy || null,
      created_at: new Date(user.createdAt),
      updated_at: new Date(user.updatedAt),
    })
    .onConflict('id')
    .merge();
}

// Seed default users for development and testing
export function getDefaultSeedUsers(): User[] {
  const defaultPw = hashPassword('password123');
  return [
    {
      id: 'usr_arhaam',
      firebaseUid: 'fb_arhaam',
      phoneE164: '+919876543210',
      name: 'Arhaam',
      email: 'arhaam@example.com',
      photoUrl: null,
      passwordHash: defaultPw,
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
      passwordHash: defaultPw,
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
      passwordHash: defaultPw,
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
      passwordHash: defaultPw,
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
      passwordHash: defaultPw,
      isPlaceholder: false,
      status: 'ACTIVE',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  ];
}

export function seedDefaultUsers(): void {
  const users = getDefaultSeedUsers();
  inMemoryUsers.clear();
  for (const u of users) {
    inMemoryUsers.set(u.id, u);
  }
}

// Initial in-memory seed (synchronous fallback)
seedDefaultUsers();

/**
 * Initializes the user store from MySQL.
 * Loads all existing registered accounts from Cloud MySQL into memory.
 * If the database has 0 users, seeds the default users and writes them to MySQL.
 */
export async function initUserStore(): Promise<void> {
  try {
    const rows = await db('users').whereNull('deleted_at').select('*');
    if (rows.length === 0) {
      console.log('[UserStore] No users found in MySQL. Seeding default demo accounts...');
      const seeds = getDefaultSeedUsers();
      for (const u of seeds) {
        await persistUserToDb(u);
        inMemoryUsers.set(u.id, u);
      }
      console.log(`[UserStore] Seeded ${seeds.length} users into Cloud MySQL.`);
    } else {
      inMemoryUsers.clear();
      for (const row of rows) {
        const u = mapRowToUser(row);
        inMemoryUsers.set(u.id, u);
      }
      console.log(`[UserStore] Successfully loaded ${inMemoryUsers.size} users from Cloud MySQL.`);
    }
  } catch (err) {
    console.error('[UserStore] Failed to connect or initialize from MySQL:', err);
  }
}

export function findUserById(id: string): User | undefined {
  return inMemoryUsers.get(id);
}

export async function findUserByIdAsync(id: string): Promise<User | undefined> {
  const cached = inMemoryUsers.get(id);
  if (cached) return cached;

  try {
    const row = await db('users').where({ id, deleted_at: null }).first();
    if (row) {
      const u = mapRowToUser(row);
      inMemoryUsers.set(u.id, u);
      return u;
    }
  } catch (err) {
    console.error(`[UserStore] DB lookup error for user ${id}:`, err);
  }
  return undefined;
}

export function findUserByPhone(phoneE164: string): User | undefined {
  for (const user of inMemoryUsers.values()) {
    if (user.phoneE164 === phoneE164) {
      return user;
    }
  }
  return undefined;
}

export async function findUserByPhoneAsync(phoneE164: string): Promise<User | undefined> {
  const cached = findUserByPhone(phoneE164);
  if (cached) return cached;

  try {
    const row = await db('users').where({ phone_e164: phoneE164, deleted_at: null }).first();
    if (row) {
      const u = mapRowToUser(row);
      inMemoryUsers.set(u.id, u);
      return u;
    }
  } catch (err) {
    console.error(`[UserStore] DB lookup error for phone ${phoneE164}:`, err);
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
  const id = data.id || ulid();
  const user: User = {
    id,
    ...data,
    createdAt: now,
    updatedAt: now,
  };
  inMemoryUsers.set(id, user);

  // Asynchronously persist to MySQL
  persistUserToDb(user).catch((err) => {
    console.error(`[UserStore] Failed to persist user ${id} to MySQL:`, err.message);
  });

  return user;
}

export async function createUserAsync(data: Omit<User, 'id' | 'createdAt' | 'updatedAt'> & { id?: string }): Promise<User> {
  const user = createUser(data);
  await persistUserToDb(user);
  return user;
}

export function updateUser(id: string, updates: Partial<Pick<User, 'name' | 'email' | 'photoUrl' | 'status' | 'firebaseUid' | 'passwordHash'>>): User | undefined {
  const existing = inMemoryUsers.get(id);
  if (!existing) return undefined;

  const updated: User = {
    ...existing,
    ...updates,
    updatedAt: new Date().toISOString(),
  };
  inMemoryUsers.set(id, updated);

  const dbUpdates: any = {
    updated_at: new Date(updated.updatedAt),
  };
  if (updates.name !== undefined) dbUpdates.name = updates.name;
  if (updates.email !== undefined) dbUpdates.email = updates.email;
  if (updates.photoUrl !== undefined) dbUpdates.photo_url = updates.photoUrl;
  if (updates.status !== undefined) dbUpdates.status = updates.status;
  if (updates.firebaseUid !== undefined) dbUpdates.firebase_uid = updates.firebaseUid;
  if (updates.passwordHash !== undefined) dbUpdates.password_hash = updates.passwordHash;

  db('users')
    .where({ id })
    .update(dbUpdates)
    .catch((err) => {
      console.error(`[UserStore] Failed to update user ${id} in MySQL:`, err.message);
    });

  return updated;
}

export async function updateUserAsync(id: string, updates: Partial<Pick<User, 'name' | 'email' | 'photoUrl' | 'status' | 'firebaseUid' | 'passwordHash'>>): Promise<User | undefined> {
  const updated = updateUser(id, updates);
  if (!updated) return undefined;

  const dbUpdates: any = {
    updated_at: new Date(updated.updatedAt),
  };
  if (updates.name !== undefined) dbUpdates.name = updates.name;
  if (updates.email !== undefined) dbUpdates.email = updates.email;
  if (updates.photoUrl !== undefined) dbUpdates.photo_url = updates.photoUrl;
  if (updates.status !== undefined) dbUpdates.status = updates.status;
  if (updates.firebaseUid !== undefined) dbUpdates.firebase_uid = updates.firebaseUid;
  if (updates.passwordHash !== undefined) dbUpdates.password_hash = updates.passwordHash;

  await db('users').where({ id }).update(dbUpdates);
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

      const sorted = [realId, otherId].sort();
      anyLedger.pair_low_user_id = sorted[0];
      anyLedger.pair_high_user_id = sorted[1];
    }

    // Check expenses in ledger
    for (const expense of ledger.expenses) {
      let isUserInvolved = false;

      if (expense.createdBy === placeholderId) {
        expense.createdBy = realId;
      }

      for (const payer of expense.payers) {
        if (payer.userId === placeholderId) {
          payer.userId = realId;
          isUserInvolved = true;
        }
      }
      const combinedPayers = new Map<string, number>();
      for (const payer of expense.payers) {
        combinedPayers.set(payer.userId, (combinedPayers.get(payer.userId) || 0) + payer.paidPaise);
      }
      expense.payers = Array.from(combinedPayers.entries()).map(([userId, paidPaise]) => ({ userId, paidPaise }));

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
  db('users')
    .where({ id: placeholderId })
    .delete()
    .catch((err) => {
      console.error(`[UserStore] Error deleting placeholder ${placeholderId} in MySQL:`, err.message);
    });

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
