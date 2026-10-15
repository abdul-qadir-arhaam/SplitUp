import { ulid } from 'ulidx';
import { db } from '../../db/knex.js';
import { inMemoryUsers, findUserById, findUserByPhone, createUser, registerMergeHook } from '../users/store.js';
import { normalizePhoneE164 } from '../users/phone.js';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { calculateNetBalances } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';
import { ValidationError, NotFoundError, ConflictError, UnsettledBalanceError } from '../../lib/errors.js';
import { getCommonGroupsForUsers } from '../groups/store.js';

export interface Friendship {
  ownerUserId: string;
  friendUserId: string;
  individualLedgerId: string;
  nickname: string | null;
  contactName: string | null;
  createdAt: string;
  removedAt: string | null;
}

export const inMemoryFriendships = new Map<string, Friendship>();
export const inMemoryBlocks = new Set<string>(); // "blocker:blocked"

function key(ownerId: string, friendId: string): string {
  return `${ownerId}:${friendId}`;
}

async function persistFriendshipToDb(f: Friendship): Promise<void> {
  try {
    await db('friendships')
      .insert({
        owner_user_id: f.ownerUserId,
        friend_user_id: f.friendUserId,
        individual_ledger_id: f.individualLedgerId,
        nickname: f.nickname || null,
        contact_name: f.contactName || null,
        created_at: new Date(f.createdAt),
        removed_at: f.removedAt ? new Date(f.removedAt) : null,
      })
      .onConflict(['owner_user_id', 'friend_user_id'])
      .merge();
  } catch (err) {
    console.error('[FriendsStore] Error persisting friendship to MySQL:', err);
  }
}

/**
 * Creates or retrieves the single authoritative individual ledger for two users.
 * Respects DATABASE.md pair_low_user_id and pair_high_user_id constraints.
 */
export async function getOrCreateIndividualLedger(userA: string, userB: string, createdBy: string): Promise<string> {
  const [low, high] = [userA, userB].sort();

  // Search existing individual ledger in memory
  for (const ledger of inMemoryLedgers.values()) {
    const anyLedger = ledger as any;
    if (
      ledger.type === 'INDIVIDUAL' &&
      ((anyLedger.pair_low_user_id === low && anyLedger.pair_high_user_id === high) ||
        (ledger.memberIds.length === 2 && ledger.memberIds.includes(userA) && ledger.memberIds.includes(userB)))
    ) {
      return ledger.id;
    }
  }

  // Create new individual ledger
  const id = `ldg_${ulid()}`;
  const userAName = inMemoryUsers.get(userA)?.name || 'User A';
  const userBName = inMemoryUsers.get(userB)?.name || 'User B';

  inMemoryLedgers.set(id, {
    id,
    name: `${userAName} & ${userBName}`,
    type: 'INDIVIDUAL',
    memberIds: [low, high],
    expenses: [],
    settlements: [],
    ...( { pair_low_user_id: low, pair_high_user_id: high, created_by: createdBy } as any ),
  });

  // Await persist ledger to MySQL
  try {
    await db('ledgers')
      .insert({
        id,
        type: 'INDIVIDUAL',
        name: `${userAName} & ${userBName}`,
        status: 'ACTIVE',
        pair_low_user_id: low,
        pair_high_user_id: high,
        created_by: createdBy,
        created_at: new Date(),
        updated_at: new Date(),
      })
      .onConflict('id')
      .ignore();

    await db('ledger_members').insert([
      { ledger_id: id, user_id: low, role: 'MEMBER', joined_at: new Date() },
      { ledger_id: id, user_id: high, role: 'MEMBER', joined_at: new Date() },
    ]).onConflict(['ledger_id', 'user_id']).ignore();
  } catch (err) {
    console.error('[FriendsStore] Error creating individual ledger in MySQL:', err);
  }

  return id;
}

export function listFriends(ownerUserId: string) {
  const results: any[] = [];

  for (const f of inMemoryFriendships.values()) {
    if (f.ownerUserId === ownerUserId && f.removedAt === null) {
      const friendUser = inMemoryUsers.get(f.friendUserId);
      if (!friendUser) continue;

      // Net balance in individual ledger
      let netPaise = 0;
      const ledger = inMemoryLedgers.get(f.individualLedgerId);
      if (ledger) {
        const netResult = calculateNetBalances(ledger.memberIds, ledger.expenses, ledger.settlements);
        netPaise = netResult.balances[ownerUserId] || 0;
      }

      results.push({
        friendId: friendUser.id,
        name: friendUser.name,
        phoneE164: friendUser.phoneE164,
        photoUrl: friendUser.photoUrl,
        isAppUser: !friendUser.isPlaceholder,
        nickname: f.nickname,
        contactName: f.contactName,
        individualLedgerId: f.individualLedgerId,
        netPaise, // positive: friend owes me; negative: I owe friend
        commonGroups: getCommonGroupsForUsers(ownerUserId, friendUser.id),
      });
    }
  }

  return results;
}

export async function addFriend(params: {
  ownerUserId: string;
  phone: string;
  name?: string;
  contactName?: string;
}) {
  const { ownerUserId, name, contactName } = params;
  const owner = findUserById(ownerUserId);
  if (!owner) throw new NotFoundError('Current user not found');

  const normalizedPhone = normalizePhoneE164(params.phone);
  if (owner.phoneE164 === normalizedPhone) {
    throw new ValidationError('You cannot add yourself as a friend');
  }

  // Check if target user exists
  let targetUser = findUserByPhone(normalizedPhone);
  const isAppUser = targetUser ? !targetUser.isPlaceholder : false;

  if (targetUser) {
    const existing = inMemoryFriendships.get(key(ownerUserId, targetUser.id));
    if (existing && existing.removedAt === null) {
      throw new ConflictError('Friend already added');
    }
  } else {
    // Create placeholder user in memory & DB
    targetUser = createUser({
      phoneE164: normalizedPhone,
      name: name || normalizedPhone,
      isPlaceholder: true,
      status: 'ACTIVE',
      createdBy: ownerUserId,
    });
  }

  const ledgerId = await getOrCreateIndividualLedger(ownerUserId, targetUser.id, ownerUserId);
  const now = new Date().toISOString();

  // Create or restore friendship for owner
  const ownerFriendship: Friendship = {
    ownerUserId,
    friendUserId: targetUser.id,
    individualLedgerId: ledgerId,
    nickname: null,
    contactName: contactName || null,
    createdAt: now,
    removedAt: null,
  };
  inMemoryFriendships.set(key(ownerUserId, targetUser.id), ownerFriendship);
  await persistFriendshipToDb(ownerFriendship);

  // If real app user, create reciprocal friendship and in-app notification
  if (isAppUser) {
    const reciprocalFriendship: Friendship = {
      ownerUserId: targetUser.id,
      friendUserId: ownerUserId,
      individualLedgerId: ledgerId,
      nickname: null,
      contactName: null,
      createdAt: now,
      removedAt: null,
    };
    inMemoryFriendships.set(key(targetUser.id, ownerUserId), reciprocalFriendship);
    await persistFriendshipToDb(reciprocalFriendship);

    notificationsStore.create({
      userId: targetUser.id,
      type: 'FRIEND_ADDED',
      payload: {
        adderId: ownerUserId,
        adderName: owner.name,
        phone: owner.phoneE164,
      },
    });
  }

  return {
    friendId: targetUser.id,
    ledgerId,
    isAppUser,
    friend: {
      id: targetUser.id,
      name: targetUser.name,
      phoneE164: targetUser.phoneE164,
      photoUrl: targetUser.photoUrl,
      isAppUser,
      contactName: contactName || null,
      nickname: null,
    },
  };
}

export function updateFriendNickname(ownerUserId: string, friendUserId: string, nickname: string | null) {
  const f = inMemoryFriendships.get(key(ownerUserId, friendUserId));
  if (!f || f.removedAt !== null) {
    throw new NotFoundError('Friendship not found');
  }

  f.nickname = nickname ? nickname.trim() : null;
  db('friendships')
    .where({ owner_user_id: ownerUserId, friend_user_id: friendUserId })
    .update({ nickname: f.nickname })
    .catch((err) => console.error('[FriendsStore] Error updating nickname in MySQL:', err));

  return {
    friendId: friendUserId,
    nickname: f.nickname,
  };
}

export function removeFriend(ownerUserId: string, friendUserId: string) {
  const f = inMemoryFriendships.get(key(ownerUserId, friendUserId));
  if (!f || f.removedAt !== null) {
    throw new NotFoundError('Friendship not found');
  }

  const ledger = inMemoryLedgers.get(f.individualLedgerId);
  if (ledger) {
    const netResult = calculateNetBalances(ledger.memberIds, ledger.expenses, ledger.settlements);
    const net = netResult.balances[ownerUserId] || 0;
    if (net !== 0) {
      throw new UnsettledBalanceError(`Cannot unfriend while balance is unsettled (balance: ₹${(net / 100).toFixed(2)})`);
    }

    const hasPending = ledger.settlements.some(
      (s: any) =>
        s.status === 'PENDING' &&
        (s.fromUserId === ownerUserId || s.toUserId === ownerUserId ||
         s.fromUserId === friendUserId || s.toUserId === friendUserId)
    );
    if (hasPending) {
      throw new UnsettledBalanceError('Cannot unfriend while a settlement is pending confirmation');
    }
  }

  const now = new Date();
  f.removedAt = now.toISOString();

  db('friendships')
    .where({ owner_user_id: ownerUserId, friend_user_id: friendUserId })
    .update({ removed_at: now })
    .catch((err) => console.error('[FriendsStore] Error removing friendship in MySQL:', err));

  return { success: true };
}

export function blockUser(blockerId: string, blockedId: string) {
  inMemoryBlocks.add(`${blockerId}:${blockedId}`);
  db('user_blocks')
    .insert({
      blocker_user_id: blockerId,
      blocked_user_id: blockedId,
      created_at: new Date(),
    })
    .onConflict(['blocker_user_id', 'blocked_user_id'])
    .ignore()
    .catch((err) => console.error('[FriendsStore] Error blocking user in MySQL:', err));
  return { success: true };
}

export function unblockUser(blockerId: string, blockedId: string) {
  inMemoryBlocks.delete(`${blockerId}:${blockedId}`);
  db('user_blocks')
    .where({ blocker_user_id: blockerId, blocked_user_id: blockedId })
    .delete()
    .catch((err) => console.error('[FriendsStore] Error unblocking user in MySQL:', err));
  return { success: true };
}

export function repointFriendshipsOnMerge(placeholderId: string, realId: string) {
  const entries = Array.from(inMemoryFriendships.entries());
  for (const [k, f] of entries) {
    let changed = false;
    let newOwner = f.ownerUserId;
    let newFriend = f.friendUserId;

    if (f.ownerUserId === placeholderId) {
      newOwner = realId;
      changed = true;
    }
    if (f.friendUserId === placeholderId) {
      newFriend = realId;
      changed = true;
    }

    if (changed) {
      inMemoryFriendships.delete(k);
      const newKey = key(newOwner, newFriend);
      const existing = inMemoryFriendships.get(newKey);
      if (existing) {
        if (!existing.nickname && f.nickname) {
          existing.nickname = f.nickname;
        }
      } else {
        f.ownerUserId = newOwner;
        f.friendUserId = newFriend;
        inMemoryFriendships.set(newKey, f);
        persistFriendshipToDb(f);
      }

      const reciprocalKey = key(newFriend, newOwner);
      if (!inMemoryFriendships.has(reciprocalKey)) {
        const recip: Friendship = {
          ownerUserId: newFriend,
          friendUserId: newOwner,
          individualLedgerId: f.individualLedgerId,
          nickname: null,
          contactName: null,
          createdAt: f.createdAt,
          removedAt: null,
        };
        inMemoryFriendships.set(reciprocalKey, recip);
        persistFriendshipToDb(recip);
      }
    }
  }
}

registerMergeHook(repointFriendshipsOnMerge);

export async function initFriendsStore(): Promise<void> {
  try {
    const rows = await db('friendships').whereNull('removed_at').select('*');
    for (const r of rows) {
      inMemoryFriendships.set(key(r.owner_user_id, r.friend_user_id), {
        ownerUserId: r.owner_user_id,
        friendUserId: r.friend_user_id,
        individualLedgerId: r.individual_ledger_id,
        nickname: r.nickname || null,
        contactName: r.contact_name || null,
        createdAt: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at),
        removedAt: r.removed_at instanceof Date ? r.removed_at.toISOString() : (r.removed_at ? String(r.removed_at) : null),
      });
    }

    const blocks = await db('user_blocks').select('*');
    for (const b of blocks) {
      inMemoryBlocks.add(`${b.blocker_user_id}:${b.blocked_user_id}`);
    }

    console.log(`[FriendsStore] Loaded ${inMemoryFriendships.size} friendships and ${inMemoryBlocks.size} blocks from Cloud MySQL.`);
  } catch (err) {
    console.error('[FriendsStore] Error loading friendships from MySQL:', err);
  }
}
