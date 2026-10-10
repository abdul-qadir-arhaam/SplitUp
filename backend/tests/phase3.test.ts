import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app.js';
import { inMemoryUsers, createUser } from '../src/modules/users/store.js';
import { inMemoryFriendships, addFriend } from '../src/modules/friends/store.js';
import { inMemoryLedgers } from '../src/modules/ledgers/routes.js';
import { inMemorySettlements, inMemorySettlementEvents } from '../src/modules/settlements/store.js';
import { notificationsStore } from '../src/modules/notifications/store.js';
import { activityStore } from '../src/modules/activity/store.js';
import { runSettlementRemindersJob } from '../src/modules/settlements/reminders.js';

describe('Phase 3: Individual Ledger, Expenses and Settlements', () => {
  const userA = 'usr_alice';
  const userB = 'usr_bob';

  beforeEach(() => {
    inMemoryUsers.clear();
    inMemoryFriendships.clear();
    inMemoryLedgers.clear();
    inMemorySettlements.clear();
    inMemorySettlementEvents.length = 0;
    notificationsStore.clear();
    activityStore.clear();

    // Create test users
    createUser({
      id: userA,
      name: 'Alice',
      phoneE164: '+919999900001',
      isPlaceholder: false,
    });
    createUser({
      id: userB,
      name: 'Bob',
      phoneE164: '+919999900002',
      isPlaceholder: false,
    });

    // Create friendship between Alice and Bob
    addFriend({
      ownerUserId: userA,
      phone: '+919999900002',
    });
  });

  function getAliceBobLedgerId(): string {
    for (const ledger of inMemoryLedgers.values()) {
      if (
        ledger.type === 'INDIVIDUAL' &&
        ledger.memberIds.includes(userA) &&
        ledger.memberIds.includes(userB)
      ) {
        return ledger.id;
      }
    }
    throw new Error('Ledger not found');
  }

  it('Scenario 5: Full settlement confirm lifecycle updates balances to zero', async () => {
    const ledgerId = getAliceBobLedgerId();

    // 1. Bob pays Rs 1,000 (100,000 paise) dinner, split equally with Alice
    const expRes = await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userB)
      .send({
        title: 'Dinner at Olive',
        totalPaise: 100000,
        category: 'food',
        splitType: 'EQUAL',
        payers: [{ userId: userB, paidPaise: 100000 }],
        participants: [
          { userId: userB, included: true },
          { userId: userA, included: true },
        ],
      });
    expect(expRes.status).toBe(201);

    // Check balances: Alice owes 50,000 paise (-50000), Bob is owed 50,000 paise (+50000)
    const balRes1 = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes1.body.data.balances[userA]).toBe(-50000);
    expect(balRes1.body.data.balances[userB]).toBe(50000);

    // Rule 1: Bob (creditor) cannot initiate a settlement where he pays
    const invalidSettle = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userB)
      .send({
        ledgerId,
        toUserId: userA,
        amountPaise: 50000,
      });
    expect(invalidSettle.status).toBe(400);

    // Rule 7: Alice cannot overpay (e.g. 60,000 paise)
    const overpayRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: userB,
        amountPaise: 60000,
      });
    expect(overpayRes.status).toBe(400);

    // Alice creates settlement for full 50,000 paise
    const settleRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: userB,
        amountPaise: 50000,
        method: 'UPI',
      });
    expect(settleRes.status).toBe(201);
    const settlementId = settleRes.body.data.id;
    expect(settleRes.body.data.status).toBe('PENDING');

    // Rule 4: Pending settlements do NOT change balances
    const balRes2 = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes2.body.data.balances[userA]).toBe(-50000);

    // Receiver Bob has open notification
    const notifs = notificationsStore.listForUser(userB);
    expect(notifs.length).toBeGreaterThan(0);
    expect(notifs[0].type).toBe('SETTLEMENT_REQUESTED');
    expect(notifs[0].actionState).toBe('OPEN');

    // Bob confirms the settlement
    const confirmRes = await request(app)
      .post(`/v1/settlements/${settlementId}/confirm`)
      .set('x-user-id', userB);
    expect(confirmRes.status).toBe(200);
    expect(confirmRes.body.data.status).toBe('CONFIRMED');

    // Balances are now 0 for both!
    const balRes3 = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes3.body.data.balances[userA]).toBe(0);
    expect(balRes3.body.data.balances[userB]).toBe(0);

    // User totals for Alice
    const totalsRes = await request(app)
      .get('/v1/users/me/totals')
      .set('x-user-id', userA);
    expect(totalsRes.body.data.totalOwedPaise).toBe(0);
    expect(totalsRes.body.data.totalReceivablePaise).toBe(0);
    expect(totalsRes.body.data.netPaise).toBe(0);
  });

  it('Scenario 6: Rejection leaves balances unchanged and resubmit links old record', async () => {
    const ledgerId = getAliceBobLedgerId();

    // Bob pays 500 (50,000 paise), Alice owes 25,000 paise
    await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userB)
      .send({
        title: 'Coffee',
        totalPaise: 50000,
        category: 'food',
        splitType: 'EQUAL',
        payers: [{ userId: userB, paidPaise: 50000 }],
        participants: [
          { userId: userB, included: true },
          { userId: userA, included: true },
        ],
      });

    // Alice creates settlement
    const settleRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: userB,
        amountPaise: 25000,
      });
    const settlementId = settleRes.body.data.id;

    // Bob rejects it
    const rejectRes = await request(app)
      .post(`/v1/settlements/${settlementId}/reject`)
      .set('x-user-id', userB);
    expect(rejectRes.status).toBe(200);
    expect(rejectRes.body.data.status).toBe('REJECTED');

    // Balance remains unchanged: Alice still owes 25,000 paise
    const balRes = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes.body.data.balances[userA]).toBe(-25000);

    // Alice resubmits
    const resubmitRes = await request(app)
      .post(`/v1/settlements/${settlementId}/resubmit`)
      .set('x-user-id', userA)
      .send({ amountPaise: 25000 });
    expect(resubmitRes.status).toBe(200);
    const newSettlementId = resubmitRes.body.data.id;
    expect(resubmitRes.body.data.status).toBe('PENDING');

    // Check old record has replaced_by_id linked
    const oldRecord = await request(app)
      .get(`/v1/settlements/${settlementId}`)
      .set('x-user-id', userA);
    expect(oldRecord.body.data.replacedById).toBe(newSettlementId);

    // Bob confirms new settlement
    await request(app)
      .post(`/v1/settlements/${newSettlementId}/confirm`)
      .set('x-user-id', userB);

    const balFinal = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balFinal.body.data.balances[userA]).toBe(0);
  });

  it('Scenario 7: Outdated detection when intermediate expense reduces amount', async () => {
    const ledgerId = getAliceBobLedgerId();

    // Bob pays 100,000 paise, Alice owes 50,000 paise
    await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userB)
      .send({
        title: 'Cab ride',
        totalPaise: 100000,
        category: 'travel',
        splitType: 'EQUAL',
        payers: [{ userId: userB, paidPaise: 100000 }],
        participants: [
          { userId: userB, included: true },
          { userId: userA, included: true },
        ],
      });

    // Alice requests settlement of 50,000 paise
    const settleRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: userB,
        amountPaise: 50000,
      });
    const settlementId = settleRes.body.data.id;

    // Before Bob confirms, Alice pays 80,000 paise for groceries, split equally
    // Bob owes 40,000 paise. So Alice net balance changes: -50000 + 40000 = -10000 paise!
    await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userA)
      .send({
        title: 'Groceries',
        totalPaise: 80000,
        category: 'groceries',
        splitType: 'EQUAL',
        payers: [{ userId: userA, paidPaise: 80000 }],
        participants: [
          { userId: userA, included: true },
          { userId: userB, included: true },
        ],
      });

    // Bob attempts to confirm the 50,000 paise settlement -> Rejected as SETTLEMENT_OUTDATED
    const confirmRes = await request(app)
      .post(`/v1/settlements/${settlementId}/confirm`)
      .set('x-user-id', userB);
    expect(confirmRes.status).toBe(409);
    expect(confirmRes.body.error.code).toBe('SETTLEMENT_OUTDATED');

    // Settlement status is now OUTDATED
    const checkRes = await request(app)
      .get(`/v1/settlements/${settlementId}`)
      .set('x-user-id', userA);
    expect(checkRes.body.data.status).toBe('OUTDATED');

    // Resubmit pre-fills with current debt (10,000 paise)
    const resubmitRes = await request(app)
      .post(`/v1/settlements/${settlementId}/resubmit`)
      .set('x-user-id', userA);
    expect(resubmitRes.status).toBe(200);
    expect(resubmitRes.body.data.amountPaise).toBe(10000);

    // Bob confirms the 10,000 paise settlement
    await request(app)
      .post(`/v1/settlements/${resubmitRes.body.data.id}/confirm`)
      .set('x-user-id', userB);

    const balFinal = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balFinal.body.data.balances[userA]).toBe(0);
  });

  it('Placeholder receiver: Creator confirms on behalf as self-confirmed (unverified)', async () => {
    // Alice adds a contact who is not on the app -> creates placeholder Charlie
    const addRes = await addFriend({
      ownerUserId: userA,
      phone: '+919999900003',
      name: 'Charlie',
    });
    const charlieId = addRes.friend.id;
    const ledgerId = addRes.ledgerId;

    // Charlie paid 20,000 paise for tickets (Alice owes Charlie 10,000 paise)
    await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userA)
      .send({
        title: 'Movie tickets',
        totalPaise: 20000,
        category: 'tickets',
        splitType: 'EQUAL',
        payers: [{ userId: charlieId, paidPaise: 20000 }],
        participants: [
          { userId: charlieId, included: true },
          { userId: userA, included: true },
        ],
      });

    // Alice settles with Charlie. Since Alice is Charlie's creator, it is immediately confirmed on behalf!
    const settleRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: charlieId,
        amountPaise: 10000,
      });
    expect(settleRes.status).toBe(201);
    expect(settleRes.body.data.status).toBe('CONFIRMED');
    expect(settleRes.body.data.confirmedOnBehalf).toBe(true);

    // Balances are immediately 0
    const balRes = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes.body.data.balances[userA]).toBe(0);
    expect(balRes.body.data.balances[charlieId]).toBe(0);
  });

  it('Expense soft delete and dispute flow', async () => {
    const ledgerId = getAliceBobLedgerId();

    const expRes = await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userA)
      .send({
        title: 'Lunch',
        totalPaise: 40000,
        category: 'food',
        splitType: 'EQUAL',
        payers: [{ userId: userA, paidPaise: 40000 }],
        participants: [
          { userId: userA, included: true },
          { userId: userB, included: true },
        ],
      });
    const expId = expRes.body.data.id;

    // Bob disputes the expense
    const disputeRes = await request(app)
      .post(`/v1/expenses/${expId}/dispute`)
      .set('x-user-id', userB);
    expect(disputeRes.status).toBe(201);
    expect(disputeRes.body.data.isDisputed).toBe(true);

    // Dispute does NOT alter balance (Bob still owes 20,000 paise)
    const balRes1 = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes1.body.data.balances[userB]).toBe(-20000);

    // Creator Alice deletes the expense (soft delete)
    const deleteRes = await request(app)
      .delete(`/v1/expenses/${expId}`)
      .set('x-user-id', userA);
    expect(deleteRes.status).toBe(200);

    // Balances return to 0!
    const balRes2 = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balRes2.body.data.balances[userB]).toBe(0);
  });

  it('Settlement reminder job increments reminder count for pending settlements', async () => {
    const ledgerId = getAliceBobLedgerId();

    await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userB)
      .send({
        title: 'Cab',
        totalPaise: 20000,
        category: 'travel',
        splitType: 'EQUAL',
        payers: [{ userId: userB, paidPaise: 20000 }],
        participants: [
          { userId: userB, included: true },
          { userId: userA, included: true },
        ],
      });

    const settleRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: userB,
        amountPaise: 10000,
      });

    const result = runSettlementRemindersJob(0); // 0 threshold for instant test
    expect(result.remindedCount).toBe(1);

    const check = inMemorySettlements.get(settleRes.body.data.id);
    expect(check?.reminderCount).toBe(1);
    expect(check?.lastRemindedAt).toBeDefined();
  });

  it('Concurrency: two simultaneous confirms of the same request produce one result', async () => {
    const ledgerId = getAliceBobLedgerId();

    await request(app)
      .post(`/v1/ledgers/${ledgerId}/expenses`)
      .set('x-user-id', userB)
      .send({
        title: 'Snacks',
        totalPaise: 20000,
        category: 'food',
        splitType: 'EQUAL',
        payers: [{ userId: userB, paidPaise: 20000 }],
        participants: [
          { userId: userB, included: true },
          { userId: userA, included: true },
        ],
      });

    const settleRes = await request(app)
      .post('/v1/settlements')
      .set('x-user-id', userA)
      .send({
        ledgerId,
        toUserId: userB,
        amountPaise: 10000,
      });

    const settlementId = settleRes.body.data.id;

    const [res1, res2] = await Promise.all([
      request(app).post(`/v1/settlements/${settlementId}/confirm`).set('x-user-id', userB),
      request(app).post(`/v1/settlements/${settlementId}/confirm`).set('x-user-id', userB),
    ]);

    const statuses = [res1.status, res2.status].sort();
    expect(statuses).toEqual([200, 409]);

    const balFinal = await request(app)
      .get(`/v1/ledgers/${ledgerId}/balances`)
      .set('x-user-id', userA);
    expect(balFinal.body.data.balances[userA]).toBe(0);
  });
});
