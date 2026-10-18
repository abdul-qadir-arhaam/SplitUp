import { ulid } from 'ulidx';
import { inMemoryLedgers } from '../ledgers/routes.js';
import { inMemoryUsers } from '../users/store.js';
import { calculateNetBalances, simplifyDebts, calculatePairwiseDebts } from '../balances/index.js';
import { notificationsStore } from '../notifications/store.js';
import { activityStore } from '../activity/store.js';
import {
  ValidationError,
  NotFoundError,
  ForbiddenError,
  ConflictError,
  UnsettledBalanceError,
} from '../../lib/errors.js';
import { persistLedgerToDb } from '../ledgers/db_sync.js';
import { db } from '../../db/knex.js';

export interface GroupMemberInfo {
  userId: string;
  name: string;
  phoneE164: string;
  photoUrl?: string | null;
  role: 'ADMIN' | 'MEMBER';
  netPaise: number;
  isAppUser: boolean;
}

export async function createGroup(params: {
  name: string;
  creatorUserId: string;
  memberUserIds: string[];
  photoUrl?: string | null;
}): Promise<any> {
  const { name, creatorUserId, memberUserIds, photoUrl } = params;

  if (!name || name.trim().length === 0) {
    throw new ValidationError('Group name is required');
  }

  const allMembers = Array.from(new Set([creatorUserId, ...memberUserIds]));
  const id = `grp_${ulid()}`;
  const now = new Date().toISOString();

  // Fetch member user details for GroupMember format
  const dbUsers = allMembers.length > 0
    ? await db('users').whereIn('id', allMembers).select('*').catch(() => [])
    : [];
  const usersMap = new Map(dbUsers.map((u: any) => [u.id, u]));

  const membersInfo: GroupMemberInfo[] = allMembers.map((uid) => {
    const memUser = inMemoryUsers.get(uid);
    const dbU = usersMap.get(uid);
    const mName = dbU?.name || memUser?.name || (uid === creatorUserId ? 'You' : 'Member');
    const phone = dbU?.phone_e164 || memUser?.phoneE164 || '';
    const isAppUser = dbU ? !dbU.is_placeholder : (memUser ? !memUser.isPlaceholder : true);
    return {
      userId: uid,
      name: mName,
      phoneE164: phone,
      photoUrl: dbU?.photo_url || memUser?.photoUrl || null,
      role: uid === creatorUserId ? 'ADMIN' : 'MEMBER',
      netPaise: 0,
      isAppUser,
    };
  });

  const groupRecord = {
    id,
    name: name.trim(),
    type: 'GROUP' as const,
    photoUrl: photoUrl || null,
    creatorUserId,
    adminUserIds: [creatorUserId],
    memberIds: allMembers,
    members: membersInfo,
    isAdmin: true,
    myNetPaise: 0,
    totalSpentPaise: 0,
    lastActivity: 'Created just now',
    expenses: [],
    settlements: [],
    createdAt: now,
    updatedAt: now,
  };

  inMemoryLedgers.set(id, groupRecord as any);

  // Persist group to MySQL and AWAIT to guarantee durability
  await persistLedgerToDb(groupRecord as any);

  // Log activity
  activityStore.log({
    ledgerId: id,
    actorUserId: creatorUserId,
    action: 'LEDGER_CREATED',
    entityType: 'ledger',
    entityId: id,
    payload: { name: groupRecord.name, memberCount: allMembers.length },
  });

  // Notify other members
  for (const uid of allMembers) {
    if (uid !== creatorUserId) {
      const user = inMemoryUsers.get(uid) || usersMap.get(uid);
      const isPlaceholder = user ? (user.isPlaceholder ?? user.is_placeholder) : false;
      if (!isPlaceholder) {
        const notifPayload = {
          groupId: id,
          groupName: groupRecord.name,
          creatorUserId,
        };
        await notificationsStore.create({
          userId: uid,
          type: 'ADDED_TO_GROUP' as any,
          payload: notifPayload,
        });
      }
    }
  }

  return groupRecord;
}

export async function listUserGroups(userId: string): Promise<any[]> {
  const results: any[] = [];
  const seenIds = new Set<string>();

  // 1. Fetch group IDs where user is member from MySQL
  let dbLedgerIds: string[] = [];
  try {
    const memberRows = await db('ledger_members')
      .where({ user_id: userId })
      .whereNull('left_at')
      .select('ledger_id');
    dbLedgerIds = memberRows.map((r: any) => r.ledger_id);
  } catch (err) {
    console.error('[GroupsStore] Error querying ledger_members from MySQL:', err);
  }

  // 2. Also check inMemoryLedgers
  for (const ledger of inMemoryLedgers.values()) {
    if (ledger.type === 'GROUP' && ledger.memberIds.includes(userId)) {
      dbLedgerIds.push(ledger.id);
    }
  }

  const uniqueGroupIds = Array.from(new Set(dbLedgerIds));
  if (uniqueGroupIds.length === 0) {
    return [];
  }

  // 3. Load ledgers from MySQL
  let dbLedgers: any[] = [];
  try {
    dbLedgers = await db('ledgers')
      .whereIn('id', uniqueGroupIds)
      .where({ type: 'GROUP' })
      .whereNot('status', 'DELETED')
      .select('*');
  } catch (err) {
    console.error('[GroupsStore] Error querying ledgers from MySQL:', err);
  }

  // Fallback to in-memory ledgers if dbLedgers is empty
  if (dbLedgers.length === 0) {
    for (const gid of uniqueGroupIds) {
      const mem = inMemoryLedgers.get(gid);
      if (mem && mem.type === 'GROUP') {
        dbLedgers.push(mem);
      }
    }
  }

  if (dbLedgers.length === 0) {
    return [];
  }

  const validGroupIds = dbLedgers.map((l: any) => l.id);

  // 4. Load all active members for these groups
  let memberRows: any[] = [];
  try {
    memberRows = await db('ledger_members')
      .whereIn('ledger_id', validGroupIds)
      .whereNull('left_at')
      .select('*');
  } catch (_) {}

  // 5. Load users for members
  const memberUserIds = Array.from(new Set(memberRows.map((m: any) => m.user_id)));
  let userRows: any[] = [];
  if (memberUserIds.length > 0) {
    try {
      userRows = await db('users').whereIn('id', memberUserIds).select('*');
    } catch (_) {}
  }
  const usersMap = new Map(userRows.map((u: any) => [u.id, u]));

  // 6. Load expenses and settlements
  let dbExpenses: any[] = [];
  try {
    dbExpenses = await db('expenses')
      .whereIn('ledger_id', validGroupIds)
      .whereNull('deleted_at')
      .select('*');
  } catch (_) {}

  let dbSettlements: any[] = [];
  try {
    dbSettlements = await db('settlements')
      .whereIn('ledger_id', validGroupIds)
      .where({ status: 'CONFIRMED' })
      .select('*');
  } catch (_) {}

  // Group members, expenses, settlements by ledger
  const membersByLedger = new Map<string, any[]>();
  for (const m of memberRows) {
    const list = membersByLedger.get(m.ledger_id) || [];
    const dbU = usersMap.get(m.user_id);
    const memU = inMemoryUsers.get(m.user_id);
    list.push({
      userId: m.user_id,
      name: dbU?.name || memU?.name || 'Member',
      phoneE164: dbU?.phone_e164 || memU?.phoneE164 || '',
      photoUrl: dbU?.photo_url || memU?.photoUrl || null,
      role: m.role || 'MEMBER',
      netPaise: 0,
      isAppUser: dbU ? !dbU.is_placeholder : (memU ? !memUserIsPlaceholder(memU) : true),
    });
    membersByLedger.set(m.ledger_id, list);
  }

  function memUserIsPlaceholder(u: any) {
    return Boolean(u?.isPlaceholder ?? u?.is_placeholder);
  }

  const expensesByLedger = new Map<string, any[]>();
  for (const e of dbExpenses) {
    const list = expensesByLedger.get(e.ledger_id) || [];
    list.push({
      id: e.id,
      ledgerId: e.ledger_id,
      totalPaise: Number(e.total_paise),
      deletedAt: e.deleted_at,
    });
    expensesByLedger.set(e.ledger_id, list);
  }

  const settlementsByLedger = new Map<string, any[]>();
  for (const s of dbSettlements) {
    const list = settlementsByLedger.get(s.ledger_id) || [];
    list.push({
      id: s.id,
      fromUserId: s.from_user_id,
      toUserId: s.to_user_id,
      amountPaise: Number(s.amount_paise),
      status: s.status,
    });
    settlementsByLedger.set(s.ledger_id, list);
  }

  // 7. Assemble final group models
  for (const ledger of dbLedgers) {
    const gid = ledger.id;
    if (seenIds.has(gid)) continue;
    seenIds.add(gid);

    const memLedger = inMemoryLedgers.get(gid) as any;
    const members = membersByLedger.get(gid) || (memLedger?.members ?? []);
    const memberIds = members.map((m: any) => m.userId);
    const creatorUserId = ledger.created_by || ledger.creatorUserId || memLedger?.creatorUserId || '';
    const adminUserIds = memLedger?.adminUserIds || [creatorUserId];

    const expenses = memLedger?.expenses || expensesByLedger.get(gid) || [];
    const settlements = memLedger?.settlements || settlementsByLedger.get(gid) || [];

    const activeExpenses = expenses.filter((e: any) => !e.deletedAt);
    const confirmedSettlements = settlements.filter((s: any) => s.status === 'CONFIRMED');

    const netResult = calculateNetBalances(memberIds, activeExpenses, confirmedSettlements);
    const totalSpentPaise = activeExpenses.reduce((sum: number, e: any) => sum + (e.totalPaise || 0), 0);

    // Keep inMemoryLedgers populated
    if (!memLedger) {
      inMemoryLedgers.set(gid, {
        id: gid,
        name: ledger.name,
        type: 'GROUP',
        photoUrl: ledger.photo_url || ledger.photoUrl || null,
        creatorUserId,
        adminUserIds,
        memberIds,
        expenses,
        settlements,
        createdAt: ledger.created_at instanceof Date ? ledger.created_at.toISOString() : String(ledger.created_at),
        updatedAt: ledger.updated_at instanceof Date ? ledger.updated_at.toISOString() : String(ledger.updated_at),
      } as any);
    }

    results.push({
      id: gid,
      name: ledger.name,
      photoUrl: ledger.photo_url || ledger.photoUrl || null,
      creatorUserId,
      isAdmin: adminUserIds.includes(userId),
      memberIds,
      members,
      memberCount: memberIds.length,
      myNetPaise: netResult.balances[userId] || 0,
      totalSpentPaise,
      lastActivity: 'Active recently',
      createdAt: ledger.created_at instanceof Date ? ledger.created_at.toISOString() : String(ledger.created_at),
      updatedAt: ledger.updated_at instanceof Date ? ledger.updated_at.toISOString() : String(ledger.updated_at),
    });
  }

  return results.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export async function getGroupDetails(groupId: string, callerUserId: string): Promise<any> {
  let ledger = inMemoryLedgers.get(groupId);
  if (!ledger) {
    const dbLedger = await db('ledgers')
      .where({ id: groupId, type: 'GROUP' })
      .whereNot('status', 'DELETED')
      .first();

    if (dbLedger) {
      const memberRows = await db('ledger_members')
        .where({ ledger_id: groupId })
        .whereNull('left_at')
        .select('*');
      const memberIds = memberRows.map((r: any) => r.user_id);
      const adminUserIds = memberRows
        .filter((r: any) => r.role === 'ADMIN')
        .map((r: any) => r.user_id);
      if (adminUserIds.length === 0) adminUserIds.push(dbLedger.created_by);

      ledger = {
        id: dbLedger.id,
        name: dbLedger.name,
        type: 'GROUP',
        photoUrl: dbLedger.photo_url || null,
        creatorUserId: dbLedger.created_by,
        adminUserIds,
        memberIds,
        expenses: [],
        settlements: [],
        createdAt: dbLedger.created_at instanceof Date ? dbLedger.created_at.toISOString() : String(dbLedger.created_at),
        updatedAt: dbLedger.updated_at instanceof Date ? dbLedger.updated_at.toISOString() : String(dbLedger.updated_at),
      } as any;
      inMemoryLedgers.set(groupId, ledger as any);
    }
  }

  if (!ledger || ledger.type !== 'GROUP') {
    throw new NotFoundError(`Group ${groupId} not found`);
  }

  if (!ledger.memberIds.includes(callerUserId)) {
    throw new ForbiddenError('You are not a member of this group');
  }

  const anyLedger = ledger as any;
  const adminUserIds: string[] = anyLedger.adminUserIds || [anyLedger.creatorUserId];

  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );

  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  // Fetch users from MySQL/inMemory
  const dbUsers = ledger.memberIds.length > 0
    ? await db('users').whereIn('id', ledger.memberIds).select('*').catch(() => [])
    : [];
  const usersMap = new Map(dbUsers.map((u: any) => [u.id, u]));

  const membersInfo: GroupMemberInfo[] = ledger.memberIds.map((uid) => {
    const memUser = inMemoryUsers.get(uid);
    const dbU = usersMap.get(uid);
    return {
      userId: uid,
      name: dbU?.name || memUser?.name || uid,
      phoneE164: dbU?.phone_e164 || memUser?.phoneE164 || '',
      photoUrl: dbU?.photo_url || memUser?.photoUrl || null,
      role: adminUserIds.includes(uid) ? 'ADMIN' : 'MEMBER',
      netPaise: netResult.balances[uid] || 0,
      isAppUser: dbU ? !dbU.is_placeholder : (memUser ? !memUser.isPlaceholder : true),
    };
  });

  const totalSpentPaise = activeExpenses.reduce(
    (sum: number, e: any) => sum + e.totalPaise,
    0
  );

  return {
    id: ledger.id,
    name: ledger.name,
    photoUrl: anyLedger.photoUrl || null,
    creatorUserId: anyLedger.creatorUserId,
    isAdmin: adminUserIds.includes(callerUserId),
    members: membersInfo,
    myNetPaise: netResult.balances[callerUserId] || 0,
    totalSpentPaise,
    expenses: activeExpenses,
    settlements: ledger.settlements,
    createdAt: anyLedger.createdAt,
    updatedAt: anyLedger.updatedAt,
  };
}

export async function updateGroup(
  groupId: string,
  actorUserId: string,
  data: { name?: string; photoUrl?: string | null }
): Promise<any> {
  let ledger = inMemoryLedgers.get(groupId);
  if (!ledger) {
    await getGroupDetails(groupId, actorUserId);
    ledger = inMemoryLedgers.get(groupId);
  }

  if (!ledger || ledger.type !== 'GROUP') {
    throw new NotFoundError(`Group ${groupId} not found`);
  }

  const anyLedger = ledger as any;
  const adminUserIds: string[] = anyLedger.adminUserIds || [anyLedger.creatorUserId];
  if (!adminUserIds.includes(actorUserId)) {
    throw new ForbiddenError('Only group admins can update group details');
  }

  if (data.name !== undefined) {
    if (data.name.trim().length === 0) {
      throw new ValidationError('Group name cannot be empty');
    }
    const oldName = ledger.name;
    ledger.name = data.name.trim();

    activityStore.log({
      ledgerId: groupId,
      actorUserId,
      action: 'LEDGER_RENAMED',
      entityType: 'ledger',
      entityId: groupId,
      payload: { oldName, newName: ledger.name },
    });
  }

  if (data.photoUrl !== undefined) {
    anyLedger.photoUrl = data.photoUrl;
  }

  anyLedger.updatedAt = new Date().toISOString();
  await persistLedgerToDb(ledger);
  return ledger;
}

export async function addMember(groupId: string, actorUserId: string, newUserId: string): Promise<any> {
  let ledger = inMemoryLedgers.get(groupId);
  if (!ledger) {
    await getGroupDetails(groupId, actorUserId);
    ledger = inMemoryLedgers.get(groupId);
  }

  if (!ledger || ledger.type !== 'GROUP') {
    throw new NotFoundError(`Group ${groupId} not found`);
  }

  const anyLedger = ledger as any;
  const adminUserIds: string[] = anyLedger.adminUserIds || [anyLedger.creatorUserId];
  if (!adminUserIds.includes(actorUserId)) {
    throw new ForbiddenError('Only group admins can add members');
  }

  if (ledger.memberIds.includes(newUserId)) {
    throw new ConflictError('User is already a member of this group');
  }

  ledger.memberIds.push(newUserId);
  anyLedger.updatedAt = new Date().toISOString();

  // Persist updated membership to MySQL
  await persistLedgerToDb(ledger);

  activityStore.log({
    ledgerId: groupId,
    actorUserId,
    action: 'MEMBER_ADDED',
    entityType: 'member',
    entityId: newUserId,
  });

  const user = inMemoryUsers.get(newUserId);
  if (user && !user.isPlaceholder) {
    await notificationsStore.create({
      userId: newUserId,
      type: 'ADDED_TO_GROUP',
      payload: {
        groupId,
        groupName: ledger.name,
        addedBy: actorUserId,
      },
    });
  }

  return ledger;
}

export async function removeMember(
  groupId: string,
  actorUserId: string,
  targetUserId: string
): Promise<any> {
  let ledger = inMemoryLedgers.get(groupId);
  if (!ledger) {
    await getGroupDetails(groupId, actorUserId);
    ledger = inMemoryLedgers.get(groupId);
  }

  if (!ledger || ledger.type !== 'GROUP') {
    throw new NotFoundError(`Group ${groupId} not found`);
  }

  const anyLedger = ledger as any;
  const adminUserIds: string[] = anyLedger.adminUserIds || [anyLedger.creatorUserId];
  const isSelf = actorUserId === targetUserId;
  const isAdmin = adminUserIds.includes(actorUserId);

  if (!isSelf && !isAdmin) {
    throw new ForbiddenError('Only group admins can remove other members');
  }

  if (!ledger.memberIds.includes(targetUserId)) {
    throw new NotFoundError('User is not a member of this group');
  }

  // Rule GRP-5: Member cannot leave or be removed with unsettled balances
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );

  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const targetNet = netResult.balances[targetUserId] || 0;
  if (targetNet !== 0) {
    throw new UnsettledBalanceError(
      `Cannot remove member ${targetUserId} with unsettled balance of ${targetNet} paise`
    );
  }

  ledger.memberIds = ledger.memberIds.filter((id) => id !== targetUserId);
  anyLedger.adminUserIds = adminUserIds.filter((id) => id !== targetUserId);
  anyLedger.updatedAt = new Date().toISOString();

  // Persist updated membership & mark left in MySQL
  await persistLedgerToDb(ledger);
  await db('ledger_members')
    .where({ ledger_id: groupId, user_id: targetUserId })
    .update({ left_at: new Date() });

  activityStore.log({
    ledgerId: groupId,
    actorUserId,
    action: isSelf ? 'MEMBER_LEFT' : 'MEMBER_REMOVED',
    entityType: 'member',
    entityId: targetUserId,
  });

  return ledger;
}

export async function deleteGroup(groupId: string, actorUserId: string): Promise<any> {
  let ledger = inMemoryLedgers.get(groupId);
  if (!ledger) {
    await getGroupDetails(groupId, actorUserId);
    ledger = inMemoryLedgers.get(groupId);
  }

  if (!ledger || ledger.type !== 'GROUP') {
    throw new NotFoundError(`Group ${groupId} not found`);
  }

  const anyLedger = ledger as any;
  const adminUserIds: string[] = anyLedger.adminUserIds || [anyLedger.creatorUserId];
  if (!adminUserIds.includes(actorUserId)) {
    throw new ForbiddenError('Only group admins can delete the group');
  }

  // Check all balances are 0
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );
  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  for (const [uid, bal] of Object.entries(netResult.balances)) {
    if (bal !== 0) {
      throw new UnsettledBalanceError(
        `Cannot delete group while member ${uid} has unsettled balance of ${bal} paise`
      );
    }
  }

  inMemoryLedgers.delete(groupId);

  // Soft delete in MySQL
  await db('ledgers')
    .where({ id: groupId })
    .update({ status: 'DELETED', updated_at: new Date() });

  return { success: true };
}

export async function getGroupDashboard(groupId: string, callerUserId: string): Promise<any> {
  const details = await getGroupDetails(groupId, callerUserId);
  const ledger = inMemoryLedgers.get(groupId)!;
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);

  // 1. Category donut breakdown
  const categoryTotals: Record<string, number> = {};
  for (const exp of activeExpenses) {
    categoryTotals[exp.category] = (categoryTotals[exp.category] || 0) + exp.totalPaise;
  }
  const categories = Object.entries(categoryTotals).map(([cat, total]) => ({
    category: cat,
    totalPaise: total,
    percentage: details.totalSpentPaise > 0 ? (total / details.totalSpentPaise) * 100 : 0,
  }));

  // 2. Paid vs Share per member
  const memberPaidShare: Record<string, { paid: number; share: number }> = {};
  for (const mem of details.members) {
    memberPaidShare[mem.userId] = { paid: 0, share: 0 };
  }
  for (const exp of activeExpenses) {
    for (const p of exp.payers) {
      if (memberPaidShare[p.userId]) {
        memberPaidShare[p.userId].paid += p.paidPaise;
      }
    }
    for (const s of exp.splits) {
      if (s.included && memberPaidShare[s.userId]) {
        memberPaidShare[s.userId].share += s.owedPaise;
      }
    }
  }

  const memberBars = details.members.map((mem: any) => ({
    userId: mem.userId,
    name: mem.name,
    paidPaise: memberPaidShare[mem.userId]?.paid || 0,
    sharePaise: memberPaidShare[mem.userId]?.share || 0,
  }));

  // 3. Spending over time
  const spendingByDate: Record<string, number> = {};
  for (const exp of activeExpenses) {
    spendingByDate[exp.expenseDate] = (spendingByDate[exp.expenseDate] || 0) + exp.totalPaise;
  }
  const spendingOverTime = Object.entries(spendingByDate)
    .sort(([dateA], [dateB]) => dateA.localeCompare(dateB))
    .map(([date, total]) => ({
      date,
      totalPaise: total,
    }));

  return {
    totalSpentPaise: details.totalSpentPaise,
    categories,
    categoryBreakdown: categories,
    memberBars,
    memberMetrics: memberBars,
    spendingOverTime,
  };
}

export async function getGroupGraph(
  groupId: string,
  callerUserId: string,
  mode: 'simplified' | 'actual' = 'simplified'
): Promise<any> {
  const details = await getGroupDetails(groupId, callerUserId);
  const ledger = inMemoryLedgers.get(groupId)!;
  const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
  const confirmedSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'CONFIRMED'
  );
  const pendingSettlements = ledger.settlements.filter(
    (s: any) => s.status === 'PENDING'
  );

  const netResult = calculateNetBalances(
    ledger.memberIds,
    activeExpenses,
    confirmedSettlements
  );

  const nodes = details.members.map((mem: any) => ({
    id: mem.userId,
    name: mem.name,
    role: mem.role,
    netPaise: netResult.balances[mem.userId] || 0,
    isAppUser: mem.isAppUser,
  }));

  let links: any[] = [];

  if (mode === 'simplified') {
    const plan = simplifyDebts(netResult.balances);
    links = plan.map((p) => ({
      fromUserId: p.from,
      toUserId: p.to,
      amountPaise: p.amountPaise,
      isPending: false,
    }));
  } else {
    const debts = calculatePairwiseDebts(activeExpenses, confirmedSettlements);
    links = debts.map((d) => ({
      fromUserId: d.from,
      toUserId: d.to,
      amountPaise: d.amountPaise,
      isPending: false,
    }));
  }

  // Overlay pending settlements as dashed links
  for (const s of pendingSettlements) {
    links.push({
      settlementId: s.id,
      fromUserId: s.fromUserId,
      toUserId: s.toUserId,
      amountPaise: s.amountPaise,
      isPending: true,
      method: s.method,
    });
  }

  return {
    groupId,
    mode,
    nodes,
    links,
  };
}

export function getCommonGroupsForUsers(userA: string, userB: string): string[] {
  const commonNames: string[] = [];
  for (const ledger of inMemoryLedgers.values()) {
    if (
      ledger.type === 'GROUP' &&
      ledger.memberIds.includes(userA) &&
      ledger.memberIds.includes(userB)
    ) {
      commonNames.push(ledger.name);
    }
  }
  return commonNames;
}
