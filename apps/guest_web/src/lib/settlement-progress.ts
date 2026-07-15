export interface SettlementTotals {
  settlementRequired: number;
  settledConfirmed: number;
  settledMarked: number;
}

export interface SettlementProgress {
  required: number;
  confirmed: number;
  marked: number;
  remaining: number;
  confirmedFraction: number;
  markedFraction: number;
  isSettled: boolean;
}

/**
 * Proyecta agregados autoritativos a fracciones visuales. No calcula deudas:
 * los tres importes proceden de recompute y ya están expresados en céntimos.
 */
export function settlementProgress(
  totals: SettlementTotals,
): SettlementProgress {
  const required = Math.max(0, totals.settlementRequired);
  const confirmed = Math.min(required, Math.max(0, totals.settledConfirmed));
  const marked = Math.min(
    required - confirmed,
    Math.max(0, totals.settledMarked),
  );
  return {
    required,
    confirmed,
    marked,
    remaining: required - confirmed,
    confirmedFraction: required === 0 ? 1 : confirmed / required,
    markedFraction: required === 0 ? 0 : marked / required,
    isSettled: required === confirmed,
  };
}
