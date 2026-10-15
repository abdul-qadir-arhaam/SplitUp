import { ulid } from 'ulidx';
import { db } from '../../db/knex.js';
import {
  inMemoryUsers,
  findUserById,
  findUserByIdAsync,
  findUserByPhone,
  findUserByPhoneAsync,
  createUser,
  registerMergeHook,
} from '../users/store.js';
import { normalizePhoneE164 } from '../users/phone.js';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { getLedgerBalancesFromDb } from '../balances/sqlBalances.js';
import { notificationsStore } from '../notifications/store.js';
import { ValidationError, NotFoundError, ConflictError, UnsettledBalanceError } from '../../lib/errors.js';

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

  // 1. Search existing individual ledger in MySQL
  const existing = await db('ledgers')
    .where({
      type: 'INDIVIDUAL',
      pair_low_user_id: low,
      pair_high_user_id: high,
    })
    .whereNull('deleted_at')
    .first();

  if (existing) {
    return existing.id;
  }

  // 2. Create new individual ledger in MySQL
  const id = `ldg_${ulid()}`;
  const userARow = await findUserByIdAsync(userA);
  const userBRow = await findUserByIdAsync(userB);
  const userAName = userARow?.name || 'User A';
  const userBName = userBRow?.name || 'User B';

  try {
    await db.transaction(async (trx) => {
      await trx('ledgers').insert({
        id,
        type: 'INDIVIDUAL',
        name: `${userAName} & ${userBName}`,
        status: 'ACTIVE',
        pair_low_user_id: low,
        pair_high_user_id: high,
        created_by: createdBy,
        created_at: new Date(),
        updated_at: new Date(),
      });

      await trx('ledger_members').insert([
        { ledger_id: id, user_id: low, role: 'MEMBER', joined_at: new Date() },
        { ledger_id: id, user_id: high, role: 'MEMBER', joined_at: new Date() },
      ]);
    });

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
  } catch (err: any) {
    // If concurrent insert created the same pair, fetch it
    const raceExisting = await db('ledgers')
      .where({
        type: 'INDIVIDUAL',
        pair_low_user_id: low,
        pair_high_user_id: high,
      })
      .whereNull('deleted_at')
      .first();

    if (raceExisting) {
      return raceExisting.id;
    }
    throw err;
  }
}

export async function listFriends(ownerUserId: string): Promise<any[]> {
  const rows = await db('friendships as f')
    .join('users as u', 'u.id', 'f.friend_user_id')
    .where('f.owner_user_id', ownerUserId)
    .whereNull('f.removed_at')
    .select(
      'f.friend_user_id as friendId',
      'f.individual_ledger_id as individualLedgerId',
      'f.nickname',
      'f.contact_name as contactName',
      'u.name',
      'u.phone_e164 as phoneE164',
      'u.photo_url as photoUrl',
      'u.is_placeholder as isPlaceholder'
    );

  const results: any[] = [];

  for (const r of rows) {
    let netPaise = 0;
    if (r.individualLedgerId) {
      try {
        const balances = await getLedgerBalancesFromDb(r.individualLedgerId);
        netPaise = balances[ownerUserId] || 0;
      } catch (err) {
        console.error(`[FriendsStore] Error computing balance for ledger ${r.individualLedgerId}:`, err);
      }
    }

    const commonGroups = await db('ledger_members as m1')
      .join('ledger_members as m2', 'm1.ledger_id', 'm2.ledger_id')
      .join('ledgers as l', 'l.id', 'm1.ledger_id')
      .where('m1.user_id', ownerUserId)
      .where('m2.user_id', r.friendId)
      .where('l.type', 'GROUP')
      .where('l.status', 'ACTIVE')
      .pluck('l.name');


    results.push({
      friendId: r.friendId,
      name: r.name,
      phoneE164: r.phoneE164,
      photoUrl: r.photoUrl,
      isAppUser: !Boolean(r.isPlaceholder),
      nickname: r.nickname,
      contactName: r.contactName,
      individualLedgerId: r.individualLedgerId,
      netPaise, // positive: friend owes me; negative: I owe friend
      commonGroups,
    });
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
  const owner = await findUserByIdAsync(ownerUserId);
  if (!owner) throw new NotFoundError('Current user not found');

  const normalizedPhone = normalizePhoneE164(params.phone);
  if (owner.phoneE164 === normalizedPhone) {
    throw new ValidationError('You cannot add yourself as a friend');
  }

  // Check if target user exists in MySQL
  let targetUser = await findUserByPhoneAsync(normalizedPhone);
  const isAppUser = targetUser ? !targetUser.isPlaceholder : false;

  if (targetUser) {
    const existing = await db('friendships')
      .where({ owner_user_id: ownerUserId, friend_user_id: targetUser.id })
      .first();
    if (existing && existing.removed_at === null) {
      throw new ConflictError('Friend already added');
    }
  } else {
    // Create placeholder user in DB
    const newId = `usr_${ulid()}`;
    const now = new Date();
    await db('users').insert({
      id: newId,
      phone_e164: normalizedPhone,
      name: name || normalizedPhone,
      is_placeholder: 1,
      status: 'ACTIVE',
      created_by: ownerUserId,
      created_at: now,
      updated_at: now,
    });
    targetUser = {
      id: newId,
      phoneE164: normalizedPhone,
      name: name || normalizedPhone,
      isPlaceholder: true,
      status: 'ACTIVE',
      createdBy: ownerUserId,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    } as any;
  }

  if (!targetUser) {
    throw new NotFoundError('Failed to find or create friend user');
  }

  const ledgerId = await getOrCreateIndividualLedger(ownerUserId, targetUser.id, ownerUserId);
  const now = new Date();


  // Create or restore friendship for owner
  await db('friendships')
    .insert({
      owner_user_id: ownerUserId,
      friend_user_id: targetUser.id,
      individual_ledger_id: ledgerId,
      nickname: null,
      contact_name: contactName || null,
      created_at: now,
      removed_at: null,
    })
    .onConflict(['owner_user_id', 'friend_user_id'])
    .merge({
      individual_ledger_id: ledgerId,
      contact_name: contactName || null,
      removed_at: null,
    });

  // If real app user, create reciprocal friendship and in-app notification
  if (isAppUser) {
    await db('friendships')
      .insert({
        owner_user_id: targetUser.id,
        friend_user_id: ownerUserId,
        individual_ledger_id: ledgerId,
        nickname: null,
        contact_name: null,
        created_at: now,
        removed_at: null,
      })
      .onConflict(['owner_user_id', 'friend_user_id'])
      .merge({
        individual_ledger_id: ledgerId,
        removed_at: null,
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

export async function updateFriendNickname(ownerUserId: string, friendUserId: string, nickname: string | null) {
  const f = await db('friendships')
    .where({ owner_user_id: ownerUserId, friend_user_id: friendUserId })
    .whereNull('removed_at')
    .first();

  if (!f) {
    throw new NotFoundError('Friendship not found');
  }

  const cleaned = nickname ? nickname.trim() : null;
  await db('friendships')
    .where({ owner_user_id: ownerUserId, friend_user_id: friendUserId })
    .update({ nickname: cleaned });

  return {
    friendId: friendUserId,
    nickname: cleaned,
  };
}

export async function removeFriend(ownerUserId: string, friendUserId: string) {
  const f = await db('friendships')
    .where({ owner_user_id: ownerUserId, friend_user_id: friendUserId })
    .whereNull('removed_at')
    .first();

  if (!f) {
    throw new NotFoundError('Friendship not found');
  }

  if (f.individual_ledger_id) {
    const balances = await getLedgerBalancesFromDb(f.individual_ledger_id);
    const net = balances[ownerUserId] || 0;
    if (net !== 0) {
      throw new UnsettledBalanceError(`Cannot unfriend while balance is unsettled (balance: ₹${(net / 100).toFixed(2)})`);
    }

    const pending = await db('settlements')
      .where({ ledger_id: f.individual_ledger_id, status: 'PENDING' })
      .first();
    if (pending) {
      throw new UnsettledBalanceError('Cannot unfriend while a settlement is pending confirmation');
    }
  }

  const now = new Date();
  await db('friendships')
    .where({ owner_user_id: ownerUserId, friend_user_id: friendUserId })
    .update({ removed_at: now });

  return { success: true };
}

export async function blockUser(blockerId: string, blockedId: string) {
  inMemoryBlocks.add(`${blockerId}:${blockedId}`);
  await db('user_blocks')
    .insert({
      blocker_user_id: blockerId,
      blocked_user_id: blockedId,
      created_at: new Date(),
    })
    .onConflict(['blocker_user_id', 'blocked_user_id'])
    .ignore();
  return { success: true };
}

export async function unblockUser(blockerId: string, blockedId: string) {
  inMemoryBlocks.delete(`${blockerId}:${blockedId}`);
  await db('user_blocks')
    .where({ blocker_user_id: blockerId, blocked_user_id: blockedId })
    .delete();
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
