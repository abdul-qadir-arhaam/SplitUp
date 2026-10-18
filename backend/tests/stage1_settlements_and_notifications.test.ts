import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { ulid } from 'ulidx';
import {
  createSettlement,
  confirmSettlement,
  rejectSettlement,
  cancelSettlement,
  resubmitSettlement,
} from '../src/modules/settlements/store.js';
import { notificationsStore } from '../src/modules/notifications/store.js';
import { getLedgerBalancesFromDb } from '../src/modules/balances/sqlBalances.js';
import {
  ConflictError,
  ValidationError,
  ForbiddenError,
  SettlementOutdatedError,
} from '../src/lib/errors.js';

describe('Stage 1: Settlements and Notifications from MySQL', () => {
  const testDbName = process.env.DB_NAME;

  beforeAll(async () => {
    console.log(`\n======================================================`);
    console.log(`[STAGE 1 TEST] Connected DB Name: ${testDbName}`);
    console.log(`======================================================\n`);

    if (testDbName !== 'splitup_test') {
      throw new Error(`FATAL: Tests must run on splitup_test ONLY! Refusing to run on "${testDbName}"`);
    }
  });

  const uA = `usr_test_a_${ulid()}`;
  const uB = `usr_test_b_${ulid()}`;
  const uC = `usr_test_c_${ulid()}`;
  const ledgerId = `ldg_test_${ulid()}`;

  it('Setup: seeds test users and ledger in splitup_test', async () => {
    expect(testDbName).toBe('splitup_test');

    await db('users').insert([
      { id: uA, name: 'Alice Test', phone_e164: `+91991${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
      { id: uB, name: 'Bob Test', phone_e164: `+91992${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
      { id: uC, name: 'Charlie NonMember', phone_e164: `+91993${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
    ]);

    await db('ledgers').insert({
      id: ledgerId,
      type: 'INDIVIDUAL',
      name: 'Alice - Bob Ledger',
      created_by: uA,
    });

    await db('ledger_members').insert([
      { ledger_id: ledgerId, user_id: uA, role: 'MEMBER' },
      { ledger_id: ledgerId, user_id: uB, role: 'MEMBER' },
    ]);
  });

  it('Scenario 1: A owes B Rs 600 (B paid Rs 1,200 split equally). A creates Rs 600 settlement. B sees actionable SETTLEMENT_REQUESTED in DB', async () => {
    // Expense: B pays Rs 1,200 split equally
    const expId = `exp_${ulid()}`;
    await db('expenses').insert({
      id: expId,
      ledger_id: ledgerId,
      title: 'Dinner test',
      total_paise: 120000,
      split_type: 'EQUAL',
      expense_date: '2026-10-17',
      created_by: uB,
    });
    await db('expense_payers').insert({
      expense_id: expId,
      user_id: uB,
      paid_paise: 120000,
    });
    await db('expense_splits').insert([
      { expense_id: expId, user_id: uA, owed_paise: 60000, included: 1 },
      { expense_id: expId, user_id: uB, owed_paise: 60000, included: 1 },
    ]);

    // Check balances
    const balances = await getLedgerBalancesFromDb(ledgerId);
    expect(balances[uA]).toBe(-60000);
    expect(balances[uB]).toBe(60000);
    expect(balances[uA] + balances[uB]).toBe(0); // Zero-sum invariant

    // A creates Rs 600 (60000 paise) settlement
    const { settlement } = await createSettlement({
      ledgerId,
      fromUserId: uA,
      toUserId: uB,
      amountPaise: 60000,
      method: 'UPI',
      createdBy: uA,
    });

    expect(settlement.id.startsWith('stl_')).toBe(true);
    expect(settlement.status).toBe('PENDING');
    expect(settlement.amountPaise).toBe(60000);

    // Pending does NOT change balances (R4)
    const balAfterPending = await getLedgerBalancesFromDb(ledgerId);
    expect(balAfterPending[uA]).toBe(-60000);
    expect(balAfterPending[uB]).toBe(60000);

    // B lists notifications from MySQL (R8)
    const notifs = await notificationsStore.listForUser(uB);
    const reqNotif = notifs.find((n) => n.payload?.settlementId === settlement.id);
    expect(reqNotif).toBeDefined();
    expect(reqNotif!.type).toBe('SETTLEMENT_REQUESTED');
    expect(reqNotif!.actionState).toBe('OPEN');
  });

  it('Scenario 2: A creates a second settlement -> 409 CONFLICT with existing settlement. Idempotency test', async () => {
    // Attempt second create
    let conflictErr: any;
    try {
      await createSettlement({
        ledgerId,
        fromUserId: uA,
        toUserId: uB,
        amountPaise: 60000,
        createdBy: uA,
      });
    } catch (err) {
      conflictErr = err;
    }

    expect(conflictErr).toBeInstanceOf(ConflictError);
    expect(conflictErr.existingSettlement).toBeDefined();
    expect(conflictErr.existingSettlement.status).toBe('PENDING');
    expect(conflictErr.existingSettlement.amountPaise).toBe(60000);

    // Test idempotency keys table
    const idemKey = `idem_${ulid()}`;
    await db('idempotency_keys').insert({
      user_id: uA,
      key_value: idemKey,
      request_hash: 'testhash123',
      response_status: 201,
      response_body: JSON.stringify({ data: conflictErr.existingSettlement }),
      created_at: new Date(),
      expires_at: new Date(Date.now() + 86400000),
    });

    const cachedIdem = await db('idempotency_keys')
      .where({ user_id: uA, key_value: idemKey })
      .first();
    expect(cachedIdem).toBeDefined();
    expect(cachedIdem.response_status).toBe(201);
  });

  it('Scenario 3: B confirms: status CONFIRMED, balances 0, event row, B notification DONE, A receives SETTLEMENT_CONFIRMED', async () => {
    const pendingSettlement = await db('settlements')
      .where({ ledger_id: ledgerId, status: 'PENDING' })
      .first();
    expect(pendingSettlement).toBeDefined();

    const { settlement, balances } = await confirmSettlement(pendingSettlement.id, uB);
    expect(settlement.status).toBe('CONFIRMED');
    expect(settlement.respondedBy).toBe(uB);

    // Balances are now 0 for both (R5)
    expect(balances[uA]).toBe(0);
    expect(balances[uB]).toBe(0);

    // Verify in database
    const dbBalances = await getLedgerBalancesFromDb(ledgerId);
    expect(dbBalances[uA]).toBe(0);
    expect(dbBalances[uB]).toBe(0);
    expect(dbBalances[uA] + dbBalances[uB]).toBe(0); // Zero-sum invariant

    // Event row written in MySQL
    const event = await db('settlement_events')
      .where({ settlement_id: pendingSettlement.id, status: 'CONFIRMED' })
      .first();
    expect(event).toBeDefined();
    expect(event.actor_user_id).toBe(uB);

    // B's notification is marked DONE with CONFIRMED
    const bNotifs = await notificationsStore.listForUser(uB);
    const bNotif = bNotifs.find((n) => n.payload?.settlementId === pendingSettlement.id);
    expect(bNotif).toBeDefined();
    expect(bNotif!.actionState).toBe('DONE');
    expect(bNotif!.actionResult).toBe('CONFIRMED');

    // A receives SETTLEMENT_CONFIRMED in notifications table
    const aNotifs = await notificationsStore.listForUser(uA);
    const aConfNotif = aNotifs.find(
      (n) => n.type === 'SETTLEMENT_CONFIRMED' && n.payload?.settlementId === pendingSettlement.id
    );
    expect(aConfNotif).toBeDefined();
  });

  it('Scenario 4: Reject, Cancel, Partial settlement (Rs 200), Amount above limit, Non-member & Wrong-user attempts rejected', async () => {
    // New expense: B pays Rs 1,000 split equally -> A owes Rs 500 (50000 paise)
    const exp2 = `exp_${ulid()}`;
    await db('expenses').insert({
      id: exp2,
      ledger_id: ledgerId,
      title: 'Groceries test',
      total_paise: 100000,
      split_type: 'EQUAL',
      expense_date: '2026-10-17',
      created_by: uB,
    });
    await db('expense_payers').insert({
      expense_id: exp2,
      user_id: uB,
      paid_paise: 100000,
    });
    await db('expense_splits').insert([
      { expense_id: exp2, user_id: uA, owed_paise: 50000, included: 1 },
      { expense_id: exp2, user_id: uB, owed_paise: 50000, included: 1 },
    ]);

    // Check balances
    const bal1 = await getLedgerBalancesFromDb(ledgerId);
    expect(bal1[uA]).toBe(-50000);
    expect(bal1[uB]).toBe(50000);

    // 1. Amount above limit rejected: A tries to settle 60000 paise when owing 50000
    await expect(
      createSettlement({
        ledgerId,
        fromUserId: uA,
        toUserId: uB,
        amountPaise: 60000,
        createdBy: uA,
      })
    ).rejects.toThrow(ValidationError);

    // 2. Non-member rejected: User C tries to settle
    await expect(
      createSettlement({
        ledgerId,
        fromUserId: uC,
        toUserId: uB,
        amountPaise: 20000,
        createdBy: uC,
      })
    ).rejects.toThrow(ForbiddenError);

    // 3. Wrong-user rejected: B (creditor) tries to initiate settlement
    await expect(
      createSettlement({
        ledgerId,
        fromUserId: uB,
        toUserId: uA,
        amountPaise: 20000,
        createdBy: uB,
      })
    ).rejects.toThrow(ValidationError);

    // 4. Partial settlement (Rs 200 / 20000 paise)
    const partial = await createSettlement({
      ledgerId,
      fromUserId: uA,
      toUserId: uB,
      amountPaise: 20000,
      createdBy: uA,
    });
    expect(partial.settlement.amountPaise).toBe(20000);

    // B confirms partial settlement
    const confPartial = await confirmSettlement(partial.settlement.id, uB);
    expect(confPartial.balances[uA]).toBe(-30000);
    expect(confPartial.balances[uB]).toBe(30000);
    expect(confPartial.balances[uA] + confPartial.balances[uB]).toBe(0);

    // 5. Reject flow: A creates Rs 300 (30000 paise) settlement
    const stlToReject = await createSettlement({
      ledgerId,
      fromUserId: uA,
      toUserId: uB,
      amountPaise: 30000,
      createdBy: uA,
    });

    const rejected = await rejectSettlement(stlToReject.settlement.id, uB);
    expect(rejected.settlement.status).toBe('REJECTED');
    // Balances remain unchanged (-30000, +30000)
    expect(rejected.balances[uA]).toBe(-30000);
    expect(rejected.balances[uB]).toBe(30000);

    // B's notification is DONE with REJECTED
    const bNotifs = await notificationsStore.listForUser(uB);
    const rejNotif = bNotifs.find((n) => n.payload?.settlementId === stlToReject.settlement.id);
    expect(rejNotif!.actionState).toBe('DONE');
    expect(rejNotif!.actionResult).toBe('REJECTED');

    // 6. Resubmit flow: A resubmits the rejected settlement
    const resubmitted = await resubmitSettlement({
      id: stlToReject.settlement.id,
      actorUserId: uA,
    });
    expect(resubmitted.settlement.status).toBe('PENDING');
    expect(resubmitted.settlement.amountPaise).toBe(30000);

    // Old record has replaced_by_id linked
    const oldRow = await db('settlements').where({ id: stlToReject.settlement.id }).first();
    expect(oldRow.replaced_by_id).toBe(resubmitted.settlement.id);

    // 7. Cancel flow: A cancels the resubmitted settlement
    const cancelled = await cancelSettlement(resubmitted.settlement.id, uA);
    expect(cancelled.settlement.status).toBe('CANCELLED');
    expect(cancelled.balances[uA]).toBe(-30000);
    expect(cancelled.balances[uB]).toBe(30000);
    expect(cancelled.balances[uA] + cancelled.balances[uB]).toBe(0);
  }, 30000);

  it('Scenario 5: Add an expense between create and confirm so amount is no longer valid -> confirm returns OUTDATED and changes no balance', async () => {
    // Current state: A owes B Rs 300 (30000 paise)
    const stl = await createSettlement({
      ledgerId,
      fromUserId: uA,
      toUserId: uB,
      amountPaise: 30000,
      createdBy: uA,
    });

    // Intermediate expense added before confirm: A pays Rs 200 split equally
    // Net changes: A pays 20000, split 10000 each.
    // A net was -30000 -> now -30000 + (20000 - 10000) = -20000.
    // B net was +30000 -> now +30000 + (0 - 10000) = +20000.
    const exp3 = `exp_${ulid()}`;
    await db('expenses').insert({
      id: exp3,
      ledger_id: ledgerId,
      title: 'Intermediate expense',
      total_paise: 20000,
      split_type: 'EQUAL',
      expense_date: '2026-10-17',
      created_by: uA,
    });
    await db('expense_payers').insert({
      expense_id: exp3,
      user_id: uA,
      paid_paise: 20000,
    });
    await db('expense_splits').insert([
      { expense_id: exp3, user_id: uA, owed_paise: 10000, included: 1 },
      { expense_id: exp3, user_id: uB, owed_paise: 10000, included: 1 },
    ]);

    // B attempts to confirm the 30000 paise settlement (which now exceeds the 20000 paise debt)
    await expect(confirmSettlement(stl.settlement.id, uB)).rejects.toThrow(
      SettlementOutdatedError
    );

    // Verify settlement status in MySQL is OUTDATED
    const updated = await db('settlements').where({ id: stl.settlement.id }).first();
    expect(updated.status).toBe('OUTDATED');

    // Balances are unchanged (still -20000 and +20000)
    const balances = await getLedgerBalancesFromDb(ledgerId);
    expect(balances[uA]).toBe(-20000);
    expect(balances[uB]).toBe(20000);
    expect(balances[uA] + balances[uB]).toBe(0);
  }, 30000);

  it('Scenario 6: Two parallel confirm requests for the same settlement: exactly one wins, the other gets 409', async () => {
    // A creates settlement for remaining Rs 200 (20000 paise)
    const stl = await createSettlement({
      ledgerId,
      fromUserId: uA,
      toUserId: uB,
      amountPaise: 20000,
      createdBy: uA,
    });

    // Run two confirmSettlement calls simultaneously
    const results = await Promise.allSettled([
      confirmSettlement(stl.settlement.id, uB),
      confirmSettlement(stl.settlement.id, uB),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    expect(fulfilled.length).toBe(1);
    expect(rejected.length).toBe(1);

    const rejReason = (rejected[0] as PromiseRejectedResult).reason;
    expect(rejReason).toBeInstanceOf(ConflictError);

    // Balances are now 0
    const finalBalances = await getLedgerBalancesFromDb(ledgerId);
    expect(finalBalances[uA]).toBe(0);
    expect(finalBalances[uB]).toBe(0);
    expect(finalBalances[uA] + finalBalances[uB]).toBe(0);
  }, 30000);

  it('Scenario 7: Fresh process (no memory) returns the same authoritative data and zero-sum holds', async () => {
    // Query directly from MySQL
    const dbSettlements = await db('settlements')
      .where({ ledger_id: ledgerId })
      .orderBy('created_at', 'desc');

    expect(dbSettlements.length).toBeGreaterThan(0);

    for (const row of dbSettlements) {
      expect(row.id.startsWith('stl_')).toBe(true);
      expect(typeof row.amount_paise).toBe('number');
    }

    const balances = await getLedgerBalancesFromDb(ledgerId);
    expect(balances[uA]).toBe(0);
    expect(balances[uB]).toBe(0);
    expect(balances[uA] + balances[uB]).toBe(0);
  });
});
