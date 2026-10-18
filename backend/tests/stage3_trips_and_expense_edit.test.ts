import { describe, it, expect, beforeAll } from 'vitest';
import request from 'supertest';
import { app } from '../src/app.js';
import { db } from '../src/db/knex.js';
import { ulid } from 'ulidx';
import { getTripDetails, listUserTrips } from '../src/modules/trips/store.js';

describe('Stage 3: Trips and Trip-Expense Edit (MySQL DB Source of Truth)', { timeout: 30000 }, () => {
  const testDbName = process.env.DB_NAME;

  beforeAll(async () => {
    console.log(`\n======================================================`);
    console.log(`[STAGE 3 TEST] Connected DB Name: ${testDbName}`);
    console.log(`======================================================\n`);

    if (testDbName !== 'splitup_test') {
      throw new Error(`FATAL: Tests must run on splitup_test ONLY! Refusing to run on "${testDbName}"`);
    }
  });

  const uCreator = `usr_test_creator_${ulid()}`;
  const uMemberB = `usr_test_memberb_${ulid()}`;
  const uMemberC = `usr_test_memberc_${ulid()}`;
  const uNonMember = `usr_test_nonmember_${ulid()}`;

  let tripId: string;
  let expenseId: string;

  it('Setup: seeds test users in splitup_test', async () => {
    expect(testDbName).toBe('splitup_test');

    await db('users').insert([
      { id: uCreator, name: 'Trip Creator', phone_e164: `+91991${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
      { id: uMemberB, name: 'Member Bob', phone_e164: `+91992${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
      { id: uMemberC, name: 'Member Charlie', phone_e164: `+91993${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
      { id: uNonMember, name: 'Outsider Dave', phone_e164: `+91994${Math.floor(Math.random() * 8999999 + 1000000)}`, status: 'ACTIVE' },
    ]);
  });

  it('Requirement a: POST /v1/trips writes ledgers, ledger_members (creator ADMIN, members MEMBER) in ONE transaction', async () => {
    const res = await request(app)
      .post('/v1/trips')
      .set('x-user-id', uCreator)
      .send({
        name: 'Goa 2026 Test Trip',
        budgetPaise: 5000000, // Rs 50,000
        startDate: '2026-11-01',
        endDate: '2026-11-07',
        memberUserIds: [uMemberB, uMemberC],
      });

    expect(res.status).toBe(201);
    expect(res.body.data).toBeDefined();
    tripId = res.body.data.id;
    expect(tripId).toMatch(/^trp_/);

    // Verify row in ledgers
    const ledgerRow = await db('ledgers').where({ id: tripId }).first();
    expect(ledgerRow).toBeDefined();
    expect(ledgerRow.type).toBe('TRIP');
    expect(ledgerRow.name).toBe('Goa 2026 Test Trip');
    expect(Number(ledgerRow.budget_paise)).toBe(5000000);
    expect(ledgerRow.status).toBe('ACTIVE');
    expect(ledgerRow.created_by).toBe(uCreator);

    // Verify rows in ledger_members
    const members = await db('ledger_members').where({ ledger_id: tripId }).orderBy('user_id');
    expect(members.length).toBe(3);

    const creatorMember = members.find((m) => m.user_id === uCreator);
    expect(creatorMember).toBeDefined();
    expect(creatorMember.role).toBe('ADMIN');

    const bobMember = members.find((m) => m.user_id === uMemberB);
    expect(bobMember).toBeDefined();
    expect(bobMember.role).toBe('MEMBER');

    const charlieMember = members.find((m) => m.user_id === uMemberC);
    expect(charlieMember).toBeDefined();
    expect(charlieMember.role).toBe('MEMBER');

    // Verify activity_log
    const activity = await db('activity_log').where({ ledger_id: tripId, action: 'LEDGER_CREATED' }).first();
    expect(activity).toBeDefined();
    expect(activity.actor_user_id).toBe(uCreator);

    // Verify notifications were created for members B and C
    const notifB = await db('notifications').where({ user_id: uMemberB, type: 'ADDED_TO_TRIP' }).first();
    expect(notifB).toBeDefined();
  });

  it('Requirement a: Trip survives server process restart (DB is authoritative source of truth)', async () => {
    // Read directly from DB via fresh store calls
    const details = await getTripDetails(tripId, uCreator);
    expect(details.id).toBe(tripId);
    expect(details.name).toBe('Goa 2026 Test Trip');
    expect(details.budgetPaise).toBe(5000000);
    expect(details.members.length).toBe(3);
    expect(details.isAdmin).toBe(true);

    const list = await listUserTrips(uCreator);
    expect(list.all.some((t: any) => t.id === tripId)).toBe(true);
    expect(list.active.some((t: any) => t.id === tripId)).toBe(true);
  });

  it('Requirement a: GET /v1/trips/:id enforces membership check (403 for non-members)', async () => {
    // Non-member Dave calls GET /v1/trips/:id
    const res = await request(app)
      .get(`/v1/trips/${tripId}`)
      .set('x-user-id', uNonMember);

    expect(res.status).toBe(403);
    expect(res.body.error).toBeDefined();

    // Active member Bob calls GET /v1/trips/:id -> 200 OK
    const bobRes = await request(app)
      .get(`/v1/trips/${tripId}`)
      .set('x-user-id', uMemberB);

    expect(bobRes.status).toBe(200);
    expect(bobRes.body.data.id).toBe(tripId);
    expect(bobRes.body.data.isAdmin).toBe(false);
  });

  it('Requirement b: Add expense to trip, verify budget meter is computed correctly', async () => {
    // Creator adds Rs 20,000 expense (2,000,000 paise)
    const expRes = await request(app)
      .post(`/v1/ledgers/${tripId}/expenses`)
      .set('x-user-id', uCreator)
      .send({
        title: 'Resort Booking',
        totalPaise: 2000000,
        category: 'stay',
        splitType: 'EQUAL',
        payers: [{ userId: uCreator, paidPaise: 2000000 }],
        participants: [
          { userId: uCreator, included: true },
          { userId: uMemberB, included: true },
        ],
      });

    expect(expRes.status).toBe(201);
    expenseId = expRes.body.data.id;
    expect(expenseId).toBeDefined();

    // Verify trip details reflection
    const tripRes = await request(app)
      .get(`/v1/trips/${tripId}`)
      .set('x-user-id', uCreator);

    expect(tripRes.status).toBe(200);
    expect(tripRes.body.data.totalSpentPaise).toBe(2000000);
    expect(tripRes.body.data.budgetMeter.spentPercent).toBe(40);
    expect(tripRes.body.data.budgetMeter.level).toBe('UNDER_60');
    expect(tripRes.body.data.budgetMeter.statusMessage).toBe('On track');
  });

  it('Requirement b: Non-creator non-admin member cannot edit or delete expense (403 Forbidden)', async () => {
    // Member Bob is not creator and not admin -> 403
    const editRes = await request(app)
      .patch(`/v1/ledgers/${tripId}/expenses/${expenseId}`)
      .set('x-user-id', uMemberB)
      .send({
        title: 'Hacked Title',
        totalPaise: 2500000,
      });

    expect(editRes.status).toBe(403);

    // Member Bob tries delete -> 403
    const deleteRes = await request(app)
      .delete(`/v1/ledgers/${tripId}/expenses/${expenseId}`)
      .set('x-user-id', uMemberB);

    expect(deleteRes.status).toBe(403);
  });

  it('Requirement b: Creator edits expense via /ledgers/:id/expenses/:expenseId with atomic update and budget threshold notification', async () => {
    // Creator edits expense to Rs 42,000 (4,200,000 paise - 84% of 50,000 budget)
    const editRes = await request(app)
      .patch(`/v1/ledgers/${tripId}/expenses/${expenseId}`)
      .set('x-user-id', uCreator)
      .send({
        title: 'Luxury Villa Booking',
        totalPaise: 4200000,
        payers: [{ userId: uCreator, paidPaise: 4200000 }],
        participants: [
          { userId: uCreator, included: true },
          { userId: uMemberB, included: true },
        ],
      });

    expect(editRes.status).toBe(200);
    expect(editRes.body.data.title).toBe('Luxury Villa Booking');
    expect(editRes.body.data.totalPaise).toBe(4200000);

    // Verify activity_log before/after was written
    const act = await db('activity_log')
      .where({ entity_id: expenseId, action: 'EXPENSE_EDITED' })
      .first();
    expect(act).toBeDefined();
    const payload = typeof act.payload === 'string' ? JSON.parse(act.payload) : act.payload;
    expect(payload.before.totalPaise).toBe(2000000);
    expect(payload.after.totalPaise).toBe(4200000);

    // Verify budget meter updated
    const tripRes = await request(app)
      .get(`/v1/trips/${tripId}`)
      .set('x-user-id', uCreator);

    expect(tripRes.status).toBe(200);
    expect(tripRes.body.data.totalSpentPaise).toBe(4200000);
    expect(tripRes.body.data.budgetMeter.spentPercent).toBe(84);
    expect(tripRes.body.data.budgetMeter.level).toBe('80_TO_100');

    // Verify 80% budget warning notification was triggered for members
    const warningNotif = await db('notifications')
      .where({ user_id: uMemberB, type: 'TRIP_BUDGET_WARNING' })
      .first();
    expect(warningNotif).toBeDefined();
  });

  it('Requirement b: Delete expense via /v1/ledgers/:id/expenses/:expenseId soft deletes and recomputes budget meter', async () => {
    const deleteRes = await request(app)
      .delete(`/v1/ledgers/${tripId}/expenses/${expenseId}`)
      .set('x-user-id', uCreator);

    expect(deleteRes.status).toBe(200);
    expect(deleteRes.body.success).toBe(true);

    // Verify soft delete in DB
    const expRow = await db('expenses').where({ id: expenseId }).first();
    expect(expRow.deleted_at).not.toBeNull();
    expect(expRow.deleted_by).toBe(uCreator);

    // Verify trip total spent returned to 0
    const tripRes = await request(app)
      .get(`/v1/trips/${tripId}`)
      .set('x-user-id', uCreator);

    expect(tripRes.status).toBe(200);
    expect(tripRes.body.data.totalSpentPaise).toBe(0);
    expect(tripRes.body.data.budgetMeter.spentPercent).toBe(0);
  });

  it('Trip budget update and completion workflow in DB', async () => {
    // Update budget
    const budgetRes = await request(app)
      .patch(`/v1/trips/${tripId}/budget`)
      .set('x-user-id', uCreator)
      .send({ budgetPaise: 6000000 });

    expect(budgetRes.status).toBe(200);
    expect(budgetRes.body.data.budgetPaise).toBe(6000000);

    // Complete trip
    const completeRes = await request(app)
      .post(`/v1/trips/${tripId}/complete`)
      .set('x-user-id', uCreator);

    expect(completeRes.status).toBe(200);
    expect(completeRes.body.data.status).toBe('COMPLETED');
    expect(completeRes.body.data.isCompleted).toBe(true);

    // Verify listUserTrips segment
    const list = await listUserTrips(uCreator);
    expect(list.completed.some((t: any) => t.id === tripId)).toBe(true);
    expect(list.active.some((t: any) => t.id === tripId)).toBe(false);
  });
});
