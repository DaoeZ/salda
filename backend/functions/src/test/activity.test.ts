/**
 * P6 — builders puros de actividad: tipos, actores, audiencia congelada e
 * IDs deterministas (idempotencia ante reintentos de trigger y recompute).
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  activityAudience,
  activityAudienceLimit,
  buildEconomicPaymentEvents,
  buildInviteEvents,
  buildMemberEvents,
  buildSettlementEvents,
  buildSpaceEvents,
  buildTicketEvents,
} from '../activity.js';

const ts = (millis: number) => ({ toMillis: () => millis });

// ── Audiencia ─────────────────────────────────────────────────────────────

test('audiencia: única, ordenada, sin vacíos y acotada', () => {
  assert.deepEqual(activityAudience(['b', 'a', 'b', '', 'a']), ['a', 'b']);
  const many = activityAudience(
    Array.from({ length: 100 }, (_, i) => `u${String(i).padStart(3, '0')}`),
  );
  assert.equal(many.length, activityAudienceLimit);
});

// ── Espacios ──────────────────────────────────────────────────────────────

test('espacio creado: un evento con el owner como actor', () => {
  const events = buildSpaceEvents('sp1', undefined, {
    name: 'Viaje', ownerUid: 'ana', status: 'active', updatedAt: ts(1000),
  }, ['ana']);
  assert.equal(events.length, 1);
  assert.equal(events[0].type, 'space_created');
  assert.equal(events[0].actorUid, 'ana');
  assert.equal(events[0].id, 'sp_sp1_created');
  assert.equal(events[0].summary.spaceName, 'Viaje');
});

test('renombrar, archivar y reactivar generan eventos con id estable', () => {
  const base = {
    name: 'Viaje', ownerUid: 'ana', status: 'active', updatedAt: ts(1000),
  };
  const renamed = buildSpaceEvents('sp1', base,
    { ...base, name: 'Viaje 2026', updatedAt: ts(2000) }, ['ana', 'bo']);
  assert.equal(renamed[0].type, 'space_renamed');
  assert.equal(renamed[0].id, 'sp_sp1_renamed_2000');

  const archived = buildSpaceEvents('sp1', base,
    { ...base, status: 'archived', updatedAt: ts(3000) }, ['ana']);
  assert.equal(archived[0].type, 'space_archived');

  const reactivated = buildSpaceEvents('sp1',
    { ...base, status: 'archived' },
    { ...base, status: 'active', updatedAt: ts(4000) }, ['ana']);
  assert.equal(reactivated[0].type, 'space_reactivated');
});

test('transferencia: el actor es el owner ANTERIOR', () => {
  const events = buildSpaceEvents('sp1',
    { name: 'Piso', ownerUid: 'ana', status: 'active', updatedAt: ts(1) },
    { name: 'Piso', ownerUid: 'bo', status: 'active', updatedAt: ts(2) },
    ['ana', 'bo']);
  assert.equal(events.length, 1);
  assert.equal(events[0].type, 'space_transferred');
  assert.equal(events[0].actorUid, 'ana');
});

test('reintento del trigger produce exactamente el MISMO id', () => {
  const run = () => buildSpaceEvents('sp1',
    { name: 'A', ownerUid: 'ana', status: 'active', updatedAt: ts(1) },
    { name: 'B', ownerUid: 'ana', status: 'active', updatedAt: ts(9) },
    ['ana']);
  assert.deepEqual(run(), run());
});

// ── Miembros ──────────────────────────────────────────────────────────────

test('incorporación: actor = el propio miembro', () => {
  const events = buildMemberEvents('sp1', 'carla', undefined,
    { uid: 'carla', joinedAt: ts(500) }, 'Viaje', ['ana', 'carla']);
  assert.equal(events[0].type, 'member_joined');
  assert.equal(events[0].actorUid, 'carla');
  assert.equal(events[0].id, 'mb_sp1_carla_join_500');
});

test('salida voluntaria vs expulsión (marcador removedBy del owner)', () => {
  const left = buildMemberEvents('sp1', 'carla',
    { uid: 'carla', joinedAt: ts(500) }, undefined, 'Viaje', ['ana']);
  assert.equal(left[0].type, 'member_left');
  assert.equal(left[0].actorUid, 'carla');

  const removed = buildMemberEvents('sp1', 'carla',
    { uid: 'carla', joinedAt: ts(500), removedBy: 'ana' }, undefined,
    'Viaje', ['ana']);
  assert.equal(removed[0].type, 'member_removed');
  assert.equal(removed[0].actorUid, 'ana');
  // El expulsado conserva el hecho en su audiencia.
  assert.ok(removed[0].memberUids.includes('carla'));
});

test('actualizar la membresía (solo el marcador) no genera eventos', () => {
  const events = buildMemberEvents('sp1', 'carla',
    { uid: 'carla', joinedAt: ts(500) },
    { uid: 'carla', joinedAt: ts(500), removedBy: 'ana' }, 'Viaje', ['ana']);
  assert.deepEqual(events, []);
});

// ── Invitaciones ──────────────────────────────────────────────────────────

test('invitación enviada y reenviada; resoluciones privadas sin evento', () => {
  const pending = {
    spaceId: 'sp1', spaceName: 'Viaje', fromUid: 'ana', toUid: 'carla',
    status: 'pending', updatedAt: ts(100),
  };
  const sent = buildInviteEvents('sp1_carla', undefined, pending);
  assert.equal(sent[0].type, 'invite_sent');
  assert.deepEqual(sent[0].memberUids, ['ana', 'carla']);

  const resent = buildInviteEvents('sp1_carla',
    { ...pending, status: 'rejected' }, { ...pending, updatedAt: ts(300) });
  assert.equal(resent.length, 1);
  assert.notEqual(resent[0].id, sent[0].id); // reenvío = hecho nuevo

  for (const status of ['accepted', 'rejected', 'cancelled']) {
    assert.deepEqual(
      buildInviteEvents('sp1_carla', pending, { ...pending, status }),
      [],
    );
  }
});

// ── Tickets ───────────────────────────────────────────────────────────────

const ticket = (overrides: Record<string, unknown> = {}) => ({
  merchant: { name: 'Casa Paco' },
  grandTotal: 5190,
  date: '2026-07-19',
  paidByParticipantId: 'p0',
  spaceId: '',
  ...overrides,
});

test('ticket creado/borrado con audiencia y rótulos congelados', () => {
  const created = buildTicketEvents('s1', 't0', undefined, ticket(),
    'ana', ['ana', 'bo'], 'Cena');
  assert.equal(created[0].type, 'ticket_created');
  assert.equal(created[0].id, 'tk_s1_t0_created');
  assert.equal(created[0].actorUid, 'ana');
  assert.equal(created[0].summary.ticketName, 'Casa Paco');
  assert.equal(created[0].summary.amount, 5190);

  const deleted = buildTicketEvents('s1', 't0', ticket(), undefined,
    'ana', ['ana'], 'Cena');
  assert.equal(deleted[0].type, 'ticket_deleted');
});

test('edición relevante = UN evento; ruido técnico = ninguno', () => {
  const relevant = buildTicketEvents('s1', 't0', ticket(),
    ticket({ grandTotal: 6000 }), 'ana', ['ana'], 'Cena');
  assert.equal(relevant.length, 1);
  assert.equal(relevant[0].type, 'ticket_updated');

  // imagePath/ocr/etc. no aparecen en el feed.
  const noise = buildTicketEvents('s1', 't0', ticket(),
    { ...ticket(), imagePath: 'receipts/x.jpg', computeHint: 3 },
    'ana', ['ana'], 'Cena');
  assert.deepEqual(noise, []);
});

test('mismo estado destino ⇒ mismo id (reintento no duplica)', () => {
  const run = () => buildTicketEvents('s1', 't0', ticket(),
    ticket({ grandTotal: 6000 }), 'ana', ['ana'], 'Cena');
  assert.equal(run()[0].id, run()[0].id);
});

test('vincular y desvincular de un espacio', () => {
  const linked = buildTicketEvents('s1', 't0', ticket(),
    ticket({ spaceId: 'sp1' }), 'ana', ['ana', 'bo'], 'Cena');
  assert.equal(linked[0].type, 'ticket_linked');
  assert.equal(linked[0].spaceId, 'sp1');

  const unlinked = buildTicketEvents('s1', 't0', ticket({ spaceId: 'sp1' }),
    ticket(), 'ana', ['ana'], 'Cena');
  assert.equal(unlinked[0].type, 'ticket_unlinked');
  assert.equal(unlinked[0].spaceId, 'sp1');
});

// ── Settlements humanos (flujo antiguo) ───────────────────────────────────

const resolver = (map: Record<string, string>) => (pid: string) => map[pid];

test('marked/confirmed generan pago con actor real; pending jamás', () => {
  const marked = buildSettlementEvents('s1', 'st1',
    { state: 'pending' }, { state: 'marked', from: 'p2', to: 'p1', amount: 500 },
    resolver({ p1: 'ana', p2: 'bo' }), ['ana'], 'Cena', 'EUR');
  assert.equal(marked[0].type, 'payment_marked');
  assert.equal(marked[0].actorUid, 'bo');
  assert.equal(marked[0].id, 'st_s1_st1_marked');

  const confirmed = buildSettlementEvents('s1', 'st1',
    { state: 'marked' },
    { state: 'confirmed', from: 'p2', to: 'p1', amount: 500 },
    resolver({ p1: 'ana', p2: 'bo' }), ['ana'], 'Cena', 'EUR');
  assert.equal(confirmed[0].type, 'payment_confirmed');
  assert.equal(confirmed[0].actorUid, 'ana');

  // recompute solo escribe pending: nunca es un evento.
  assert.deepEqual(buildSettlementEvents('s1', 'st9', undefined,
    { state: 'pending', from: 'p2', to: 'p1', amount: 100 },
    resolver({ p1: 'ana', p2: 'bo' }), ['ana'], 'Cena', 'EUR'), []);
  // Reescritura sin cambio de estado: nada.
  assert.deepEqual(buildSettlementEvents('s1', 'st1',
    { state: 'marked' }, { state: 'marked', from: 'p2', to: 'p1', amount: 500 },
    resolver({ p1: 'ana', p2: 'bo' }), ['ana'], 'Cena', 'EUR'), []);
});

test('sin identidad real del actor no se inventa un evento', () => {
  const events = buildSettlementEvents('s1', 'st1',
    { state: 'pending' },
    { state: 'marked', from: 'p9', to: 'p1', amount: 500 },
    resolver({ p1: 'ana' }), ['ana'], 'Cena', 'EUR');
  assert.deepEqual(events, []);
});

// ── Pagos P5 ──────────────────────────────────────────────────────────────

const payment = (status: string, byUid: string) => ({
  source: 'user',
  status,
  amount: 1200,
  currency: 'EUR',
  memberUids: ['ana', 'bo'],
  stateHistory: [
    { status: 'pending', byUid: 'bo' },
    ...(status === 'pending' ? [] : [{ status, byUid }]),
  ],
});

test('pago P5: marcado, confirmado y cancelado con actor del historial', () => {
  const marked = buildEconomicPaymentEvents('pay1', undefined,
    payment('pending', 'bo'));
  assert.equal(marked[0].type, 'payment_marked');
  assert.equal(marked[0].actorUid, 'bo');

  const confirmed = buildEconomicPaymentEvents('pay1',
    payment('pending', 'bo'), payment('confirmed', 'ana'));
  assert.equal(confirmed[0].type, 'payment_confirmed');
  assert.equal(confirmed[0].actorUid, 'ana');

  const cancelled = buildEconomicPaymentEvents('pay1',
    payment('pending', 'bo'), payment('cancelled', 'bo'));
  assert.equal(cancelled[0].type, 'payment_cancelled');
});

test('proyecciones legacy y reescrituras de recompute no generan eventos', () => {
  // Legacy: el hecho ya se registró desde el settlement humano.
  assert.deepEqual(buildEconomicPaymentEvents('legacy_st1', undefined, {
    ...payment('confirmed', 'ana'), source: 'legacySettlement',
  }), []);
  // Reescritura idéntica (recompute): sin transición, sin evento.
  assert.deepEqual(buildEconomicPaymentEvents('pay1',
    payment('confirmed', 'ana'), payment('confirmed', 'ana')), []);
});

test('ids de pago deterministas por estado (doble trigger converge)', () => {
  const a = buildEconomicPaymentEvents('pay1', undefined,
    payment('pending', 'bo'))[0].id;
  const b = buildEconomicPaymentEvents('pay1', undefined,
    payment('pending', 'bo'))[0].id;
  assert.equal(a, b);
});
