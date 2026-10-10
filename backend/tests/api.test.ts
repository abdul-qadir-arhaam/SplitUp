import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app.js';
import { inMemoryLedgers } from '../src/modules/ledgers/routes.js';

describe('API Endpoints and Middleware Integration Tests', () => {
  beforeEach(() => {
    // Reset test ledger
    inMemoryLedgers.set('ledger_test_1', {
      id: 'ledger_test_1',
      name: 'Friday Gang',
      type: 'GROUP',
      memberIds: ['usr_arhaam', 'usr_rahul', 'usr_priya', 'usr_amit', 'usr_sneha'],
      expenses: [],
      settlements: [],
    });
  });

  it('GET /health returns 200 ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.headers['x-request-id']).toBeDefined();
  });

  it('GET /app/version returns current version config', async () => {
    const res = await request(app).get('/app/version');
    expect(res.status).toBe(200);
    expect(res.body.latest_version_code).toBe(1);
    expect(res.body.download_page_url).toBe('https://splitup.app/download');
  });

  it('POST /v1/ledgers/:id/expenses creates an expense and calculates equal split', async () => {
    const payload = {
      title: 'Dinner at Wharf',
      totalPaise: 120000,
      splitType: 'EQUAL',
      payers: [
        { userId: 'usr_arhaam', paidPaise: 20000 },
        { userId: 'usr_rahul', paidPaise: 60000 },
        { userId: 'usr_priya', paidPaise: 40000 },
      ],
      participants: [
        { userId: 'usr_arhaam', included: true },
        { userId: 'usr_rahul', included: true },
        { userId: 'usr_priya', included: true },
      ],
    };

    const res = await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .send(payload);

    expect(res.status).toBe(201);
    expect(res.body.data.id).toBeDefined();
    expect(res.body.data.totalPaise).toBe(120000);
    expect(res.body.data.splits).toHaveLength(3);
    for (const split of res.body.data.splits) {
      expect(split.owedPaise).toBe(40000);
    }
  });

  it('POST /v1/ledgers/:id/expenses rejects when payer amounts do not equal total', async () => {
    const payload = {
      title: 'Mismatched Expense',
      totalPaise: 120000,
      splitType: 'EQUAL',
      payers: [{ userId: 'usr_arhaam', paidPaise: 100000 }], // 100000 != 120000
      participants: [{ userId: 'usr_arhaam', included: true }],
    };

    const res = await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .send(payload);

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.message).toContain('Sum of payer amounts');
  });

  it('POST /v1/ledgers/:id/expenses rejects when excluded member is marked as payer', async () => {
    const payload = {
      title: 'Invalid Payer Excluded',
      totalPaise: 50000,
      splitType: 'EQUAL',
      payers: [{ userId: 'usr_amit', paidPaise: 50000 }],
      participants: [
        { userId: 'usr_arhaam', included: true },
        { userId: 'usr_amit', included: false }, // Amit is excluded but also paid
      ],
    };

    const res = await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .send(payload);

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.message).toContain('Excluded member usr_amit cannot be a payer');
  });

  it('Authorization: Non-member cannot access ledger endpoints', async () => {
    const res = await request(app)
      .get('/v1/ledgers/ledger_test_1/balances')
      .set('Authorization', 'Bearer user:usr_stranger');

    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });

  it('Idempotency: Duplicate request with same Idempotency-Key returns cached response', async () => {
    const key = 'idem_uuid_12345';
    const payload = {
      title: 'Cab Ride',
      totalPaise: 60000,
      splitType: 'EQUAL',
      payers: [{ userId: 'usr_arhaam', paidPaise: 60000 }],
      participants: [
        { userId: 'usr_arhaam', included: true },
        { userId: 'usr_rahul', included: true },
      ],
    };

    // First request
    const res1 = await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .set('Idempotency-Key', key)
      .send(payload);
    expect(res1.status).toBe(201);
    const createdId = res1.body.data.id;

    // Repeated request with same key and same body
    const res2 = await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .set('Idempotency-Key', key)
      .send(payload);
    expect(res2.status).toBe(201);
    expect(res2.body.data.id).toBe(createdId);

    // Ledger only contains 1 expense
    const ledger = inMemoryLedgers.get('ledger_test_1')!;
    expect(ledger.expenses).toHaveLength(1);
  });

  it('Idempotency: Same key with different body returns 409 CONFLICT', async () => {
    const key = 'idem_uuid_conflict_test';

    await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .set('Idempotency-Key', key)
      .send({
        title: 'Original',
        totalPaise: 50000,
        splitType: 'EQUAL',
        payers: [{ userId: 'usr_arhaam', paidPaise: 50000 }],
        participants: [{ userId: 'usr_arhaam', included: true }],
      });

    const conflictRes = await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .set('Idempotency-Key', key)
      .send({
        title: 'Different Title',
        totalPaise: 50000,
        splitType: 'EQUAL',
        payers: [{ userId: 'usr_arhaam', paidPaise: 50000 }],
        participants: [{ userId: 'usr_arhaam', included: true }],
      });

    expect(conflictRes.status).toBe(409);
    expect(conflictRes.body.error.code).toBe('CONFLICT');
  });

  it('GET /v1/ledgers/:id/balances & /simplified calculate correct balance and simplified plan', async () => {
    // Add dinner expense: A 200, B 600, C 400 on Rs 1200
    await request(app)
      .post('/v1/ledgers/ledger_test_1/expenses')
      .send({
        title: 'Dinner',
        totalPaise: 120000,
        splitType: 'EQUAL',
        payers: [
          { userId: 'usr_arhaam', paidPaise: 20000 },
          { userId: 'usr_rahul', paidPaise: 60000 },
          { userId: 'usr_priya', paidPaise: 40000 },
        ],
        participants: [
          { userId: 'usr_arhaam', included: true },
          { userId: 'usr_rahul', included: true },
          { userId: 'usr_priya', included: true },
        ],
      });

    // Check balances
    const balRes = await request(app).get('/v1/ledgers/ledger_test_1/balances');
    expect(balRes.status).toBe(200);
    expect(balRes.body.data.balances['usr_arhaam']).toBe(-20000);
    expect(balRes.body.data.balances['usr_rahul']).toBe(20000);
    expect(balRes.body.data.balances['usr_priya']).toBe(0);

    // Check simplified plan
    const simpRes = await request(app).get('/v1/ledgers/ledger_test_1/simplified');
    expect(simpRes.status).toBe(200);
    expect(simpRes.body.data.payments).toEqual([
      { from: 'usr_arhaam', to: 'usr_rahul', amountPaise: 20000 },
    ]);
  });
});
