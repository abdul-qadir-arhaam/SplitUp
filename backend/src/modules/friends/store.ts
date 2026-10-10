import { ulid } from 'ulidx';
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

/**
 * Creates or retrieves the single authoritative individual ledger for two users.
 * Respects DATABASE.md pair_low_user_id and pair_high_user_id constraints.
 */
export function getOrCreateIndividualLedger(userA: string, userB: string, createdBy: string): string {
  const [low, high] = [userA, userB].sort();

  // Search existing individual ledger
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

export function addFriend(params: {
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
    // Create placeholder user
    targetUser = createUser({
      phoneE164: normalizedPhone,
      name: name || normalizedPhone,
      isPlaceholder: true,
      status: 'ACTIVE',
      createdBy: ownerUserId,
    });
  }

  const ledgerId = getOrCreateIndividualLedger(ownerUserId, targetUser.id, ownerUserId);
  const now = new Date().toISOString();

  // Create or restore friendship for owner
  inMemoryFriendships.set(key(ownerUserId, targetUser.id), {
    ownerUserId,
    friendUserId: targetUser.id,
    individualLedgerId: ledgerId,
    nickname: null,
    contactName: contactName || null,
    createdAt: now,
    removedAt: null,
  });

  // If real app user, create reciprocal friendship and in-app notification
  if (isAppUser) {
    inMemoryFriendships.set(key(targetUser.id, ownerUserId), {
      ownerUserId: targetUser.id,
      friendUserId: ownerUserId,
      individualLedgerId: ledgerId,
      nickname: null,
      contactName: null,
      createdAt: now,
      removedAt: null,
    });

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
  return {
    friendId: friendUserId,
    nickname: f.nickname,
  };
}

/**
 * DATABASE.md Section 6.4: Unsettled-balance guard
 * A member has unsettled balance in a ledger if their net is not 0
 * OR they have a PENDING settlement as sender or receiver.
 */
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

  f.removedAt = new Date().toISOString();
  return { success: true };
}

export function blockUser(blockerId: string, blockedId: string) {
  inMemoryBlocks.add(`${blockerId}:${blockedId}`);
  return { success: true };
}

export function unblockUser(blockerId: string, blockedId: string) {
  inMemoryBlocks.delete(`${blockerId}:${blockedId}`);
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
        // Keep row with more data (preserve nickname)
        if (!existing.nickname && f.nickname) {
          existing.nickname = f.nickname;
        }
      } else {
        f.ownerUserId = newOwner;
        f.friendUserId = newFriend;
        inMemoryFriendships.set(newKey, f);
      }

      // Ensure reciprocal friendship exists for real user
      const reciprocalKey = key(newFriend, newOwner);
      if (!inMemoryFriendships.has(reciprocalKey)) {
        inMemoryFriendships.set(reciprocalKey, {
          ownerUserId: newFriend,
          friendUserId: newOwner,
          individualLedgerId: f.individualLedgerId,
          nickname: null,
          contactName: null,
          createdAt: f.createdAt,
          removedAt: null,
        });
      }
    }
  }
}

registerMergeHook(repointFriendshipsOnMerge);
