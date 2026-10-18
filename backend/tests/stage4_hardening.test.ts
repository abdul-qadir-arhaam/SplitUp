import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { ulid } from 'ulidx';
import { app } from '../src/app.js';
import { db } from '../src/db/knex.js';

describe('Stage 4: Hardening and Cleanup', () => {
  const userA = `usr_s4a_${ulid()}`;
  const userB = `usr_s4b_${ulid()}`;
  const userOutsider = `usr_s4out_${ulid()}`;
  const ledgerId = `ldg_${ulid()}`;
  let settlementId: string;

  beforeAll(async () => {
    // Seed users with unique phone numbers
    const rand = Math.floor(10000000 + Math.random() * 90000000);
    const now = new Date();
    await db('users').insert([
      { id: userA, phone_e164: `+9198${rand}1`, name: 'User 4A', is_placeholder: 0, created_at: now, updated_at: now },
      { id: userB, phone_e164: `+9198${rand}2`, name: 'User 4B', is_placeholder: 0, created_at: now, updated_at: now },
      { id: userOutsider, phone_e164: `+9198${rand}3`, name: 'User Outsider', is_placeholder: 0, created_at: now, updated_at: now },
    ]);

    // Seed ledger with A and B as members
    await db('ledgers').insert({
      id: ledgerId,
      type: 'GROUP',
      name: 'Stage 4 Ledger',
      created_by: userA,
      created_at: now,
      updated_at: now,
    });

    await db('ledger_members').insert([
      { ledger_id: ledgerId, user_id: userA, role: 'ADMIN', joined_at: now },
      { ledger_id: ledgerId, user_id: userB, role: 'MEMBER', joined_at: now },
    ]);

    // Create a settlement between A and B
    settlementId = `stl_${ulid()}`;
    await db('settlements').insert({
      id: settlementId,
      ledger_id: ledgerId,
      from_user_id: userA,
      to_user_id: userB,
      amount_paise: 50000,
      method: 'CASH',
      status: 'PENDING',
      created_by: userA,
      created_at: now,
    });
  });

  afterAll(async () => {
    await db('settlements').where({ ledger_id: ledgerId }).del().catch(() => {});
    await db('ledger_members').where({ ledger_id: ledgerId }).del().catch(() => {});
    await db('ledgers').where({ id: ledgerId }).del().catch(() => {});
    await db('users').whereIn('id', [userA, userB, userOutsider]).del().catch(() => {});
  });

  it('Bearer user:<id> is accepted for authentication', async () => {
    const res = await request(app)
      .get(`/v1/ledgers/${ledgerId}/settlements`)
      .set('Authorization', `Bearer user:${userA}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('GET /v1/settlements/:id enforces membership check (403 for outsider)', async () => {
    const res = await request(app)
      .get(`/v1/settlements/${settlementId}`)
      .set('Authorization', `Bearer user:${userOutsider}`);

    expect(res.status).toBe(403);
    expect(res.body.error.message).toContain('not an active member');
  });

  it('GET /v1/settlements/:id succeeds for active member', async () => {
    const res = await request(app)
      .get(`/v1/settlements/${settlementId}`)
      .set('Authorization', `Bearer user:${userA}`);

    expect(res.status).toBe(200);
    expect(res.body.data.id).toBe(settlementId);
  });

  it('GET /v1/ledgers/:id/settlements enforces membership check (403 for outsider)', async () => {
    const res = await request(app)
      .get(`/v1/ledgers/${ledgerId}/settlements`)
      .set('Authorization', `Bearer user:${userOutsider}`);

    expect(res.status).toBe(403);
    expect(res.body.error.message).toContain('not an active member');
  });

  it('Missing authorization returns 401 Unauthenticated', async () => {
    const res = await request(app)
      .get(`/v1/settlements/${settlementId}`);

    expect(res.status).toBe(401);
  });

  it('x-user-id header is ignored when NODE_ENV is not test', async () => {
    const prevEnv = process.env.NODE_ENV;
    try {
      (process.env as any).NODE_ENV = 'production';
      const res = await request(app)
        .get(`/v1/settlements/${settlementId}`)
        .set('x-user-id', userA);

      expect(res.status).toBe(401);
    } finally {
      process.env.NODE_ENV = prevEnv;
    }
  });
});
