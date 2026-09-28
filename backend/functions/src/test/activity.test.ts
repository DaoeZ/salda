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
  membershipCycleId,
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

// A11d: la distinción ya NO la da un marcador escrito sobre el documento
// que se va a borrar, sino la evidencia inmutable del ciclo.
test('salida voluntaria vs expulsión (evidencia del ciclo)', () => {
  const left = buildMemberEvents('sp1', 'carla',
    { uid: 'carla', joinedAt: ts(500) }, undefined, 'Viaje', ['ana']);
  assert.equal(left[0].type, 'member_left');
  assert.equal(left[0].actorUid, 'carla');
  assert.equal(left[0].at, undefined); // sin documento que feche el hecho

  const removed = buildMemberEvents('sp1', 'carla',
    { uid: 'carla', joinedAt: ts(500) }, undefined, 'Viaje', ['ana'],
    { uid: 'carla', membershipJoinedAt: ts(500), removedBy: 'ana',
      removedAt: ts(900) });
  assert.equal(removed[0].type, 'member_removed');
  assert.equal(removed[0].actorUid, 'ana');
  // El instante del hecho es el de la expulsión, no el del proceso: un
  // trigger retrasado no puede colocarlo donde no ocurrió.
  assert.equal((removed[0].at as { toMillis(): number }).toMillis(), 900);
  // El expulsado conserva el hecho en su audiencia.
  assert.ok(removed[0].memberUids.includes('carla'));
  // Mismo id: el tipo va en el campo, nunca en la identidad del hecho.
  assert.equal(removed[0].id, left[0].id);
});

test('la identidad del ciclo se deriva del joinedAt inmutable', () => {
  assert.equal(membershipCycleId('carla', ts(500)), 'carla_500');
  assert.notEqual(
    membershipCycleId('carla', ts(500)), membershipCycleId('carla', ts(900)));
});

// La carrera que motivó ADR-039: el evento del ciclo A se procesa cuando el
// grupo ya pasó por el ciclo B. La clasificación solo mira la evidencia de
// SU ciclo, así que el resultado no depende de por dónde vaya la persona.
test('un evento retrasado del ciclo A no lo falsifica un ciclo B posterior',
  () => {
    const evidenciaA = { uid: 'carla', membershipJoinedAt: ts(500),
      removedBy: 'ana', removedAt: ts(900) };
    const eventoA = () => buildMemberEvents('sp1', 'carla',
      { uid: 'carla', joinedAt: ts(500) }, undefined, 'Viaje', ['ana'],
      evidenciaA);

    // Reprocesarlo N veces da SIEMPRE el mismo hecho, id incluido.
    for (let i = 0; i < 5; i++) {
      assert.equal(eventoA()[0].type, 'member_removed');
      assert.equal(eventoA()[0].actorUid, 'ana');
      assert.equal(eventoA()[0].id, 'mb_sp1_carla_left_500');
      assert.equal(
        (eventoA()[0].at as { toMillis(): number }).toMillis(), 900);
    }

    // Y el desenlace del ciclo B es un hecho propio, con su id propio.
    const salidaB = buildMemberEvents('sp1', 'carla',
      { uid: 'carla', joinedAt: ts(1500) }, undefined, 'Viaje', ['ana']);
    assert.equal(salidaB[0].type, 'member_left');
    assert.equal(salidaB[0].id, 'mb_sp1_carla_left_1500');

    const expulsionB = buildMemberEvents('sp1', 'carla',
      { uid: 'carla', joinedAt: ts(1500) }, undefined, 'Viaje', ['ana'],
      { uid: 'carla', membershipJoinedAt: ts(1500), removedBy: 'ana',
        removedAt: ts(1900) });
    assert.equal(expulsionB[0].type, 'member_removed');
    assert.equal(expulsionB[0].id, 'mb_sp1_carla_left_1500');
    assert.notEqual(expulsionB[0].id, eventoA()[0].id);
  });

test('cambiar el rol de la membresía no genera eventos', () => {
  const events = buildMemberEvents('sp1', 'carla',
    { uid: 'carla', joinedAt: ts(500) },
    { uid: 'carla', joinedAt: ts(500), role: 'admin' }, 'Viaje', ['ana']);
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

test('A2 el borrado lo firma quien borró, no el dueño de la sesión', () => {
  // Ana creó el gasto; Edgar, que administra el grupo, lo elimina. Atribuirlo
  // a Ana sería falso y PERMANENTE: `persistEvents` es create-only.
  const [evento] = buildTicketEvents('s1', 't0', ticket(), undefined,
    'ana', ['ana', 'edgar'], 'Cena',
    { removedBy: 'edgar', removedAt: { toMillis: () => 1700 } });
  assert.equal(evento.type, 'ticket_deleted');
  assert.equal(evento.actorUid, 'edgar');
  // La hora es la del HECHO (evidencia), no la del proceso.
  assert.equal((evento.at as { toMillis: () => number }).toMillis(), 1700);
  // El id no cambia de formato: reintentar produce el mismo documento.
  assert.equal(evento.id, 'tk_s1_t0_deleted');
  // Y el resumen sigue congelado desde el `before`: es lo único que explica
  // después un pago que sobrevivió al gasto.
  assert.equal(evento.summary.ticketName, 'Casa Paco');
  assert.equal(evento.summary.amount, 5190);
});

test('A2 el borrado del propio dueño se atribuye a él mismo', () => {
  const [evento] = buildTicketEvents('s1', 't0', ticket(), undefined,
    'ana', ['ana'], 'Cena',
    { removedBy: 'ana', removedAt: { toMillis: () => 900 } });
  assert.equal(evento.actorUid, 'ana');
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

// ── Correcciones administrativas firmadas (A11c) ──────────────────────────
// La firma la renueva SOLO una corrección, y viaja en el mismo batch que el
// cambio de las líneas. De ahí salen las tres propiedades que se fijan aquí:
// actor real, un evento por operación, y ninguna atribución heredada.

/// Firma tal y como llega del trigger: un Timestamp de Firestore.
const firma = (uid: string, millis: number) => ({
  lastEditedByUid: uid,
  lastEditedAt: { toMillis: () => millis },
});

test('A11c corrección de cabecera: el actor es quien firma, no el dueño',
    () => {
  const eventos = buildTicketEvents('s1', 't0',
    ticket(),
    ticket({ grandTotal: 6000, ...firma('edgar', 1000) }),
    'ana', ['ana', 'edgar'], 'Cena');

  assert.equal(eventos.length, 1);
  assert.equal(eventos[0].type, 'ticket_updated');
  assert.equal(eventos[0].actorUid, 'edgar');
});

test('A11c corrección SOLO de líneas: la firma basta para contar el hecho',
    () => {
  // Ni el comercio, ni el total, ni la fecha, ni el pagador cambian: lo
  // corregido fueron productos. Antes esto no dejaba rastro ninguno.
  const eventos = buildTicketEvents('s1', 't0',
    ticket(),
    ticket(firma('edgar', 1000)),
    'ana', ['ana', 'edgar'], 'Cena');

  assert.equal(eventos.length, 1);
  assert.equal(eventos[0].type, 'ticket_updated');
  assert.equal(eventos[0].actorUid, 'edgar');
});

test('A11c el creador corrigiendo lo suyo sigue siendo el actor', () => {
  const eventos = buildTicketEvents('s1', 't0',
    ticket(),
    ticket({ grandTotal: 6000, ...firma('ana', 1000) }),
    'ana', ['ana'], 'Cena');

  assert.equal(eventos[0].actorUid, 'ana');
});

test('A11c una operación con varios cambios NO produce spam de eventos', () => {
  // Comercio + total + fecha + pagador + líneas, todo en la misma escritura
  // firmada: sigue siendo UN hecho, «Edgar corrigió el ticket».
  const eventos = buildTicketEvents('s1', 't0',
    ticket(),
    ticket({
      merchant: { name: 'Familycash' },
      grandTotal: 6000,
      date: '2026-08-19',
      paidByParticipantId: 'p1',
      ...firma('edgar', 1000),
    }),
    'ana', ['ana', 'edgar'], 'Cena');

  assert.equal(eventos.length, 1);
  assert.equal(eventos[0].actorUid, 'edgar');
});

test('A11c dos correcciones distintas que acaban igual son DOS hechos', () => {
  // 30 € → 3 € y, más tarde, 3 € → 30 €. Con el id derivado del estado
  // destino la segunda se perdía como si fuera un reintento de la primera.
  const bajada = buildTicketEvents('s1', 't0',
    ticket({ grandTotal: 3000 }),
    ticket({ grandTotal: 300, ...firma('edgar', 1000) }),
    'ana', ['ana'], 'Cena');
  const subida = buildTicketEvents('s1', 't0',
    ticket({ grandTotal: 300, ...firma('edgar', 1000) }),
    ticket({ grandTotal: 3000, ...firma('edgar', 2000) }),
    'ana', ['ana'], 'Cena');

  assert.notEqual(bajada[0].id, subida[0].id);
});

test('A11c reintentar la MISMA corrección da el mismo id (idempotente)', () => {
  const run = () => buildTicketEvents('s1', 't0',
    ticket(),
    ticket({ grandTotal: 6000, ...firma('edgar', 1000) }),
    'ana', ['ana'], 'Cena');

  assert.equal(run()[0].id, run()[0].id);
});

test('A11c una escritura POSTERIOR sin firmar no se atribuye a quien '
    + 'corrigió antes', () => {
  // El ticket conserva la firma de Edgar, pero esta escritura no la renueva:
  // es otro flujo (el dueño). Heredar el actor sería inventarse un culpable.
  const corregido = ticket({ grandTotal: 6000, ...firma('edgar', 1000) });
  const eventos = buildTicketEvents('s1', 't0',
    corregido,
    { ...corregido, date: '2026-09-01' },
    'ana', ['ana', 'edgar'], 'Cena');

  assert.equal(eventos.length, 1);
  assert.equal(eventos[0].actorUid, 'ana');
});

test('A11c un ticket sin firma se comporta exactamente como antes', () => {
  const eventos = buildTicketEvents('s1', 't0',
    ticket(), ticket({ grandTotal: 6000 }), 'ana', ['ana'], 'Cena');

  assert.equal(eventos.length, 1);
  assert.equal(eventos[0].actorUid, 'ana');
  // Mismo id de siempre: el esquema del flujo no firmado no se toca.
  assert.equal(eventos[0].id,
    buildTicketEvents('s1', 't0', ticket(), ticket({ grandTotal: 6000 }),
      'ana', ['ana'], 'Cena')[0].id);
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
