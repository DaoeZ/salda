/**
 * Motor de balance y simplificación de deudas — espejo exacto de
 * packages/domain/lib/src/engines/balance_engine.dart.
 */
import { DomainError } from './errors.js';
import type { Cents } from './money.js';

export interface TicketContribution {
  readonly paidBy: string;
  readonly grandTotal: Cents;
  readonly consumption: Readonly<Record<string, Cents>>;
}

export interface FrozenSettlement {
  readonly from: string;
  readonly to: string;
  readonly amount: Cents;
}

export interface SettlementDraft {
  readonly from: string;
  readonly to: string;
  readonly amount: Cents;
}

export interface ParticipantBalance {
  readonly paid: Cents;
  readonly consumed: Cents;
  /** paid − consumed (positivo = le deben). */
  readonly net: Cents;
  /** net ajustado por liquidaciones congeladas. */
  readonly outstanding: Cents;
}

export interface BalanceResult {
  readonly balances: Record<string, ParticipantBalance>;
  readonly settlements: SettlementDraft[];
}

export function computeBalance(params: {
  participantIds: readonly string[];
  tickets: readonly TicketContribution[];
  frozenSettlements?: readonly FrozenSettlement[];
}): BalanceResult {
  const { participantIds, tickets } = params;
  const frozenSettlements = params.frozenSettlements ?? [];

  if (participantIds.length === 0) {
    throw new DomainError(
      'emptyParticipants',
      'Una sesión necesita al menos un participante',
    );
  }
  const known = new Set(participantIds);

  const paid = new Map(participantIds.map((p) => [p, 0]));
  const consumed = new Map(participantIds.map((p) => [p, 0]));

  for (const ticket of tickets) {
    if (!known.has(ticket.paidBy)) {
      throw new DomainError(
        'unknownParticipant',
        `Pagador desconocido "${ticket.paidBy}"`,
      );
    }
    let consumptionSum = 0;
    for (const [pid, cents] of Object.entries(ticket.consumption)) {
      if (!known.has(pid)) {
        throw new DomainError(
          'unknownParticipant',
          `Consumidor desconocido "${pid}"`,
        );
      }
      consumed.set(pid, consumed.get(pid)! + cents);
      consumptionSum += cents;
    }
    if (consumptionSum !== ticket.grandTotal) {
      throw new DomainError(
        'consumptionMismatch',
        `El consumo (${consumptionSum}) no cuadra con el total (${ticket.grandTotal})`,
      );
    }
    paid.set(ticket.paidBy, paid.get(ticket.paidBy)! + ticket.grandTotal);
  }

  const outstanding = new Map(
    participantIds.map((p) => [p, paid.get(p)! - consumed.get(p)!]),
  );
  for (const frozen of frozenSettlements) {
    if (!known.has(frozen.from) || !known.has(frozen.to)) {
      throw new DomainError(
        'unknownParticipant',
        'Liquidación congelada con participante desconocido',
      );
    }
    outstanding.set(frozen.from, outstanding.get(frozen.from)! + frozen.amount);
    outstanding.set(frozen.to, outstanding.get(frozen.to)! - frozen.amount);
  }

  return {
    balances: Object.fromEntries(
      participantIds.map((p) => [
        p,
        {
          paid: paid.get(p)!,
          consumed: consumed.get(p)!,
          net: paid.get(p)! - consumed.get(p)!,
          outstanding: outstanding.get(p)!,
        },
      ]),
    ),
    settlements: simplify(participantIds, outstanding),
  };
}

/** Voraz determinista: mayor deudor paga al mayor acreedor (empate → orden de participantes). */
function simplify(
  participantIds: readonly string[],
  outstanding: ReadonlyMap<string, Cents>,
): SettlementDraft[] {
  const position = new Map(participantIds.map((p, i) => [p, i]));
  const creditors: Array<[string, number]> = [];
  const debtors: Array<[string, number]> = [];
  for (const p of participantIds) {
    const cents = outstanding.get(p)!;
    if (cents > 0) creditors.push([p, cents]);
    if (cents < 0) debtors.push([p, -cents]);
  }

  const byAmountThenOrder = (a: [string, number], b: [string, number]) =>
    b[1] - a[1] || position.get(a[0])! - position.get(b[0])!;

  const result: SettlementDraft[] = [];
  while (creditors.length > 0 && debtors.length > 0) {
    creditors.sort(byAmountThenOrder);
    debtors.sort(byAmountThenOrder);
    const [creditor, creditorAmount] = creditors[0];
    const [debtor, debtorAmount] = debtors[0];
    const amount = Math.min(creditorAmount, debtorAmount);

    result.push({ from: debtor, to: creditor, amount });

    creditors.shift();
    debtors.shift();
    if (creditorAmount - amount > 0) creditors.push([creditor, creditorAmount - amount]);
    if (debtorAmount - amount > 0) debtors.push([debtor, debtorAmount - amount]);
  }
  return result;
}
