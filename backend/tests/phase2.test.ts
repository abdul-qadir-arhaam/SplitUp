import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app.js';
import { normalizePhoneE164, isValidE164 } from '../src/modules/users/phone.js';
import { inMemoryUsers, seedDefaultUsers } from '../src/modules/users/store.js';
import { inMemoryFriendships } from '../src/modules/friends/store.js';
import { inMemoryLedgers } from '../src/modules/ledgers/routes.js';
import { notificationsStore } from '../src/modules/notifications/store.js';

describe('Phase 2: Identity, Contacts, Friends, and Placeholder Merge', () => {
  beforeEach(() => {
    seedDefaultUsers();
    inMemoryFriendships.clear();
    notificationsStore.clear();
    inMemoryLedgers.clear();
  });

  describe('Phone Normalization', () => {
    it('normalizes 10-digit Indian numbers to +91', () => {
      expect(normalizePhoneE164('9876543210')).toBe('+919876543210');
      expect(normalizePhoneE164('09876543210')).toBe('+919876543210');
      expect(normalizePhoneE164(' 98765-43210 ')).toBe('+919876543210');
      expect(normalizePhoneE164('+91 (987) 654-3210')).toBe('+919876543210');
    });

    it('rejects invalid phone numbers', () => {
      expect(isValidE164('123')).toBe(false);
      expect(isValidE164('abc')).toBe(false);
      expect(() => normalizePhoneE164('hello')).toThrow();
    });
  });

  describe('User Profile (GET/PATCH /v1/users/me)', () => {
    it('GET /v1/users/me returns authenticated user profile', async () => {
      const res = await request(app)
        .get('/v1/users/me')
        .set('Authorization', 'Bearer user:usr_arhaam');

      expect(res.status).toBe(200);
      expect(res.body.data.id).toBe('usr_arhaam');
      expect(res.body.data.name).toBe('Arhaam');
      expect(res.body.data.phoneE164).toBe('+919876543210');
    });

    it('PATCH /v1/users/me updates name and email', async () => {
      const res = await request(app)
        .patch('/v1/users/me')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          name: 'Arhaam Qadir',
          email: 'arhaam.qadir@example.com',
        });

      expect(res.status).toBe(200);
      expect(res.body.data.name).toBe('Arhaam Qadir');
      expect(res.body.data.email).toBe('arhaam.qadir@example.com');
    });
  });

  describe('Contacts Lookup (POST /v1/contacts/lookup)', () => {
    it('returns only active app users and excludes non-users / placeholders', async () => {
      // Create a placeholder user
      await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({ phone: '+919999900000', name: 'Placeholder Contact' });

      const res = await request(app)
        .post('/v1/contacts/lookup')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          phones: [
            '9876543211', // Rahul (Registered App User)
            '9999900000', // Placeholder (Not registered app user)
            '9111122222', // Unknown phone
          ],
        });

      expect(res.status).toBe(200);
      const matches = res.body.data.matches;
      expect(matches).toHaveLength(1);
      expect(matches[0].phone).toBe('+919876543211');
      expect(matches[0].name).toBe('Rahul');
    });
  });

  describe('Friends Management (POST/GET/PATCH/DELETE /v1/friends)', () => {
    it('adds registered app user: creates bidirectional friendship, individual ledger, and notification', async () => {
      const res = await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          phone: '+919876543211', // Rahul
          contactName: 'Rahul Phonebook',
        });

      expect(res.status).toBe(201);
      expect(res.body.data.isAppUser).toBe(true);
      expect(res.body.data.friendId).toBe('usr_rahul');
      expect(res.body.data.ledgerId).toBeDefined();

      // Check Arhaam friends list
      const listA = await request(app)
        .get('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam');
      expect(listA.body.data).toHaveLength(1);
      expect(listA.body.data[0].friendId).toBe('usr_rahul');
      expect(listA.body.data[0].contactName).toBe('Rahul Phonebook');

      // Check Rahul friends list (bidirectional!)
      const listB = await request(app)
        .get('/v1/friends')
        .set('Authorization', 'Bearer user:usr_rahul');
      expect(listB.body.data).toHaveLength(1);
      expect(listB.body.data[0].friendId).toBe('usr_arhaam');

      // Check notification received by Rahul
      const notifs = await request(app)
        .get('/v1/notifications')
        .set('Authorization', 'Bearer user:usr_rahul');
      expect(notifs.body.data).toHaveLength(1);
      expect(notifs.body.data[0].type).toBe('FRIEND_ADDED');
      expect(notifs.body.data[0].payload.adderName).toBe('Arhaam');
    });

    it('adds non-app user: creates placeholder and marks isAppUser false', async () => {
      const res = await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          phone: '9988776655',
          name: 'College Buddy',
        });

      expect(res.status).toBe(201);
      expect(res.body.data.isAppUser).toBe(false);
      expect(res.body.data.friend.phoneE164).toBe('+919988776655');
      expect(res.body.data.friend.name).toBe('College Buddy');
    });

    it('rejects adding yourself as friend', async () => {
      const res = await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({ phone: '+919876543210' });

      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    });

    it('private nickname: Arhaam sets nickname for Rahul, Rahul never sees it', async () => {
      // Arhaam adds Rahul
      await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({ phone: '+919876543211' });

      // Arhaam sets nickname "Bro"
      const patchRes = await request(app)
        .patch('/v1/friends/usr_rahul/nickname')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({ nickname: 'Bro' });
      expect(patchRes.status).toBe(200);
      expect(patchRes.body.data.nickname).toBe('Bro');

      // Arhaam sees nickname "Bro"
      const friendsA = await request(app)
        .get('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam');
      expect(friendsA.body.data[0].nickname).toBe('Bro');

      // Rahul sees Arhaam, but Arhaam's nickname for Rahul is completely hidden from Rahul!
      const friendsB = await request(app)
        .get('/v1/friends')
        .set('Authorization', 'Bearer user:usr_rahul');
      expect(friendsB.body.data[0].nickname).toBeNull();

      // Rahul's profile still has his original name
      const profileB = await request(app)
        .get('/v1/users/me')
        .set('Authorization', 'Bearer user:usr_rahul');
      expect(profileB.body.data.name).toBe('Rahul');
    });

    it('unsettled balance guard: cannot remove friend if balance != 0', async () => {
      // Arhaam adds Rahul
      const addRes = await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({ phone: '+919876543211' });
      const ledgerId = addRes.body.data.ledgerId;

      // Log an expense where Rahul owes Arhaam Rs 500
      await request(app)
        .post(`/v1/ledgers/${ledgerId}/expenses`)
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          title: 'Lunch',
          totalPaise: 100000,
          splitType: 'EQUAL',
          payers: [{ userId: 'usr_arhaam', paidPaise: 100000 }],
          participants: [
            { userId: 'usr_arhaam', included: true },
            { userId: 'usr_rahul', included: true },
          ],
        });

      // Try removing friend Rahul
      const deleteRes = await request(app)
        .delete('/v1/friends/usr_rahul')
        .set('Authorization', 'Bearer user:usr_arhaam');

      expect(deleteRes.status).toBe(400);
      expect(deleteRes.body.error.code).toBe('UNSETTLED_BALANCE');
    });
  });

  describe('Placeholder Merge Flow (DATABASE.md Section 5.1)', () => {
    it('merges placeholder into real account when unregistered friend signs up', async () => {
      const testPhone = '+919123456789';

      // 1. Arhaam adds unregistered friend with testPhone
      const addRes = await request(app)
        .post('/v1/friends')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({ phone: testPhone, name: 'Zack Offline' });
      const placeholderId = addRes.body.data.friendId;
      const ledgerId = addRes.body.data.ledgerId;

      // 2. Arhaam records an expense of Rs 1,000 where Zack owes Rs 500
      await request(app)
        .post(`/v1/ledgers/${ledgerId}/expenses`)
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          title: 'Concert Ticket',
          totalPaise: 100000,
          splitType: 'EQUAL',
          payers: [{ userId: 'usr_arhaam', paidPaise: 100000 }],
          participants: [
            { userId: 'usr_arhaam', included: true },
            { userId: placeholderId, included: true },
          ],
        });

      // 3. Zack signs up via /v1/users/auth/verify with that verified phone
      const signupRes = await request(app)
        .post('/v1/users/auth/verify')
        .send({
          phone: testPhone,
          name: 'Zack Real',
          firebaseUid: 'fb_zack_123',
        });

      expect(signupRes.status).toBe(200);
      const newUserId = signupRes.body.data.user.id;
      const mergeSummary = signupRes.body.data.mergeSummary;

      // 4. Verify merge summary
      expect(mergeSummary).not.toBeNull();
      expect(mergeSummary.merged).toBe(true);
      expect(mergeSummary.placeholderId).toBe(placeholderId);
      expect(mergeSummary.realUserId).toBe(newUserId);
      expect(mergeSummary.expenseCount).toBe(1);
      expect(mergeSummary.totalPaise).toBe(100000);

      // 5. Placeholder row is deleted
      expect(inMemoryUsers.get(placeholderId)).toBeUndefined();

      // 6. Inviter (Arhaam) receives FRIEND_JOINED notification
      const arhaamNotifs = await request(app)
        .get('/v1/notifications')
        .set('Authorization', 'Bearer user:usr_arhaam');
      const friendJoinedNotif = arhaamNotifs.body.data.find((n: any) => n.type === 'FRIEND_JOINED');
      expect(friendJoinedNotif).toBeDefined();
      expect(friendJoinedNotif.payload.friendName).toBe('Zack Real');

      // 7. Check Zack's friends list: Arhaam is present and balance shows Zack owes Rs 500 (-50000 paise)
      const zackFriends = await request(app)
        .get('/v1/friends')
        .set('Authorization', `Bearer user:${newUserId}`);
      expect(zackFriends.body.data).toHaveLength(1);
      expect(zackFriends.body.data[0].friendId).toBe('usr_arhaam');
      expect(zackFriends.body.data[0].netPaise).toBe(-50000); // Zack owes Rs 500
    });
  });

  describe('Device Tokens (POST/DELETE /v1/devices/tokens)', () => {
    it('registers and unregisters FCM device tokens', async () => {
      const regRes = await request(app)
        .post('/v1/devices/tokens')
        .set('Authorization', 'Bearer user:usr_arhaam')
        .send({
          fcmToken: 'test_fcm_token_abcdef1234567890',
          platform: 'android',
        });

      expect(regRes.status).toBe(201);
      expect(regRes.body.data.userId).toBe('usr_arhaam');

      const delRes = await request(app)
        .delete('/v1/devices/tokens/test_fcm_token_abcdef1234567890')
        .set('Authorization', 'Bearer user:usr_arhaam');
      expect(delRes.status).toBe(200);
      expect(delRes.body.success).toBe(true);
    });
  });
});
