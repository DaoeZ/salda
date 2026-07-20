/**
 * Runner TS de los vectores dorados compartidos con packages/domain.
 * Fuente única: packages/domain/test/golden/*.json. Si este test falla y el
 * Dart pasa (o viceversa), hay una divergencia entre motores: corregir la
 * implementación, NUNCA el vector, salvo revisión consciente de ambos lados.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';

import { computeBalance } from '../domain/balanceEngine.js';
import { computeEconomicLedger } from '../domain/economicLedger.js';
import { DomainError } from '../domain/errors.js';
import {
  splitTicket,
  type SplitMode,
  type SplitTicketInput,
} from '../domain/splitEngine.js';

const goldenDir = path.join(
  __dirname,
  '../../../../packages/domain/test/golden',
);

function loadCases(file: string): any[] {
  const json = JSON.parse(readFileSync(path.join(goldenDir, file), 'utf8'));
  return json.cases;
}

function assertDomainError(fn: () => unknown, code: string, name: string) {
  assert.throws(
    fn,
    (e: unknown) => e instanceof DomainError && e.code === code,
    `${name}: se esperaba DomainError(${code})`,
  );
}

for (const c of loadCases('split_engine.json')) {
  test(`golden split: ${c.name}`, () => {
    const run = () =>
      splitTicket({
        participantIds: c.participants,
        mode: c.mode as SplitMode,
        unassignedPolicy: c.unassignedPolicy === 'all' ? 'splitAmongAll' : 'error',
        payerId: c.payerId,
        ticket: c.ticket as SplitTicketInput,
      });

    if (c.expectedError) {
      assertDomainError(run, c.expectedError, c.name);
    } else {
      assert.deepEqual(run(), c.expected);
    }
  });
}

for (const c of loadCases('balance_engine.json')) {
  test(`golden balance: ${c.name}`, () => {
    const run = () =>
      computeBalance({
        participantIds: c.participants,
        tickets: c.tickets,
        frozenSettlements: c.frozenSettlements ?? [],
      });

    if (c.expectedError) {
      assertDomainError(run, c.expectedError, c.name);
    } else {
      const result = run();
      assert.deepEqual(result.balances, c.expected.balances);
      assert.deepEqual(result.settlements, c.expected.settlements);
    }
  });
}

for (const c of loadCases('economic_ledger.json')) {
  test(`golden economic: ${c.name}`, () => {
    assert.deepEqual(
      computeEconomicLedger({
        obligations: c.obligations,
        payments: c.payments,
      }),
      c.expected,
    );
  });
}
