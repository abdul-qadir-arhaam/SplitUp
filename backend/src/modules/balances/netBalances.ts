export interface ExpenseRecord {
  id: string;
  totalPaise: number;
  payers: { userId: string; paidPaise: number }[];
  splits: { userId: string; owedPaise: number; included: boolean }[];
}

export interface SettlementRecord {
  id: string;
  fromUserId: string; // sender
  toUserId: string;   // receiver
  amountPaise: number;
  status: 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'OUTDATED' | 'CANCELLED';
}

export interface NetBalancesResult {
  balances: Record<string, number>; // positive = owed money, negative = owes money
  totalPaid: Record<string, number>;
  totalOwed: Record<string, number>;
  totalSettledSent: Record<string, number>;
  totalSettledReceived: Record<string, number>;
}

/**
 * Computes authoritative net balances for all members in a ledger.
 * Invariant: Sum of all net balances in a ledger must strictly equal 0.
 */
export function calculateNetBalances(
  memberUserIds: string[],
  expenses: ExpenseRecord[],
  settlements: SettlementRecord[]
): NetBalancesResult {
  const totalPaid: Record<string, number> = {};
  const totalOwed: Record<string, number> = {};
  const totalSettledSent: Record<string, number> = {};
  const totalSettledReceived: Record<string, number> = {};
  const balances: Record<string, number> = {};

  for (const uid of memberUserIds) {
    totalPaid[uid] = 0;
    totalOwed[uid] = 0;
    totalSettledSent[uid] = 0;
    totalSettledReceived[uid] = 0;
    balances[uid] = 0;
  }

  // 1. Accumulate Expenses
  for (const exp of expenses) {
    for (const payer of exp.payers) {
      totalPaid[payer.userId] = (totalPaid[payer.userId] || 0) + payer.paidPaise;
    }
    for (const split of exp.splits) {
      if (split.included) {
        totalOwed[split.userId] = (totalOwed[split.userId] || 0) + split.owedPaise;
      }
    }
  }

  // 2. Accumulate Confirmed Settlements only
  for (const stl of settlements) {
    if (stl.status === 'CONFIRMED') {
      totalSettledSent[stl.fromUserId] =
        (totalSettledSent[stl.fromUserId] || 0) + stl.amountPaise;
      totalSettledReceived[stl.toUserId] =
        (totalSettledReceived[stl.toUserId] || 0) + stl.amountPaise;
    }
  }

  // 3. Compute Net: paid - owed + sent - received
  // Sign check: A owes 200 (net = -200). A sends 200 confirmed. A's net = -200 + 200 = 0.
  let sumNets = 0;
  for (const uid of Object.keys(balances)) {
    const paid = totalPaid[uid] || 0;
    const owed = totalOwed[uid] || 0;
    const sent = totalSettledSent[uid] || 0;
    const received = totalSettledReceived[uid] || 0;

    const net = paid - owed + sent - received;
    balances[uid] = net;
    sumNets += net;
  }

  // 4. Assert zero-sum invariant
  if (sumNets !== 0) {
    throw new Error(
      `Zero-sum invariant violated! Sum of net balances across members is ${sumNets} paise (must be 0)`
    );
  }

  return {
    balances,
    totalPaid,
    totalOwed,
    totalSettledSent,
    totalSettledReceived,
  };
}
