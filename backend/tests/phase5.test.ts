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

describe('Phase 5: Trips, Budget Meter, Graph and Isolation', () => {
  const creatorId = 'usr_arhaam';
  const memberRahul = 'usr_rahul';
  const memberPriya = 'usr_priya';
  const memberAmit = 'usr_amit';

  beforeEach(() => {
    inMemoryUsers.clear();
    inMemoryFriendships.clear();
    inMemoryLedgers.clear();
    inMemorySettlements.clear();
    inMemorySettlementEvents.length = 0;
    inMemoryOffsets.clear();
    notificationsStore.clear();
    activityStore.clear();

    // Create test users
    [
      { id: creatorId, name: 'Arhaam', phone: '+919999900001' },
      { id: memberRahul, name: 'Rahul', phone: '+919999900002' },
      { id: memberPriya, name: 'Priya', phone: '+919999900003' },
      { id: memberAmit, name: 'Amit', phone: '+919999900004' },
    ].forEach((u) => {
      createUser({
        id: u.id,
        name: u.name,
        phoneE164: u.phone,
        isPlaceholder: false,
      });
    });

    // Friendship between Arhaam and Rahul
    addFriend({
      ownerUserId: creatorId,
      phone: '+919999900002',
    });
  });

  describe('Trip Creation & Group Copying', () => {
    it('creates trip and copies members from existing group without live link', async () => {
      // 1. Create a group "Weekend Gang" with Arhaam and Rahul
      const groupRes = await request(app)
        .post('/v1/groups')
        .set('x-user-id', creatorId)
        .send({
          name: 'Weekend Gang',
          memberUserIds: [memberRahul],
        });
      const groupId = groupRes.body.data.id;

      // 2. Create a trip copying members from Weekend Gang and adding Priya
      const tripRes = await request(app)
        .post('/v1/trips')
        .set('x-user-id', creatorId)
        .send({
          name: 'Goa 2026',
          budgetPaise: 5000000, // Rs 50,000
          startDate: '2026-10-12',
          endDate: '2026-10-16',
          sourceGroupId: groupId,
          memberUserIds: [memberPriya],
        });

      expect(tripRes.status).toBe(201);
      const trip = tripRes.body.data;
      expect(trip.name).toBe('Goa 2026');
      expect(trip.creatorUserId).toBe(creatorId);
      expect(trip.memberIds).toContain(creatorId);
      expect(trip.memberIds).toContain(memberRahul);
      expect(trip.memberIds).toContain(memberPriya);

      const tripId = trip.id;

      // 3. Add Amit to the original group later
      await request(app)
        .post(`/v1/groups/${groupId}/members`)
        .set('x-user-id', creatorId)
        .send({ userId: memberAmit });

      // 4. Verify trip memberIds are unaffected (no live link!)
      const tripDetailsRes = await request(app)
        .get(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId);
      expect(tripDetailsRes.body.data.memberIds).not.toContain(memberAmit);
    });
  });

  describe('Scenario 9: Trip Isolation Enforcement', () => {
    it('no trip amount appears in friend balances or group balances, and offsets are forbidden', async () => {
      // 1. Create Trip
      const tripRes = await request(app)
        .post('/v1/trips')
        .set('x-user-id', creatorId)
        .send({
          name: 'Isolated Mountains',
          budgetPaise: 3000000,
          memberUserIds: [memberRahul],
        });
      const tripId = tripRes.body.data.id;

      // 2. Add an expense in the trip: Rahul pays 10,000 paise for Arhaam
      await request(app)
        .post(`/v1/ledgers/${tripId}/expenses`)
        .set('x-user-id', memberRahul)
        .send({
          title: 'Camp rent',
          totalPaise: 10000,
          category: 'stay',
          splitType: 'EXACT',
          expenseDate: '2026-10-12',
          payers: [{ userId: memberRahul, paidPaise: 10000 }],
          participants: [
            { userId: memberRahul, included: true, owedPaise: 0 },
            { userId: creatorId, included: true, owedPaise: 10000 },
          ],
        });

      // 3. Verify Trip Balance reflects Arhaam owes 10,000 paise
      const tripDetailsRes = await request(app)
        .get(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId);
      expect(tripDetailsRes.body.data.myNetPaise).toBe(-10000);

      // 4. Verify Friend balance with Rahul is STILL 0 (Trip Isolation!)
      const friendsRes = await request(app)
        .get('/v1/friends')
        .set('x-user-id', creatorId);
      const rahulFriend = friendsRes.body.data.find((f: any) => f.friendId === memberRahul);
      expect(rahulFriend.netPaise).toBe(0);

      // 5. Verify Offsets are strictly forbidden for trip ledgers
      const offsetSuggRes = await request(app)
        .get('/v1/offsets/suggestions')
        .query({ groupLedgerId: tripId })
        .set('x-user-id', creatorId);
      // Fails because trip ledger is not a GROUP
      expect(offsetSuggRes.status).toBe(404);

      const offsetCreateRes = await request(app)
        .post('/v1/offsets')
        .set('x-user-id', creatorId)
        .send({
          groupLedgerId: tripId,
          toUserId: memberRahul,
          amountPaise: 5000,
        });
      expect(offsetCreateRes.status).toBe(404);
    });
  });

  describe('Scenario 12: Budget Meter Levels & Notifications', () => {
    it('shows 60 to 80% amber state, calculates per-day remaining, and notifies once at 80% and 100%', async () => {
      // Create trip: Rs 50,000 budget, 4 days duration
      const tripRes = await request(app)
        .post('/v1/trips')
        .set('x-user-id', creatorId)
        .send({
          name: 'Goa Budget Test',
          budgetPaise: 5000000, // Rs 50,000
          startDate: '2026-10-12',
          endDate: '2026-10-16',
          memberUserIds: [memberRahul],
        });
      const tripId = tripRes.body.data.id;

      // 1. Spend Rs 38,400 (3,840,000 paise = 76.8% of 50,000)
      await request(app)
        .post(`/v1/ledgers/${tripId}/expenses`)
        .set('x-user-id', creatorId)
        .send({
          title: 'Resort Booking',
          totalPaise: 3840000,
          category: 'stay',
          splitType: 'EQUAL',
          expenseDate: '2026-10-12',
          payers: [{ userId: creatorId, paidPaise: 3840000 }],
          participants: [
            { userId: creatorId, included: true },
            { userId: memberRahul, included: true },
          ],
        });

      // Check budget meter
      const details1 = await request(app)
        .get(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId);

      const meter1 = details1.body.data.budgetMeter;
      expect(meter1.spentPercent).toBe(76.8);
      expect(meter1.level).toBe('60_TO_80');
      expect(meter1.statusMessage).toBe('Heads up');
      expect(meter1.remainingPaise).toBe(1160000); // 50,000 - 38,400 = 11,600 (1,160,000 paise)
      expect(meter1.remainingPerDayPaise).toBeGreaterThan(0);

      // 2. Cross 80% (spend another Rs 3,000 -> 41,400 spent = 82.8%)
      await request(app)
        .post(`/v1/ledgers/${tripId}/expenses`)
        .set('x-user-id', creatorId)
        .send({
          title: 'Dinner at Beach',
          totalPaise: 300000,
          category: 'food',
          splitType: 'EQUAL',
          expenseDate: '2026-10-13',
          payers: [{ userId: creatorId, paidPaise: 300000 }],
          participants: [
            { userId: creatorId, included: true },
            { userId: memberRahul, included: true },
          ],
        });

      const details2 = await request(app)
        .get(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId);
      const meter2 = details2.body.data.budgetMeter;
      expect(meter2.spentPercent).toBe(82.8);
      expect(meter2.level).toBe('80_TO_100');
      expect(meter2.statusMessage).toMatch(/Warning, remaining/);

      // Check notification sent for 80%
      const notifications = notificationsStore.listForUser(memberRahul);
      const warning80 = notifications.find((n: any) => n.type === 'TRIP_BUDGET_WARNING');
      expect(warning80).toBeDefined();

      // 3. Cross 100% (spend another Rs 10,000 -> 51,400 spent = 102.8%)
      await request(app)
        .post(`/v1/ledgers/${tripId}/expenses`)
        .set('x-user-id', creatorId)
        .send({
          title: 'Water Sports',
          totalPaise: 1000000,
          category: 'other',
          splitType: 'EQUAL',
          expenseDate: '2026-10-14',
          payers: [{ userId: creatorId, paidPaise: 1000000 }],
          participants: [
            { userId: creatorId, included: true },
            { userId: memberRahul, included: true },
          ],
        });

      const details3 = await request(app)
        .get(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId);
      const meter3 = details3.body.data.budgetMeter;
      expect(meter3.spentPercent).toBe(102.8);
      expect(meter3.level).toBe('OVER_100');
      expect(meter3.statusMessage).toMatch(/Over budget by/);

      // Check notification sent for 100% exceeded
      const notificationsAfter = notificationsStore.listForUser(memberRahul);
      const exceeded100 = notificationsAfter.find((n: any) => n.type === 'TRIP_BUDGET_EXCEEDED');
      expect(exceeded100).toBeDefined();
    });
  });

  describe('Budget Changes & Creator Permissions', () => {
    it('only creator can update trip budget or details, writes to activity log', async () => {
      const tripRes = await request(app)
        .post('/v1/trips')
        .set('x-user-id', creatorId)
        .send({
          name: 'Manali Expedition',
          budgetPaise: 4000000,
          memberUserIds: [memberRahul],
        });
      const tripId = tripRes.body.data.id;

      // Rahul attempts to change budget -> 403 Forbidden
      const unauthorizedBudgetRes = await request(app)
        .patch(`/v1/trips/${tripId}/budget`)
        .set('x-user-id', memberRahul)
        .send({ budgetPaise: 6000000 });
      expect(unauthorizedBudgetRes.status).toBe(403);

      // Creator updates budget -> Success
      const budgetRes = await request(app)
        .patch(`/v1/trips/${tripId}/budget`)
        .set('x-user-id', creatorId)
        .send({ budgetPaise: 6000000 });
      expect(budgetRes.status).toBe(200);
      expect(budgetRes.body.data.budgetPaise).toBe(6000000);

      // Check activity log
      const logs = activityStore.listForLedger(tripId);
      const budgetLog = logs.find((l) => l.action === 'BUDGET_CHANGED');
      expect(budgetLog).toBeDefined();
      expect(budgetLog!.actorUserId).toBe(creatorId);

      // Creator renames trip -> Success
      const renameRes = await request(app)
        .patch(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId)
        .send({ name: 'Manali 2026 Winter' });
      expect(renameRes.status).toBe(200);
      expect(renameRes.body.data.name).toBe('Manali 2026 Winter');
    });

    it('marks trip as completed and allows settlements in completed trips', async () => {
      const tripRes = await request(app)
        .post('/v1/trips')
        .set('x-user-id', creatorId)
        .send({
          name: 'Jaipur Heritage',
          budgetPaise: 2000000,
          memberUserIds: [memberRahul],
        });
      const tripId = tripRes.body.data.id;

      // Add expense so Rahul owes Arhaam 1000 paise
      await request(app)
        .post(`/v1/ledgers/${tripId}/expenses`)
        .set('x-user-id', creatorId)
        .send({
          title: 'Fort entry',
          totalPaise: 2000,
          category: 'tickets',
          splitType: 'EQUAL',
          payers: [{ userId: creatorId, paidPaise: 2000 }],
          participants: [
            { userId: creatorId, included: true },
            { userId: memberRahul, included: true },
          ],
        });

      // Creator marks trip as completed
      const completeRes = await request(app)
        .post(`/v1/trips/${tripId}/complete`)
        .set('x-user-id', creatorId);
      expect(completeRes.status).toBe(200);
      expect(completeRes.body.data.isCompleted).toBe(true);
      expect(completeRes.body.data.status).toBe('COMPLETED');

      // Verify listUserTrips places it in completed segment
      const listRes = await request(app)
        .get('/v1/trips')
        .set('x-user-id', creatorId);
      expect(listRes.body.data.completed.some((t: any) => t.id === tripId)).toBe(true);

      // Settlement is STILL permitted in completed trip
      const stlRes = await request(app)
        .post('/v1/settlements')
        .set('x-user-id', memberRahul)
        .send({
          ledgerId: tripId,
          toUserId: creatorId,
          amountPaise: 1000,
          method: 'UPI',
        });
      expect(stlRes.status).toBe(201);
      const stlId = stlRes.body.data.id;

      // Creator confirms settlement
      const confirmRes = await request(app)
        .post(`/v1/settlements/${stlId}/confirm`)
        .set('x-user-id', creatorId);
      expect(confirmRes.status).toBe(200);

      // Balances in trip are now 0
      const finalTripRes = await request(app)
        .get(`/v1/trips/${tripId}`)
        .set('x-user-id', creatorId);
      expect(finalTripRes.body.data.myNetPaise).toBe(0);
    });
  });
});
