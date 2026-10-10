export interface SimplifiedPayment {
  from: string; // debtor
  to: string;   // creditor
  amountPaise: number;
}

/**
 * Debt Simplification Algorithm (Min-Cash-Flow):
 * Minimizes transactions in group/trip ledgers to at most (n - 1) payments.
 * Repeatedly pairs the largest debtor with the largest creditor.
 */
export function simplifyDebts(netBalances: Record<string, number>): SimplifiedPayment[] {
  // Extract and filter non-zero balances
  const debtors: { userId: string; net: number }[] = [];
  const creditors: { userId: string; net: number }[] = [];

  let totalNet = 0;
  for (const [userId, net] of Object.entries(netBalances)) {
    totalNet += net;
    if (net < 0) {
      debtors.push({ userId, net });
    } else if (net > 0) {
      creditors.push({ userId, net });
    }
  }

  if (totalNet !== 0) {
    throw new Error(`Cannot simplify debts: net balances do not sum to zero (sum = ${totalNet})`);
  }

  const payments: SimplifiedPayment[] = [];

  // Greedy match largest debtor with largest creditor
  while (debtors.length > 0 && creditors.length > 0) {
    // Sort debtors ascending (most negative first)
    debtors.sort((a, b) => a.net - b.net);
    // Sort creditors descending (most positive first)
    creditors.sort((a, b) => b.net - a.net);

    const debtor = debtors[0];
    const creditor = creditors[0];

    const debtorOwes = Math.abs(debtor.net);
    const creditorIsOwed = creditor.net;

    const paymentAmount = Math.min(debtorOwes, creditorIsOwed);

    if (paymentAmount > 0) {
      payments.push({
        from: debtor.userId,
        to: creditor.userId,
        amountPaise: paymentAmount,
      });
    }

    debtor.net += paymentAmount;
    creditor.net -= paymentAmount;

    if (debtor.net === 0) {
      debtors.shift();
    }
    if (creditor.net === 0) {
      creditors.shift();
    }
  }

  const memberCount = Object.keys(netBalances).length;
  if (payments.length > Math.max(0, memberCount - 1)) {
    throw new Error(
      `Simplification invariant violated: expected at most ${memberCount - 1} payments, got ${payments.length}`
    );
  }

  return payments;
}
