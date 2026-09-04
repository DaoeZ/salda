/**
 * A19 — cierre de consumo: núcleo puro.
 *
 * Lo que se fija aquí es la frontera entre las dos cosas que `activeIds`
 * hacía a la vez: quién puede recibir consumo nuevo (el reparto) y quién
 * puede ser nombrado en un saldo (el libro). Y que una economía congelada
 * se usa LITERAL, sin reinterpretarla según quién siga activo.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  computeAggregates,
  frozenContribution,
  pickingFingerprint,
  ticketIsFirm,
  type SessionSnapshot,
  type TicketDoc,
} from '../recompute.js';

const linea = (id: string, unitIds: string[], totalPrice = 6000) => ({
  id,
  totalPrice,
  quantityMilli: unitIds.length * 1000,
  unitIds,
});

test('la huella cambia con la topología y con el modo, no con el precio', () => {
  const lines = [linea('l1', ['u0', 'u1'], 1000), linea('l0', ['u0'], 500)];
  const base = pickingFingerprint('byItem', lines);

  // El orden de lectura no importa: la huella se ordena por id.
  assert.equal(pickingFingerprint('byItem', [...lines].reverse()), base);

  // Corregir un precio NO invalida la elección de nadie.
  assert.equal(
    pickingFingerprint('byItem', [
      linea('l1', ['u0', 'u1'], 9999),
      linea('l0', ['u0'], 500),
    ]),
    base,
  );

  // Podar una unidad sí.
  assert.notEqual(
    pickingFingerprint('byItem', [linea('l1', ['u0'], 1000), linea('l0', ['u0'], 500)]),
    base,
  );
  // Que desaparezca una línea, también.
  assert.notEqual(pickingFingerprint('byItem', [lines[0]]), base);
  // Y cambiar de modo: en «a partes iguales» las líneas dejan de contar.
  assert.notEqual(pickingFingerprint('equal', lines), base);
});

test('un ticket legacy es firme siempre; uno byItem solo con open vacío', () => {
  const legacy = { lines: [] } as unknown as TicketDoc;
  assert.equal(ticketIsFirm(legacy, 'byItem', ['p1']), true);

  const abierto = {
    pickingModelVersion: 1,
    picking: { open: { p2: true }, fingerprint: pickingFingerprint('byItem', []) },
    lines: [],
  } as unknown as TicketDoc;
  assert.equal(ticketIsFirm(abierto, 'byItem', ['p1', 'p2']), false);
  // p2 ya no participa: deja de bloquear el cierre.
  assert.equal(ticketIsFirm(abierto, 'byItem', ['p1']), true);
  // A partes iguales el reparto no mira las líneas: no hay nada que esperar.
  assert.equal(ticketIsFirm(abierto, 'equal', ['p1', 'p2']), true);
});

test('una topología distinta de la sellada deja el ticket NO firme', () => {
  const ticket = {
    pickingModelVersion: 1,
    picking: { open: {}, fingerprint: 'byItem|l1:u0,u1' },
    lines: [linea('l1', ['u0', 'u1', 'u2'])],
  } as unknown as TicketDoc;
  assert.equal(ticketIsFirm(ticket, 'byItem', ['p1']), false);
});

test('la contribución congelada se devuelve LITERAL, sin sanear', () => {
  const ticket = {
    pickingModelVersion: 1,
    picking: {
      open: { p2: true },
      firmContribution: {
        paidBy: 'p1',
        grandTotal: 6000,
        consumption: { p2: 6000 },
      },
    },
    lines: [],
  } as unknown as TicketDoc;
  // Aunque p2 ya no esté activo, su consumo NO se dobla sobre el pagador:
  // el libro lo nombrará igualmente (ver `ledgerIds`).
  assert.deepEqual(frozenContribution(ticket), {
    paidBy: 'p1',
    grandTotal: 6000,
    consumption: { p2: 6000 },
  });
});

test('un ticket que nunca fue firme no aporta economía congelada', () => {
  const ticket = {
    pickingModelVersion: 1,
    picking: { open: { p1: true } },
    lines: [],
  } as unknown as TicketDoc;
  assert.equal(frozenContribution(ticket), undefined);
});

// ── El agregado completo ────────────────────────────────────────────────

const sesion = (ticket: Partial<TicketDoc>, opciones: {
  activos?: string[];
  confirmada?: boolean;
} = {}): SessionSnapshot => {
  const activos = opciones.activos ?? ['p1', 'p2'];
  return {
    splitModeDefault: 'byItem',
    ownerUid: 'uid-alba',
    currency: 'EUR',
    participants: [
      { id: 'p1', isOwner: true, order: 0, active: activos.includes('p1'), userUid: 'uid-alba' },
      { id: 'p2', order: 1, active: activos.includes('p2'), userUid: 'uid-jorge' },
    ],
    accounts: [{
      id: 'a1',
      tickets: [{
        id: 't1',
        grandTotal: 6000,
        paidByParticipantId: 'p1',
        splitModeOverride: 'byItem',
        lines: [{
          ...linea('l1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']),
          assignment: {
            type: 'units',
            schemaVersion: 2,
            units: { u0: { p2: true }, u1: { p2: true }, u2: { p2: true },
              u3: { p2: true }, u4: { p2: true }, u5: { p2: true } },
          },
        }],
        ...ticket,
      } as TicketDoc],
    }],
    settlements: opciones.confirmada
      ? [{ id: 'pending_p2_p1', from: 'p2', to: 'p1', amount: 6000, state: 'confirmed' }]
      : [],
  };
};

test('un ticket abierto no aporta economía firme, pero sí lo gastado', () => {
  const r = computeAggregates(sesion({
    pickingModelVersion: 1,
    picking: { open: { p1: true, p2: true } },
  }));
  assert.equal(r.balances.p2.consumed, 0);
  assert.equal(r.balances.p1.consumed, 0);
  assert.equal(r.settlementSync.writes.length, 0);
  assert.equal(r.economicEntries.length, 0);
  // Lo pagado es descriptivo, no un balance: se sigue contando.
  assert.equal(r.sessionTotals.grandTotal, 6000);
});

test('al cerrar el último pendiente aparece la economía completa', () => {
  const r = computeAggregates(sesion({
    pickingModelVersion: 1,
    picking: { open: {}, fingerprint: undefined },
  }));
  assert.equal(r.balances.p2.consumed, 6000);
  assert.equal(r.economicEntries.length, 1);
  assert.equal(r.economicEntries[0].amount, 6000);
  // Y se congela la economía del cierre para sostener pagos posteriores.
  const write = r.pickingWrites.find((w) => w.firmContribution);
  assert.deepEqual(write?.firmContribution?.consumption, { p1: 0, p2: 6000 });
});

test('el pagador y el consumidor provisional obtienen derecho histórico '
  + 'con el ticket todavía abierto', () => {
  const r = computeAggregates(sesion({
    pickingModelVersion: 1,
    picking: { open: { p1: true, p2: true } },
  }));
  const uids = r.ticketEntitlements.map((e) => e.uid).sort();
  assert.deepEqual(uids, ['uid-alba', 'uid-jorge']);
});

// ── El caso que obligó a congelar la contribución ──────────────────────

test('reabrir un ticket ya cobrado NO fabrica una deuda inversa', () => {
  const r = computeAggregates(sesion(
    {
      pickingModelVersion: 1,
      // Reabierto (p2 vuelve a estar pendiente) pero con la economía del
      // cierre congelada, y con la línea ya cambiada a 1 de 6.
      picking: {
        open: { p2: true },
        firmContribution: {
          paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
        },
      },
      lines: [{
        ...linea('l1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']),
        assignment: {
          type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        },
      }],
    },
    { confirmada: true },
  ));

  // La economía sigue siendo la del cierre, no la del reparto a medias.
  assert.equal(r.balances.p2.consumed, 6000);
  assert.equal(r.balances.p1.consumed, 0);
  // Nadie queda a deber nada por estar editando.
  assert.equal(r.balances.p1.outstanding, 0);
  assert.equal(r.balances.p2.outstanding, 0);
  // Ni liquidación inversa, ni ninguna nueva.
  assert.equal(r.settlementSync.writes.length, 0);
  assert.equal(r.pendingSettlements, 0);
  // La obligación no cambia mientras se edita.
  assert.equal(r.economicEntries.length, 1);
  assert.equal(r.economicEntries[0].amount, 6000);
});

test('ACTOR HISTÓRICO: el consumidor congelado pasa a active:false y la '
  + 'economía del cierre sigue cuadrando', () => {
  const r = computeAggregates(sesion(
    {
      pickingModelVersion: 1,
      picking: {
        // El ticket sigue REALMENTE abierto: p1, que sí está activo, aún no
        // ha terminado. Es la condición del invariante — si el único
        // pendiente fuera el inactivo, el ticket se cerraría solo y
        // estaríamos en el escenario de RECIERRE B, que es otra cosa.
        open: { p1: true, p2: true },
        firmContribution: {
          paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
        },
      },
      lines: [{
        ...linea('l1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']),
        assignment: {
          type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        },
      }],
    },
    { activos: ['p1'], confirmada: true },
  ));

  // No lanza `unknownParticipant`: p2 entra en el LIBRO aunque no en el
  // reparto. La economía del último cierre es idéntica.
  assert.equal(r.balances.p1.paid, 6000);
  assert.equal(r.balances.p1.consumed, 0);
  assert.equal(r.balances.p2.consumed, 6000);
  assert.equal(r.balances.p1.outstanding, 0);
  assert.equal(r.balances.p2.outstanding, 0);
  assert.equal(r.settlementSync.writes.length, 0);
  assert.equal(r.pendingSettlements, 0);
  assert.equal(r.economicEntries.length, 1);
  assert.equal(r.economicEntries[0].debtorUid, 'uid-jorge');
  assert.equal(r.economicEntries[0].creditorUid, 'uid-alba');
  assert.equal(r.economicEntries[0].amount, 6000);
});

test('REGRESIÓN previa a A19: una liquidación confirmada de alguien '
  + 'desactivado ya no rompe el recompute', () => {
  // Sin protocolo A19 en el ticket: es el caso que HOY lanzaba
  // `unknownParticipant` y dejaba la sesión entera sin recalcular, porque
  // la liquidación congelada nombra a p2 y p2 salía del universo.
  const r = computeAggregates(sesion({}, { activos: ['p1'], confirmada: true }));

  // Lo que arregla el libro es que esto NO reviente. El resultado económico
  // es el de siempre y es honesto: al dejar p2 de participar, su consumo
  // recae en quien pagó y los 60 € que ya había transferido pasan a ser un
  // saldo a su favor. No es una deuda inventada por A19: es la consecuencia
  // de desactivar a alguien que ya había pagado.
  assert.equal(r.balances.p1.consumed, 6000);
  assert.equal(r.balances.p2.outstanding, 6000);
  assert.equal(r.settlementSync.writes[0].from, 'p1');
  assert.equal(r.settlementSync.writes[0].to, 'p2');
  assert.equal(r.settlementSync.writes[0].amount, 6000);
});

// ── Recierre: DOS escenarios que no hay que confundir ──────────────────

test('RECIERRE A · Jorge vuelve a estar ACTIVO y se queda 1 de 6', () => {
  const r = computeAggregates(sesion(
    {
      pickingModelVersion: 1,
      picking: { open: {} },   // cerrado otra vez
      lines: [{
        ...linea('l1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']),
        assignment: {
          type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        },
      }],
    },
    { confirmada: true },
  ));
  assert.equal(r.balances.p1.consumed, 5000);
  assert.equal(r.balances.p2.consumed, 1000);
  assert.equal(r.economicEntries[0].amount, 1000);
  // Reconciliación contra el pago confirmado de 6000: Alba devuelve 5000.
  const inversa = r.settlementSync.writes[0];
  assert.equal(inversa.from, 'p1');
  assert.equal(inversa.to, 'p2');
  assert.equal(inversa.amount, 5000);
});

test('el último pendiente que se desactiva NO bloquea: el ticket se cierra '
  + 'solo y pasa a RECIERRE B', () => {
  const r = computeAggregates(sesion(
    {
      pickingModelVersion: 1,
      // p2 es el único pendiente y ya no está activo: nadie a quien esperar.
      picking: {
        open: { p2: true },
        firmContribution: {
          paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
        },
      },
      lines: [{
        ...linea('l1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']),
        assignment: {
          type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        },
      }],
    },
    { activos: ['p1'], confirmada: true },
  ));
  // Se cierra con el reparto VIGENTE, que ya no cuenta a Jorge: es RECIERRE
  // B, no el invariante del actor histórico. Sin esta regla, alguien
  // expulsado dejaría el gasto bloqueado para siempre.
  assert.equal(r.balances.p1.consumed, 6000);
});

test('RECIERRE B · Jorge sigue INACTIVO: sus unidades recaen en quien pagó', () => {
  const r = computeAggregates(sesion(
    {
      pickingModelVersion: 1,
      picking: { open: { p2: true } },   // p2 inactivo no bloquea
      lines: [{
        ...linea('l1', ['u0', 'u1', 'u2', 'u3', 'u4', 'u5']),
        assignment: {
          type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        },
      }],
    },
    { activos: ['p1'], confirmada: true },
  ));
  // El reparto vigente no cuenta a Jorge: 6000 al pagador, no 5000.
  assert.equal(r.balances.p1.consumed, 6000);
});
