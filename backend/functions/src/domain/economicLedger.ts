import { DomainError } from './errors.js';
import type { Cents } from './money.js';

export type EconomicPaymentStatus = 'pending' | 'confirmed' | 'cancelled';

export interface EconomicObligation {
  id: string;
  debtorUid: string;
  creditorUid: string;
  amount: Cents;
  currency: string;
}

export interface EconomicPaymentRecord {
  id: string;
  payerUid: string;
  receiverUid: string;
  amount: Cents;
  currency: string;
  status: EconomicPaymentStatus;
}

export interface BilateralEconomicBalance {
  firstUid: string;
  secondUid: string;
  currency: string;
  originalFirstToSecond: Cents;
  originalSecondToFirst: Cents;
  confirmedFirstToSecond: Cents;
  confirmedSecondToFirst: Cents;
  pendingFirstToSecond: Cents;
  pendingSecondToFirst: Cents;
  signedOutstanding: Cents;
}

type Accumulator = Omit<BilateralEconomicBalance, 'signedOutstanding'>;

/** Neteo bilateral puro; nunca transforma A→B + B→C en A→C. */
export function computeEconomicLedger(input: {
  obligations: EconomicObligation[];
  payments?: EconomicPaymentRecord[];
}): BilateralEconomicBalance[] {
  const accumulators = new Map<string, Accumulator>();

  for (const obligation of input.obligations) {
    validate(
      obligation.debtorUid,
      obligation.creditorUid,
      obligation.amount,
      obligation.currency,
    );
    const accumulator = forPair(
      accumulators,
      obligation.debtorUid,
      obligation.creditorUid,
      obligation.currency,
    );
    if (obligation.debtorUid === accumulator.firstUid) {
      accumulator.originalFirstToSecond += obligation.amount;
    } else {
      accumulator.originalSecondToFirst += obligation.amount;
    }
  }

  for (const payment of input.payments ?? []) {
    validate(
      payment.payerUid,
      payment.receiverUid,
      payment.amount,
      payment.currency,
    );
    if (payment.status === 'cancelled') continue;
    const accumulator = forPair(
      accumulators,
      payment.payerUid,
      payment.receiverUid,
      payment.currency,
    );
    const fromFirst = payment.payerUid === accumulator.firstUid;
    if (payment.status === 'confirmed') {
      if (fromFirst) accumulator.confirmedFirstToSecond += payment.amount;
      else accumulator.confirmedSecondToFirst += payment.amount;
    } else if (fromFirst) {
      accumulator.pendingFirstToSecond += payment.amount;
    } else {
      accumulator.pendingSecondToFirst += payment.amount;
    }
  }

  return [...accumulators.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([, value]) => ({
      ...value,
      signedOutstanding:
        value.originalFirstToSecond -
        value.originalSecondToFirst -
        value.confirmedFirstToSecond +
        value.confirmedSecondToFirst,
    }));
}

function forPair(
  accumulators: Map<string, Accumulator>,
  left: string,
  right: string,
  currency: string,
): Accumulator {
  const [firstUid, secondUid] = left.localeCompare(right) < 0
    ? [left, right]
    : [right, left];
  const key = `${currency}\0${firstUid}\0${secondUid}`;
  let value = accumulators.get(key);
  if (!value) {
    value = {
      firstUid,
      secondUid,
      currency,
      originalFirstToSecond: 0,
      originalSecondToFirst: 0,
      confirmedFirstToSecond: 0,
      confirmedSecondToFirst: 0,
      pendingFirstToSecond: 0,
      pendingSecondToFirst: 0,
    };
    accumulators.set(key, value);
  }
  return value;
}

function validate(from: string, to: string, amount: Cents, currency: string) {
  if (
    !from ||
    !to ||
    from === to ||
    !Number.isSafeInteger(amount) ||
    amount <= 0 ||
    !/^[A-Z]{3}$/.test(currency)
  ) {
    throw new DomainError('invalidEconomicRecord', 'Relación económica inválida');
  }
}
