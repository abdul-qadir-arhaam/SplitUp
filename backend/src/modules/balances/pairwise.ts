import type { ExpenseRecord, SettlementRecord } from './netBalances.js';

export interface PairwiseDebt {
  from: string; // debtor
  to: string;   // creditor
  amountPaise: number;
}

/**
 * Calculates direct pairwise ("Actual") debts between members in a ledger.
 * Explains exactly who owes whom before any graph simplification is applied.
 */
export function calculatePairwiseDebts(
  expenses: ExpenseRecord[],
  settlements: SettlementRecord[]
): PairwiseDebt[] {
  // Directed debt matrix: debts[from][to] = paise
  const matrix: Record<string, Record<string, number>> = {};

  function addDebt(from: string, to: string, paise: number) {
    if (from === to || paise <= 0) return;
    if (!matrix[from]) matrix[from] = {};
    matrix[from][to] = (matrix[from][to] || 0) + paise;
  }

  // 1. Accumulate pairwise shares per expense
  for (const exp of expenses) {
    if (exp.totalPaise <= 0) continue;

    for (const split of exp.splits) {
      if (!split.included || split.owedPaise <= 0) continue;

      for (const payer of exp.payers) {
        if (payer.paidPaise <= 0 || split.userId === payer.userId) continue;

        // Proportional contribution of this payer to the participant's owed share
        const pairwiseShare = Math.round((split.owedPaise * payer.paidPaise) / exp.totalPaise);
        addDebt(split.userId, payer.userId, pairwiseShare);
      }
    }
  }

  // 2. Reduce by confirmed settlements
  for (const stl of settlements) {
    if (stl.status === 'CONFIRMED' && stl.amountPaise > 0) {
      // Sender paid receiver: reduces debt from sender to receiver
      addDebt(stl.toUserId, stl.fromUserId, -stl.amountPaise);
    }
  }

  // 3. Net out bidirectional debts between every pair
  const result: PairwiseDebt[] = [];
  const processedPairs = new Set<string>();

  const allUsers = new Set<string>();
  for (const from of Object.keys(matrix)) {
    allUsers.add(from);
    for (const to of Object.keys(matrix[from])) {
      allUsers.add(to);
    }
  }

  const userList = Array.from(allUsers);
  for (let i = 0; i < userList.length; i++) {
    for (let j = i + 1; j < userList.length; j++) {
      const u1 = userList[i];
      const u2 = userList[j];

      const u1OwesU2 = (matrix[u1]?.[u2] || 0);
      const u2OwesU1 = (matrix[u2]?.[u1] || 0);

      const netDifference = u1OwesU2 - u2OwesU1;

      if (netDifference > 0) {
        result.push({ from: u1, to: u2, amountPaise: netDifference });
      } else if (netDifference < 0) {
        result.push({ from: u2, to: u1, amountPaise: -netDifference });
      }
    }
  }

  // Sort deterministically
  return result.sort((a, b) => a.from.localeCompare(b.from) || a.to.localeCompare(b.to));
}
