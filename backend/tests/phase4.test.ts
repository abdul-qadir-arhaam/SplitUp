import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app.js';
import { inMemoryUsers, createUser } from '../src/modules/users/store.js';
import { inMemoryFriendships, addFriend } from '../src/modules/friends/store.js';
import { inMemoryLedgers } from '../src/modules/ledgers/routes.js';
import { inMemorySettlements, inMemorySettlementEvents } from '../src/modules/settlements/store.js';
import { inMemoryOffsets } from '../src/modules/offsets/store.js';
import { notificationsStore } from '../src/modules/notifications/store.js';
import { activityStore } from '../src/modules/activity/store.js';

describe('Phase 4: Groups, Admin Rules, Graph, Simplification and Offsets', () => {
  const adminId = 'usr_alice';
  const memberBob = 'usr_bob';
  const memberCharlie = 'usr_charlie';
  const memberDavid = 'usr_david';
  const memberEva = 'usr_eva';

  beforeEach(() => {
    inMemoryUsers.clear();
    inMemoryFriendships.clear();
    inMemoryLedgers.clear();
    inMemorySettlements.clear();
    inMemorySettlementEvents.length = 0;
    inMemoryOffsets.clear();
    notificationsStore.clear();
    activityStore.clear();

    // Create 5 users
    [
      { id: adminId, name: 'Alice', phone: '+919999900001' },
      { id: memberBob, name: 'Bob', phone: '+919999900002' },
      { id: memberCharlie, name: 'Charlie', phone: '+919999900003' },
      { id: memberDavid, name: 'David', phone: '+919999900004' },
      { id: memberEva, name: 'Eva', phone: '+919999900005' },
    ].forEach((u) => {
      createUser({
        id: u.id,
        name: u.name,
        phoneE164: u.phone,
        isPlaceholder: false,
      });
    });

    // Friendship between Alice and Bob
    addFriend({
      ownerUserId: adminId,
      phone: '+919999900002',
    });
  });

  describe('Group CRUD and Admin Permissions', () => {
    it('creates group with creator as ADMIN, non-admin blocked from admin actions', async () => {
      // Create group by Alice
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Flatmates',
          memberUserIds: [memberBob, memberCharlie],
        });

      expect(createRes.status).toBe(201);
      const group = createRes.body.data;
      expect(group.name).toBe('Flatmates');
      expect(group.creatorUserId).toBe(adminId);
      expect(group.memberIds).toContain(adminId);
      expect(group.memberIds).toContain(memberBob);
      expect(group.memberIds).toContain(memberCharlie);

      const groupId = group.id;

      // Bob (member, non-admin) attempts to rename group -> Forbidden
      const renameRes = await request(app)
        .patch(`/v1/groups/${groupId}`)
        .set('x-user-id', memberBob)
        .send({ name: 'Bob House' });
      expect(renameRes.status).toBe(403);

      // Alice (admin) renames group -> Success
      const adminRenameRes = await request(app)
        .patch(`/v1/groups/${groupId}`)
        .set('x-user-id', adminId)
        .send({ name: 'Flatmates 2026' });
      expect(adminRenameRes.status).toBe(200);
      expect(adminRenameRes.body.data.name).toBe('Flatmates 2026');

      // Bob attempts to add memberDavid -> Forbidden
      const addRes = await request(app)
        .post(`/v1/groups/${groupId}/members`)
        .set('x-user-id', memberBob)
        .send({ userId: memberDavid });
      expect(addRes.status).toBe(403);

      // Alice adds memberDavid -> Success
      const adminAddRes = await request(app)
        .post(`/v1/groups/${groupId}/members`)
        .set('x-user-id', adminId)
        .send({ userId: memberDavid });
      expect(adminAddRes.status).toBe(201);
      expect(adminAddRes.body.data.memberIds).toContain(memberDavid);

      // Bob attempts to remove Charlie -> Forbidden
      const removeRes = await request(app)
        .delete(`/v1/groups/${groupId}/members/${memberCharlie}`)
        .set('x-user-id', memberBob);
      expect(removeRes.status).toBe(403);

      // Charlie leaves voluntarily (actor is Charlie himself) -> Success when balance is 0
      const leaveRes = await request(app)
        .delete(`/v1/groups/${groupId}/members/${memberCharlie}`)
        .set('x-user-id', memberCharlie);
      expect(leaveRes.status).toBe(200);
      expect(leaveRes.body.data.memberIds).not.toContain(memberCharlie);
    });

    it('prevents member removal or group deletion when unsettled balance exists', async () => {
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Trip Squad',
          memberUserIds: [memberBob],
        });
      const groupId = createRes.body.data.id;

      // Alice pays 2000 paise split equally between Alice and Bob (Bob owes 1000 paise)
      await request(app)
        .post(`/v1/ledgers/${groupId}/expenses`)
        .set('x-user-id', adminId)
        .send({
          title: 'Groceries',
          totalPaise: 2000,
          category: 'GROCERIES',
          splitType: 'EQUAL',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: adminId, paidPaise: 2000 }],
          participants: [
            { userId: adminId, included: true },
            { userId: memberBob, included: true },
          ],
        });

      // Bob tries to leave while having unsettled debt (-1000 paise)
      const leaveRes = await request(app)
        .delete(`/v1/groups/${groupId}/members/${memberBob}`)
        .set('x-user-id', memberBob);
      expect(leaveRes.status).toBe(400);
      expect(leaveRes.body.error.code).toBe('UNSETTLED_BALANCE');

      // Admin tries to remove Bob -> Blocked by unsettled balance
      const removeRes = await request(app)
        .delete(`/v1/groups/${groupId}/members/${memberBob}`)
        .set('x-user-id', adminId);
      expect(removeRes.status).toBe(400);
      expect(removeRes.body.error.code).toBe('UNSETTLED_BALANCE');

      // Admin tries to delete group -> Blocked by unsettled balance
      const deleteRes = await request(app)
        .delete(`/v1/groups/${groupId}`)
        .set('x-user-id', adminId);
      expect(deleteRes.status).toBe(400);
      expect(deleteRes.body.error.code).toBe('UNSETTLED_BALANCE');
    });
  });

  describe('Scenario 3: "Not there" Excluded Member', () => {
    it('excluded member receives 0 share and cannot be a payer', async () => {
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Dinner Gang',
          memberUserIds: [memberBob, memberCharlie],
        });
      const groupId = createRes.body.data.id;

      // Attempt 1: Charlie is excluded (Not there), but listed as a payer -> Validation Error
      const invalidRes = await request(app)
        .post(`/v1/ledgers/${groupId}/expenses`)
        .set('x-user-id', adminId)
        .send({
          title: 'Dinner at Olive',
          totalPaise: 3000,
          category: 'FOOD_AND_DRINKS',
          splitType: 'EQUAL',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: memberCharlie, paidPaise: 3000 }],
          participants: [
            { userId: adminId, included: true },
            { userId: memberBob, included: true },
            { userId: memberCharlie, included: false }, // "Not there"
          ],
        });
      expect(invalidRes.status).toBe(400);
      expect(invalidRes.body.error.message).toMatch(/cannot be a payer/i);

      // Attempt 2: Alice pays 3000 paise. Charlie is excluded.
      // Total 3000 split EQUAL among Alice and Bob (1500 each). Charlie owed = 0.
      const validRes = await request(app)
        .post(`/v1/ledgers/${groupId}/expenses`)
        .set('x-user-id', adminId)
        .send({
          title: 'Dinner at Olive',
          totalPaise: 3000,
          category: 'FOOD_AND_DRINKS',
          splitType: 'EQUAL',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: adminId, paidPaise: 3000 }],
          participants: [
            { userId: adminId, included: true },
            { userId: memberBob, included: true },
            { userId: memberCharlie, included: false },
          ],
        });
      expect(validRes.status).toBe(201);
      const expense = validRes.body.data;

      const charlieSplit = expense.splits.find((s: any) => s.userId === memberCharlie);
      expect(charlieSplit.owedPaise).toBe(0);

      const bobSplit = expense.splits.find((s: any) => s.userId === memberBob);
      expect(bobSplit.owedPaise).toBe(1500);

      const aliceSplit = expense.splits.find((s: any) => s.userId === adminId);
      expect(aliceSplit.owedPaise).toBe(1500);

      // Check group balances
      const balRes = await request(app)
        .get(`/v1/ledgers/${groupId}/balances`)
        .set('x-user-id', adminId);
      expect(balRes.status).toBe(200);
      expect(balRes.body.data.balances[memberCharlie]).toBe(0);
      expect(balRes.body.data.balances[memberBob]).toBe(-1500);
      expect(balRes.body.data.balances[adminId]).toBe(1500);
    });
  });

  describe('Scenario 4: 5 Members, 12 Expenses Graph and Simplification', () => {
    it('simplifies 12 varied expenses across 5 members into at most 4 transactions', async () => {
      const all5 = [adminId, memberBob, memberCharlie, memberDavid, memberEva];
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'The Five Roommates',
          memberUserIds: [memberBob, memberCharlie, memberDavid, memberEva],
        });
      const groupId = createRes.body.data.id;

      // Add 12 distinct expenses with different payers and participants
      const expenseConfigs = [
        { payer: adminId, amount: 5000, parts: [adminId, memberBob, memberCharlie, memberDavid, memberEva] },
        { payer: memberBob, amount: 2500, parts: [memberBob, memberCharlie] },
        { payer: memberCharlie, amount: 10000, parts: [adminId, memberCharlie, memberDavid] },
        { payer: memberDavid, amount: 4000, parts: [memberBob, memberDavid, memberEva] },
        { payer: memberEva, amount: 6000, parts: [adminId, memberEva] },
        { payer: adminId, amount: 3000, parts: [memberBob, memberDavid] },
        { payer: memberBob, amount: 7500, parts: [adminId, memberBob, memberCharlie, memberDavid, memberEva] },
        { payer: memberCharlie, amount: 1200, parts: [memberCharlie, memberEva] },
        { payer: memberDavid, amount: 9000, parts: [adminId, memberBob, memberDavid] },
        { payer: memberEva, amount: 3500, parts: [memberCharlie, memberDavid, memberEva] },
        { payer: adminId, amount: 4500, parts: [adminId, memberCharlie, memberEva] },
        { payer: memberBob, amount: 8000, parts: [memberBob, memberDavid] },
      ];

      for (let i = 0; i < expenseConfigs.length; i++) {
        const c = expenseConfigs[i];
        await request(app)
          .post(`/v1/ledgers/${groupId}/expenses`)
          .set('x-user-id', c.payer)
          .send({
            title: `Expense ${i + 1}`,
            totalPaise: c.amount,
            category: 'FOOD_AND_DRINKS',
            splitType: 'EQUAL',
            expenseDate: new Date().toISOString(),
            payers: [{ userId: c.payer, paidPaise: c.amount }],
            participants: all5.map((u) => ({
              userId: u,
              included: c.parts.includes(u),
            })),
          });
      }

      // Check Simplified Graph
      const simplifiedRes = await request(app)
        .get(`/v1/groups/${groupId}/graph?mode=simplified`)
        .set('x-user-id', adminId);
      expect(simplifiedRes.status).toBe(200);
      const simplifiedData = simplifiedRes.body.data;

      // Mathematical invariant: for N=5 members, maximum transactions is N-1 = 4
      expect(simplifiedData.links.length).toBeLessThanOrEqual(4);
      expect(simplifiedData.nodes.length).toBe(5);

      // Check Actual Graph (Pairwise debts)
      const actualRes = await request(app)
        .get(`/v1/groups/${groupId}/graph?mode=actual`)
        .set('x-user-id', adminId);
      expect(actualRes.status).toBe(200);
      const actualData = actualRes.body.data;
      expect(actualData.links.length).toBeGreaterThan(0);

      // Verify dashboard data is aggregated correctly
      const dashRes = await request(app)
        .get(`/v1/groups/${groupId}/dashboard`)
        .set('x-user-id', adminId);
      expect(dashRes.status).toBe(200);
      expect(dashRes.body.data.categoryBreakdown.length).toBeGreaterThan(0);
      expect(dashRes.body.data.memberMetrics.length).toBe(5);
    });
  });

  describe('Scenario 8: Group-to-Individual Offsets', () => {
    it('offsets Rs 60 against Rs 100 group debt, remainder Rs 40 settled normally', async () => {
      // 1. Group setup: Alice and Bob
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Flat Offsets Test',
          memberUserIds: [memberBob],
        });
      const groupId = createRes.body.data.id;

      // Alice owes Bob Rs 100 (10,000 paise) in GROUP
      // (Bob pays 10,000 paise for Alice)
      await request(app)
        .post(`/v1/ledgers/${groupId}/expenses`)
        .set('x-user-id', memberBob)
        .send({
          title: 'Bob paid for Alice in Group',
          totalPaise: 10000,
          category: 'GENERAL',
          splitType: 'EXACT',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: memberBob, paidPaise: 10000 }],
          participants: [
            { userId: memberBob, included: true, owedPaise: 0 },
            { userId: adminId, included: true, owedPaise: 10000 },
          ],
        });

      // 2. Individual setup: Bob owes Alice Rs 60 (6,000 paise) INDIVIDUALLY
      // Find individual ledger between Alice and Bob
      const indLedger = Array.from(inMemoryLedgers.values()).find(
        (l) => l.type === 'INDIVIDUAL' && l.memberIds.includes(adminId) && l.memberIds.includes(memberBob)
      )!;
      expect(indLedger).toBeDefined();

      // Alice pays 6,000 paise for Bob in individual ledger
      await request(app)
        .post(`/v1/ledgers/${indLedger.id}/expenses`)
        .set('x-user-id', adminId)
        .send({
          title: 'Alice paid for Bob individually',
          totalPaise: 6000,
          category: 'GENERAL',
          splitType: 'EXACT',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: adminId, paidPaise: 6000 }],
          participants: [
            { userId: adminId, included: true, owedPaise: 0 },
            { userId: memberBob, included: true, owedPaise: 6000 },
          ],
        });

      // 3. Offset suggestion check:
      // Alice owes Bob 100 in group, Bob owes Alice 60 individually.
      // Suggested offset should be min(100, 60) = 60.
      const suggRes = await request(app)
        .get(`/v1/groups/${groupId}/offset-suggestions`)
        .set('x-user-id', adminId);
      expect(suggRes.status).toBe(200);
      expect(suggRes.body.data.length).toBe(1);
      const suggestion = suggRes.body.data[0];
      expect(suggestion.toUserId).toBe(memberBob);
      expect(suggestion.maxOffsetPaise).toBe(6000);
      expect(suggestion.remainingGroupDebtPaise).toBe(4000);

      // 4. Alice initiates offset of Rs 60 (6000 paise)
      const offsetCreateRes = await request(app)
        .post('/v1/offsets')
        .set('x-user-id', adminId)
        .send({
          groupLedgerId: groupId,
          toUserId: memberBob,
          amountPaise: 6000,
        });
      expect(offsetCreateRes.status).toBe(201);
      const offsetRecord = offsetCreateRes.body.data;
      expect(offsetRecord.status).toBe('PENDING');
      const offsetId = offsetRecord.id;

      // Both settlements must exist under offsetId with status PENDING
      const groupStl = inMemoryLedgers.get(groupId)!.settlements.find((s: any) => s.offsetId === offsetId);
      const indStl = inMemoryLedgers.get(indLedger.id)!.settlements.find((s: any) => s.offsetId === offsetId);
      expect(groupStl).toBeDefined();
      expect(indStl).toBeDefined();
      expect(groupStl!.status).toBe('PENDING');
      expect(indStl!.status).toBe('PENDING');
      expect(groupStl!.fromUserId).toBe(adminId);
      expect(groupStl!.toUserId).toBe(memberBob);
      expect(indStl!.fromUserId).toBe(memberBob);
      expect(indStl!.toUserId).toBe(adminId);

      // 5. Bob confirms the offset
      const confirmRes = await request(app)
        .post(`/v1/offsets/${offsetId}/confirm`)
        .set('x-user-id', memberBob);
      expect(confirmRes.status).toBe(200);
      expect(confirmRes.body.data.status).toBe('CONFIRMED');

      // Both ledger settlements must now be CONFIRMED
      expect(groupStl!.status).toBe('CONFIRMED');
      expect(indStl!.status).toBe('CONFIRMED');

      // 6. Check updated balances:
      // Group: Alice owed 100, offset 60 -> Alice now owes 40 (4000 paise) to Bob
      const groupBalRes = await request(app)
        .get(`/v1/ledgers/${groupId}/balances`)
        .set('x-user-id', adminId);
      expect(groupBalRes.body.data.balances[adminId]).toBe(-4000);
      expect(groupBalRes.body.data.balances[memberBob]).toBe(4000);

      // Individual: Bob owed 60, offset 60 -> Individual balance is now 0
      const indBalRes = await request(app)
        .get(`/v1/ledgers/${indLedger.id}/balances`)
        .set('x-user-id', adminId);
      expect(indBalRes.body.data.balances[adminId]).toBe(0);
      expect(indBalRes.body.data.balances[memberBob]).toBe(0);

      // 7. Settle the remaining Rs 40 (4000 paise) normally in the group
      const stlRes = await request(app)
        .post('/v1/settlements')
        .set('x-user-id', adminId)
        .send({
          ledgerId: groupId,
          toUserId: memberBob,
          amountPaise: 4000,
          method: 'UPI',
        });
      expect(stlRes.status).toBe(201);
      const remainingStlId = stlRes.body.data.id;

      // Bob confirms remaining settlement
      await request(app)
        .post(`/v1/settlements/${remainingStlId}/confirm`)
        .set('x-user-id', memberBob);

      // Group balance is now completely settled (0 for both)
      const finalGroupBal = await request(app)
        .get(`/v1/ledgers/${groupId}/balances`)
        .set('x-user-id', adminId);
      expect(finalGroupBal.body.data.balances[adminId]).toBe(0);
      expect(finalGroupBal.body.data.balances[memberBob]).toBe(0);
    });

    it('rejection of an offset changes neither ledger', async () => {
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Reject Test Group',
          memberUserIds: [memberBob],
        });
      const groupId = createRes.body.data.id;

      // Alice owes Bob 5000 in group
      await request(app)
        .post(`/v1/ledgers/${groupId}/expenses`)
        .set('x-user-id', memberBob)
        .send({
          title: 'Group expense',
          totalPaise: 5000,
          category: 'GENERAL',
          splitType: 'EXACT',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: memberBob, paidPaise: 5000 }],
          participants: [
            { userId: memberBob, included: true, owedPaise: 0 },
            { userId: adminId, included: true, owedPaise: 5000 },
          ],
        });

      // Bob owes Alice 3000 in individual
      const indLedger = Array.from(inMemoryLedgers.values()).find(
        (l) => l.type === 'INDIVIDUAL' && l.memberIds.includes(adminId) && l.memberIds.includes(memberBob)
      )!;

      await request(app)
        .post(`/v1/ledgers/${indLedger.id}/expenses`)
        .set('x-user-id', adminId)
        .send({
          title: 'Ind expense',
          totalPaise: 3000,
          category: 'GENERAL',
          splitType: 'EXACT',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: adminId, paidPaise: 3000 }],
          participants: [
            { userId: adminId, included: true, owedPaise: 0 },
            { userId: memberBob, included: true, owedPaise: 3000 },
          ],
        });

      // Alice requests offset of 3000
      const offsetRes = await request(app)
        .post('/v1/offsets')
        .set('x-user-id', adminId)
        .send({
          groupLedgerId: groupId,
          toUserId: memberBob,
          amountPaise: 3000,
        });
      const offsetId = offsetRes.body.data.id;

      // Bob rejects
      const rejectRes = await request(app)
        .post(`/v1/offsets/${offsetId}/reject`)
        .set('x-user-id', memberBob);
      expect(rejectRes.status).toBe(200);
      expect(rejectRes.body.data.status).toBe('REJECTED');

      // Balances must remain unchanged
      const groupBal = await request(app)
        .get(`/v1/ledgers/${groupId}/balances`)
        .set('x-user-id', adminId);
      expect(groupBal.body.data.balances[adminId]).toBe(-5000);

      const indBal = await request(app)
        .get(`/v1/ledgers/${indLedger.id}/balances`)
        .set('x-user-id', adminId);
      expect(indBal.body.data.balances[adminId]).toBe(3000);
    });

    it('detects OUTDATED offset when balance changes before confirm', async () => {
      const createRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Outdated Test Group',
          memberUserIds: [memberBob],
        });
      const groupId = createRes.body.data.id;

      // Alice owes Bob 5000 in group
      await request(app)
        .post(`/v1/ledgers/${groupId}/expenses`)
        .set('x-user-id', memberBob)
        .send({
          title: 'Group exp',
          totalPaise: 5000,
          category: 'GENERAL',
          splitType: 'EXACT',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: memberBob, paidPaise: 5000 }],
          participants: [
            { userId: memberBob, included: true, owedPaise: 0 },
            { userId: adminId, included: true, owedPaise: 5000 },
          ],
        });

      // Bob owes Alice 3000 in individual
      const indLedger = Array.from(inMemoryLedgers.values()).find(
        (l) => l.type === 'INDIVIDUAL' && l.memberIds.includes(adminId) && l.memberIds.includes(memberBob)
      )!;

      await request(app)
        .post(`/v1/ledgers/${indLedger.id}/expenses`)
        .set('x-user-id', adminId)
        .send({
          title: 'Ind exp',
          totalPaise: 3000,
          category: 'GENERAL',
          splitType: 'EXACT',
          expenseDate: new Date().toISOString(),
          payers: [{ userId: adminId, paidPaise: 3000 }],
          participants: [
            { userId: adminId, included: true, owedPaise: 0 },
            { userId: memberBob, included: true, owedPaise: 3000 },
          ],
        });

      // Offset request for 3000
      const offsetRes = await request(app)
        .post('/v1/offsets')
        .set('x-user-id', adminId)
        .send({
          groupLedgerId: groupId,
          toUserId: memberBob,
          amountPaise: 3000,
        });
      const offsetId = offsetRes.body.data.id;

      // Now Bob settles 2000 in the individual ledger before confirming the offset
      const earlyStl = await request(app)
        .post('/v1/settlements')
        .set('x-user-id', memberBob)
        .send({
          ledgerId: indLedger.id,
          toUserId: adminId,
          amountPaise: 2000,
          method: 'CASH',
        });
      await request(app)
        .post(`/v1/settlements/${earlyStl.body.data.id}/confirm`)
        .set('x-user-id', adminId);

      // Now Bob only owes Alice 1000 in individual, but offset was for 3000!
      // Confirmation must fail with SETTLEMENT_OUTDATED
      const confirmRes = await request(app)
        .post(`/v1/offsets/${offsetId}/confirm`)
        .set('x-user-id', memberBob);
      expect(confirmRes.status).toBe(409);
      expect(confirmRes.body.error.code).toBe('SETTLEMENT_OUTDATED');
    });
  });

  describe('Common Groups on Friend Profile', () => {
    it('returns common groups in listFriends', async () => {
      // Create two groups with Alice and Bob
      await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'College Friends',
          memberUserIds: [memberBob],
        });

      await request(app)
        .post('/v1/groups')
        .set('x-user-id', adminId)
        .send({
          name: 'Flat 402',
          memberUserIds: [memberBob],
        });

      const friendsRes = await request(app)
        .get('/v1/friends')
        .set('x-user-id', adminId);

      expect(friendsRes.status).toBe(200);
      const bobFriend = friendsRes.body.data.find((f: any) => f.friendId === memberBob);
      expect(bobFriend).toBeDefined();
      expect(bobFriend.commonGroups).toContain('College Friends');
      expect(bobFriend.commonGroups).toContain('Flat 402');
    });
  });
});
