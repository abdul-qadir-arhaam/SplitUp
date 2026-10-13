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

export interface GroupMemberInfo {
  userId: string;
  name: string;
  phoneE164: string;
  photoUrl?: string | null;
  role: 'ADMIN' | 'MEMBER';
  netPaise: number;
  isAppUser: boolean;
}

export function createGroup(params: {
  name: string;
  creatorUserId: string;
  memberUserIds: string[];
  photoUrl?: string | null;
}): any {
  const { name, creatorUserId, memberUserIds, photoUrl } = params;

  if (!name || name.trim().length === 0) {
    throw new ValidationError('Group name is required');
  }

  const allMembers = Array.from(new Set([creatorUserId, ...memberUserIds]));
  const id = `grp_${ulid()}`;
  const now = new Date().toISOString();

  const groupRecord = {
    id,
    name: name.trim(),
    type: 'GROUP' as const,
    photoUrl: photoUrl || null,
    creatorUserId,
    adminUserIds: [creatorUserId],
    memberIds: allMembers,
    expenses: [],
    settlements: [],
    createdAt: now,
    updatedAt: now,
  };

  inMemoryLedgers.set(id, groupRecord as any);

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
      const user = inMemoryUsers.get(uid);
      if (user && !user.isPlaceholder) {
        notificationsStore.create({
          userId: uid,
          type: 'ADDED_TO_GROUP' as any,
          payload: {
            groupId: id,
            groupName: groupRecord.name,
            creatorUserId,
          },
        });
      }
    }
  }

  return groupRecord;
}

export function listUserGroups(userId: string) {
  const results: any[] = [];

  for (const ledger of inMemoryLedgers.values()) {
    if (ledger.type === 'GROUP' && ledger.memberIds.includes(userId)) {
      const anyLedger = ledger as any;
      const activeExpenses = ledger.expenses.filter((e: any) => !e.deletedAt);
      const confirmedSettlements = ledger.settlements.filter(
        (s: any) => s.status === 'CONFIRMED'
      );

      const netResult = calculateNetBalances(
        ledger.memberIds,
        activeExpenses,
        confirmedSettlements
      );

      const totalSpentPaise = activeExpenses.reduce(
        (sum: number, e: any) => sum + e.totalPaise,
        0
      );

      results.push({
        id: ledger.id,
        name: ledger.name,
        photoUrl: anyLedger.photoUrl || null,
        memberCount: ledger.memberIds.length,
        myNetPaise: netResult.balances[userId] || 0,
        totalSpentPaise,
        createdAt: anyLedger.createdAt || new Date().toISOString(),
        updatedAt: anyLedger.updatedAt || new Date().toISOString(),
      });
    }
  }

  return results.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export function getGroupDetails(groupId: string, callerUserId: string) {
  const ledger = inMemoryLedgers.get(groupId);
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

  const membersInfo: GroupMemberInfo[] = ledger.memberIds.map((uid) => {
    const user = inMemoryUsers.get(uid);
    return {
      userId: uid,
      name: user?.name || uid,
      phoneE164: user?.phoneE164 || '',
      photoUrl: user?.photoUrl || null,
      role: adminUserIds.includes(uid) ? 'ADMIN' : 'MEMBER',
      netPaise: netResult.balances[uid] || 0,
      isAppUser: !user?.isPlaceholder,
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

export function updateGroup(
  groupId: string,
  actorUserId: string,
  data: { name?: string; photoUrl?: string | null }
) {
  const ledger = inMemoryLedgers.get(groupId);
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
  return ledger;
}

export function addMember(groupId: string, actorUserId: string, newUserId: string) {
  const ledger = inMemoryLedgers.get(groupId);
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

  activityStore.log({
    ledgerId: groupId,
    actorUserId,
    action: 'MEMBER_ADDED',
    entityType: 'member',
    entityId: newUserId,
  });

  const user = inMemoryUsers.get(newUserId);
  if (user && !user.isPlaceholder) {
    notificationsStore.create({
      userId: newUserId,
      type: 'ADDED_TO_GROUP' as any,
      payload: {
        groupId,
        groupName: ledger.name,
        addedBy: actorUserId,
      },
    });
  }

  return ledger;
}

export function removeMember(
  groupId: string,
  actorUserId: string,
  targetUserId: string
) {
  const ledger = inMemoryLedgers.get(groupId);
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

  activityStore.log({
    ledgerId: groupId,
    actorUserId,
    action: isSelf ? 'MEMBER_LEFT' : 'MEMBER_REMOVED',
    entityType: 'member',
    entityId: targetUserId,
  });

  return ledger;
}

export function deleteGroup(groupId: string, actorUserId: string) {
  const ledger = inMemoryLedgers.get(groupId);
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
  return { success: true };
}

export function getGroupDashboard(groupId: string, callerUserId: string) {
  const details = getGroupDetails(groupId, callerUserId);
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

  const memberBars = details.members.map((mem) => ({
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

export function getGroupGraph(
  groupId: string,
  callerUserId: string,
  mode: 'simplified' | 'actual' = 'simplified'
) {
  const details = getGroupDetails(groupId, callerUserId);
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

  const nodes = details.members.map((mem) => ({
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
