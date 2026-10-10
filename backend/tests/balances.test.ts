import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  calculateSplits,
  calculateNetBalances,
  simplifyDebts,
  calculatePairwiseDebts,
} from '../src/modules/balances/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const vectorsDir = path.resolve(__dirname, '../../shared/test-vectors');

describe('Shared Test Vectors Verification', () => {
  it('Scenario 1: Basic Dinner Split passes dinner_basic.json', () => {
    const raw = fs.readFileSync(path.join(vectorsDir, 'dinner_basic.json'), 'utf-8');
    const vector = JSON.parse(raw);

    const splits = calculateSplits(vector.totalPaise, vector.splitType, vector.participants);
    expect(splits).toEqual(vector.expectedSplits);

    const netResult = calculateNetBalances(
      vector.participants.map((p: any) => p.userId),
      [
        {
          id: 'exp_1',
          totalPaise: vector.totalPaise,
          payers: vector.payers,
          splits,
        },
      ],
      []
    );
    expect(netResult.balances).toEqual(vector.expectedNetBalances);

    const simplified = simplifyDebts(netResult.balances);
    expect(simplified).toEqual(vector.expectedSimplifiedSettlements);
  });

  it('Scenario 2: Rounding Invariant passes rounding.json', () => {
    const raw = fs.readFileSync(path.join(vectorsDir, 'rounding.json'), 'utf-8');
    const vector = JSON.parse(raw);

    const splits = calculateSplits(vector.totalPaise, vector.splitType, vector.participants);
    expect(splits).toEqual(vector.expectedSplits);

    const sum = splits.reduce((acc, s) => acc + s.owedPaise, 0);
    expect(sum).toBe(vector.totalPaise);

    const netResult = calculateNetBalances(
      vector.participants.map((p: any) => p.userId),
      [
        {
          id: 'exp_round',
          totalPaise: vector.totalPaise,
          payers: vector.payers,
          splits,
        },
      ],
      []
    );
    expect(netResult.balances).toEqual(vector.expectedNetBalances);
  });

  it('Scenario 3: Excluded Member ("Not there") passes not_there.json', () => {
    const raw = fs.readFileSync(path.join(vectorsDir, 'not_there.json'), 'utf-8');
    const vector = JSON.parse(raw);

    const splits = calculateSplits(vector.totalPaise, vector.splitType, vector.participants);
    expect(splits).toEqual(vector.expectedSplits);

    // C must have 0 share
    const splitC = splits.find((s) => s.userId === 'C');
    expect(splitC?.owedPaise).toBe(0);

    const netResult = calculateNetBalances(
      ['A', 'B', 'C'],
      [
        {
          id: 'exp_not_there',
          totalPaise: vector.totalPaise,
          payers: vector.payers,
          splits,
        },
      ],
      []
    );
    expect(netResult.balances).toEqual(vector.expectedNetBalances);
    expect(netResult.balances['C']).toBe(0);
  });

  it('Scenario 4: Simplification of 5 Members passes simplification.json', () => {
    const raw = fs.readFileSync(path.join(vectorsDir, 'simplification.json'), 'utf-8');
    const vector = JSON.parse(raw);

    const simplified = simplifyDebts(vector.netBalances);
    expect(simplified.length).toBeLessThanOrEqual(vector.maxPaymentsAllowed);
    expect(simplified).toEqual(vector.expectedSimplifiedSettlements);

    // Verify applying simplified payments zeroes all balances
    const testBalances = { ...vector.netBalances };
    for (const p of simplified) {
      testBalances[p.from] += p.amountPaise;
      testBalances[p.to] -= p.amountPaise;
    }
    for (const net of Object.values(testBalances)) {
      expect(net).toBe(0);
    }
  });

  it('Percentages and Shares Split Vectors pass percentages_shares.json', () => {
    const raw = fs.readFileSync(path.join(vectorsDir, 'percentages_shares.json'), 'utf-8');
    const vector = JSON.parse(raw);

    for (const c of vector.percentCases) {
      const splits = calculateSplits(c.totalPaise, c.splitType, c.participants);
      expect(splits).toEqual(c.expectedSplits);
      expect(splits.reduce((a, b) => a + b.owedPaise, 0)).toBe(c.totalPaise);
    }

    for (const s of vector.sharesCases) {
      const splits = calculateSplits(s.totalPaise, s.splitType, s.participants);
      expect(splits).toEqual(s.expectedSplits);
      expect(splits.reduce((a, b) => a + b.owedPaise, 0)).toBe(s.totalPaise);
    }
  });
});

describe('Property-Based and Invariant Tests', () => {
  it('Property 1: Sum of splits strictly equals totalPaise across random totals and participant counts', () => {
    for (let i = 0; i < 500; i++) {
      const totalPaise = Math.floor(Math.random() * 1000000) + 1; // 1 to 10,000 INR
      const participantCount = Math.floor(Math.random() * 10) + 2; // 2 to 12 participants

      const participants = Array.from({ length: participantCount }, (_, idx) => ({
        userId: `user_${idx + 1}`,
        included: Math.random() > 0.2, // ~20% chance of "Not there"
      }));

      // Ensure at least one included
      participants[0].included = true;

      const splits = calculateSplits(totalPaise, 'EQUAL', participants);
      const sum = splits.reduce((acc, s) => acc + s.owedPaise, 0);

      expect(sum).toBe(totalPaise);

      // Excluded members must strictly owe 0
      for (const s of splits) {
        if (!s.included) {
          expect(s.owedPaise).toBe(0);
        }
      }
    }
  });

  it('Property 2: Zero-sum invariant holds across arbitrary complex ledgers', () => {
    const members = ['u1', 'u2', 'u3', 'u4', 'u5'];

    for (let test = 0; test < 200; test++) {
      const expenses = [];
      const numExpenses = Math.floor(Math.random() * 8) + 1;

      for (let e = 0; e < numExpenses; e++) {
        const total = (Math.floor(Math.random() * 5000) + 10) * 100; // random rupees in paise
        const payer = members[Math.floor(Math.random() * members.length)];

        const participants = members.map((m) => ({
          userId: m,
          included: Math.random() > 0.25,
        }));
        participants[0].included = true;

        const splits = calculateSplits(total, 'EQUAL', participants);

        expenses.push({
          id: `exp_${test}_${e}`,
          totalPaise: total,
          payers: [{ userId: payer, paidPaise: total }],
          splits,
        });
      }

      const netResult = calculateNetBalances(members, expenses, []);
      const sumNets = Object.values(netResult.balances).reduce((a, b) => a + b, 0);
      expect(sumNets).toBe(0);

      // Property 3: Simplification generates at most n-1 payments and zeroes all balances
      const simplified = simplifyDebts(netResult.balances);
      expect(simplified.length).toBeLessThanOrEqual(members.length - 1);

      const balancesAfter = { ...netResult.balances };
      for (const p of simplified) {
        balancesAfter[p.from] += p.amountPaise;
        balancesAfter[p.to] -= p.amountPaise;
      }
      for (const b of Object.values(balancesAfter)) {
        expect(b).toBe(0);
      }
    }
  });

  it('Pairwise debts correctly reflects direct debts between members', () => {
    // A pays 1200 for A, B, C equally (400 each)
    const exp = {
      id: 'e1',
      totalPaise: 120000,
      payers: [{ userId: 'A', paidPaise: 120000 }],
      splits: [
        { userId: 'A', owedPaise: 40000, included: true },
        { userId: 'B', owedPaise: 40000, included: true },
        { userId: 'C', owedPaise: 40000, included: true },
      ],
    };

    const debts = calculatePairwiseDebts([exp], []);
    expect(debts).toEqual([
      { from: 'B', to: 'A', amountPaise: 40000 },
      { from: 'C', to: 'A', amountPaise: 40000 },
    ]);
  });
});
