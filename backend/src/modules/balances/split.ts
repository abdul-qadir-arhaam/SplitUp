export type SplitType = 'EQUAL' | 'EXACT' | 'PERCENT' | 'SHARES';

export interface ParticipantInput {
  userId: string;
  included: boolean;
  splitValue?: number; // exact amount, basis points (5000 = 50.00%), or shares count
}

export interface CalculatedSplit {
  userId: string;
  included: boolean;
  owedPaise: number;
}

/**
 * Calculates deterministic splits in integer paise ensuring:
 * 1. Excluded participants ("Not there") always receive owedPaise = 0
 * 2. Sum of all owedPaise across included participants strictly equals totalPaise
 * 3. Leftover paise distributed deterministically (by sorted userId)
 */
export function calculateSplits(
  totalPaise: number,
  splitType: SplitType,
  participants: ParticipantInput[]
): CalculatedSplit[] {
  if (!Number.isInteger(totalPaise) || totalPaise <= 0) {
    throw new Error('totalPaise must be a positive integer in paise');
  }

  // Sort participants deterministically by userId
  const sorted = [...participants].sort((a, b) => a.userId.localeCompare(b.userId));
  const included = sorted.filter((p) => p.included);

  if (included.length === 0) {
    throw new Error('Cannot split expense with zero included participants');
  }

  const result: CalculatedSplit[] = sorted.map((p) => ({
    userId: p.userId,
    included: p.included,
    owedPaise: 0,
  }));

  const resultMap = new Map<string, CalculatedSplit>(result.map((r) => [r.userId, r]));

  switch (splitType) {
    case 'EQUAL': {
      const count = included.length;
      const baseShare = Math.floor(totalPaise / count);
      const remainder = totalPaise % count;

      for (let i = 0; i < count; i++) {
        const p = included[i];
        // Distribute remainder paise 1-by-1 to the first remainder users in deterministic order
        const extra = i < remainder ? 1 : 0;
        resultMap.get(p.userId)!.owedPaise = baseShare + extra;
      }
      break;
    }

    case 'EXACT': {
      let sum = 0;
      for (const p of included) {
        const val = p.splitValue ?? 0;
        if (!Number.isInteger(val) || val < 0) {
          throw new Error(`EXACT split value for user ${p.userId} must be non-negative integer paise`);
        }
        resultMap.get(p.userId)!.owedPaise = val;
        sum += val;
      }
      if (sum !== totalPaise) {
        throw new Error(`Sum of EXACT splits (${sum}) does not equal totalPaise (${totalPaise})`);
      }
      break;
    }

    case 'PERCENT': {
      // splitValue in basis points: 10000 = 100.00%
      let totalBps = 0;
      for (const p of included) {
        totalBps += p.splitValue ?? 0;
      }
      if (totalBps !== 10000) {
        throw new Error(`Sum of PERCENT split values must equal 10000 basis points (100%), got ${totalBps}`);
      }

      let distributed = 0;
      const remainders: { userId: string; remainder: number }[] = [];

      for (const p of included) {
        const bps = p.splitValue ?? 0;
        const exactPaise = (totalPaise * bps) / 10000;
        const basePaise = Math.floor(exactPaise);
        resultMap.get(p.userId)!.owedPaise = basePaise;
        distributed += basePaise;
        remainders.push({ userId: p.userId, remainder: exactPaise - basePaise });
      }

      // Sort remainders descending, then by userId ascending
      remainders.sort((a, b) => b.remainder - a.remainder || a.userId.localeCompare(b.userId));
      let leftover = totalPaise - distributed;
      for (let i = 0; i < leftover; i++) {
        const target = remainders[i % remainders.length];
        resultMap.get(target.userId)!.owedPaise += 1;
      }
      break;
    }

    case 'SHARES': {
      let totalShares = 0;
      for (const p of included) {
        const s = p.splitValue ?? 1;
        if (!Number.isInteger(s) || s <= 0) {
          throw new Error(`SHARES split value for user ${p.userId} must be a positive integer`);
        }
        totalShares += s;
      }

      let distributed = 0;
      const remainders: { userId: string; remainder: number }[] = [];

      for (const p of included) {
        const s = p.splitValue ?? 1;
        const exactPaise = (totalPaise * s) / totalShares;
        const basePaise = Math.floor(exactPaise);
        resultMap.get(p.userId)!.owedPaise = basePaise;
        distributed += basePaise;
        remainders.push({ userId: p.userId, remainder: exactPaise - basePaise });
      }

      remainders.sort((a, b) => b.remainder - a.remainder || a.userId.localeCompare(b.userId));
      let leftover = totalPaise - distributed;
      for (let i = 0; i < leftover; i++) {
        const target = remainders[i % remainders.length];
        resultMap.get(target.userId)!.owedPaise += 1;
      }
      break;
    }
  }

  // Final invariant check: sum must strictly equal totalPaise
  const finalSum = result.reduce((acc, r) => acc + r.owedPaise, 0);
  if (finalSum !== totalPaise) {
    throw new Error(`Invariant violation: calculated splits sum (${finalSum}) does not match total (${totalPaise})`);
  }

  return result;
}
