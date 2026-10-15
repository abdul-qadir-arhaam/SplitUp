import type { Knex } from 'knex';
import { db } from '../../db/knex.js';

export interface LedgerMemberBalance {
  userId: string;
  netPaise: number;
}

export interface UserTotals {
  totalOwedPaise: number;
  totalReceivablePaise: number;
  netPaise: number;
}

/**
 * Authoritative SQL balance calculation directly matching docs/DATABASE.md Section 6.1.
 * net = paid - owed + settlements sent - settlements received (CONFIRMED settlements only).
 * Positive = member is owed money. Negative = member owes money.
 */
export async function getLedgerBalancesFromDb(
  ledgerId: string,
  trxOrDb: Knex = db
): Promise<Record<string, number>> {
  const query = `
    SELECT m.user_id,
           CAST(
             COALESCE(p.paid, 0) - COALESCE(s.owed, 0)
             + COALESCE(ss.sent, 0) - COALESCE(sr.received, 0)
           AS SIGNED) AS net_paise
    FROM ledger_members m
    LEFT JOIN (
        SELECT ep.user_id, SUM(ep.paid_paise) AS paid
        FROM expense_payers ep
        JOIN expenses e ON e.id = ep.expense_id
        WHERE e.ledger_id = ? AND e.deleted_at IS NULL
        GROUP BY ep.user_id
    ) p ON p.user_id = m.user_id
    LEFT JOIN (
        SELECT es.user_id, SUM(es.owed_paise) AS owed
        FROM expense_splits es
        JOIN expenses e ON e.id = es.expense_id
        WHERE e.ledger_id = ? AND e.deleted_at IS NULL AND es.included = 1
        GROUP BY es.user_id
    ) s ON s.user_id = m.user_id
    LEFT JOIN (
        SELECT from_user_id AS user_id, SUM(amount_paise) AS sent
        FROM settlements
        WHERE ledger_id = ? AND status = 'CONFIRMED'
        GROUP BY from_user_id
    ) ss ON ss.user_id = m.user_id
    LEFT JOIN (
        SELECT to_user_id AS user_id, SUM(amount_paise) AS received
        FROM settlements
        WHERE ledger_id = ? AND status = 'CONFIRMED'
        GROUP BY to_user_id
    ) sr ON sr.user_id = m.user_id
    WHERE m.ledger_id = ?;
  `;

  const [rows] = (await trxOrDb.raw(query, [ledgerId, ledgerId, ledgerId, ledgerId, ledgerId])) as [any[], any];

  const balances: Record<string, number> = {};
  let sumNets = 0;

  for (const r of rows) {
    const net = Number(r.net_paise) || 0;
    balances[r.user_id] = net;
    sumNets += net;
  }

  // Zero-sum invariant check per docs/DATABASE.md Section 7.3
  if (rows.length > 0 && sumNets !== 0) {
    throw new Error(
      `Zero-sum invariant violated for ledger ${ledgerId}! Sum of net balances across members is ${sumNets} paise (must be 0)`
    );
  }

  return balances;
}

/**
 * Calculates financial totals for a user across all ledgers they belong to.
 * Follows docs/DATABASE.md Section 6.2.
 */
export async function getUserTotalsFromDb(
  userId: string,
  trxOrDb: Knex = db
): Promise<UserTotals> {
  const memberLedgers = await trxOrDb('ledger_members')
    .where('user_id', userId)
    .whereNull('left_at')
    .select('ledger_id');

  let totalOwedPaise = 0;
  let totalReceivablePaise = 0;

  for (const row of memberLedgers) {
    const balances = await getLedgerBalancesFromDb(row.ledger_id, trxOrDb);
    const net = balances[userId] || 0;
    if (net < 0) {
      totalOwedPaise += Math.abs(net);
    } else if (net > 0) {
      totalReceivablePaise += net;
    }
  }

  return {
    totalOwedPaise,
    totalReceivablePaise,
    netPaise: totalReceivablePaise - totalOwedPaise,
  };
}
