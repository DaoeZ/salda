import { describe, expect, it } from 'vitest';

import { settlementProgress } from './settlement-progress';

describe('progreso de liquidación', () => {
  it('usa obligaciones y no el gasto total', () => {
    const progress = settlementProgress({
      settlementRequired: 6000,
      settledConfirmed: 6000,
      settledMarked: 0,
    });
    expect(progress.confirmedFraction).toBe(1);
    expect(progress.isSettled).toBe(true);
  });

  it('separa lo marcado de lo confirmado', () => {
    const progress = settlementProgress({
      settlementRequired: 6000,
      settledConfirmed: 2000,
      settledMarked: 1000,
    });
    expect(progress.confirmedFraction).toBeCloseTo(1 / 3);
    expect(progress.markedFraction).toBeCloseTo(1 / 6);
    expect(progress.remaining).toBe(4000);
    expect(progress.isSettled).toBe(false);
  });

  it('0/0 significa saldado sin dividir por cero', () => {
    const progress = settlementProgress({
      settlementRequired: 0,
      settledConfirmed: 0,
      settledMarked: 0,
    });
    expect(progress.confirmedFraction).toBe(1);
    expect(progress.markedFraction).toBe(0);
    expect(progress.isSettled).toBe(true);
  });
});
