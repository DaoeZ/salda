/**
 * recompute — la calculadora autoritativa (spec §12.2, DC-7).
 *
 * Se dispara al escribir líneas, tickets o participantes y recalcula:
 * totales por cuenta, totales/balances de sesión y liquidaciones pendientes.
 * Escribe SOLO si algo cambió (sin cambio no hay bump de computeVersion →
 * sin cascadas). Determinista: ejecuciones concurrentes convergen al mismo
 * resultado. Usa los MISMOS motores validados por vectores dorados.
 *
 * Robustez ante datos huérfanos (participante borrado con asignaciones o
 * pagos colgando): se sanea (se ignoran pids desconocidos; un pagador
 * desconocido se reasigna al participante-owner) y se deja constancia en logs.
 */
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  computeBalance,
  type FrozenSettlement,
  type ParticipantBalance,
  type SettlementDraft,
  type TicketContribution,
} from './domain/balanceEngine.js';
import {
  accountUidsOf,
  isManualActor,
  manualActor,
  resolveActorIdentity,
} from './domain/economicActor.js';
import type { Cents } from './domain/money.js';
import {
  splitTicket,
  unitsFromQuantityMilli,
  type SplitLine,
  type SplitMode,
} from './domain/splitEngine.js';

// ── Modelo en memoria (independiente de Firestore para poder testearlo) ──

/**
 * UID económico de un participante de sesión.
 *
 * `registeredUids` son las identidades REALES existentes: cuentas con perfil
 * público (P2) **e invitados** con identidad de dispositivo (ADR-034). Un
 * invitado no tiene perfil público por diseño, pero tiene UID propio y
 * participa económicamente igual que una cuenta: excluirlo dejaría sus
 * gastos fuera de los balances.
 *
 * Un `claimedByDevice` sin identidad registrada (invitado web de sesión, P1)
 * NO se eleva a identidad económica global: sigue viviendo en el balance de
 * su sesión, sin inventar una relación permanente.
 */
export function resolveParticipantUid(params: {
  isOwner?: boolean;
  claimedByDevice?: string;
  sessionOwnerUid?: string;
  registeredUids: ReadonlySet<string>;
}): string | undefined {
  if (params.isOwner === true) return params.sessionOwnerUid;
  const claimed = params.claimedByDevice;
  return claimed && params.registeredUids.has(claimed) ? claimed : undefined;
}

export interface ParticipantDoc {
  id: string;
  /** Nombre visible; solo se proyecta en el derecho histórico (A11d). */
  name?: string;
  isOwner?: boolean;
  active?: boolean;
  order?: number;
  /** P5: identidad registrada estable. No confundir con claimedByDevice. */
  userUid?: string;
  /**
   * ADR-033: participante MANUAL (sin cuenta ni UID). Su actor económico es
   * `manual:{manualId}` y pesa igual que una cuenta en las obligaciones.
   */
  manualId?: string;
  claimedByDevice?: string;
}

export interface LineDoc {
  id: string;
  totalPrice: Cents;
  /** Cantidad ×1000; define las unidades reclamables de la línea (P2.1). */
  quantityMilli?: number;
  /** Unidades declaradas por la línea; entra en la huella de A19. */
  unitIds?: string[];
  assignment?: {
    type?: string;
    participants?: Record<string, number>;
    schemaVersion?: number;
    units?: Record<string, Record<string, boolean | number>>;
  };
}

/** Última economía FIRME de un ticket (A19). La escribe SOLO recompute. */
export interface FirmContribution {
  paidBy: string;
  grandTotal: Cents;
  consumption: Record<string, Cents>;
}

export interface TicketDoc {
  id: string;
  grandTotal: Cents;
  paidByParticipantId: string;
  splitModeOverride?: SplitMode;
  merchantName?: string;
  date?: string;
  spaceId?: string;
  /** 1 = el gasto espera a que todos terminen de elegir (A19). */
  pickingModelVersion?: number;
  picking?: {
    open?: Record<string, boolean>;
    fingerprint?: string;
    firmContribution?: FirmContribution;
  };
  lines: LineDoc[];
}

export interface AccountDoc {
  id: string;
  name?: string;
  tickets: TicketDoc[];
}

export interface SettlementDoc {
  id: string;
  from: string;
  to: string;
  amount: Cents;
  state: 'pending' | 'marked' | 'confirmed';
}

export interface SessionSnapshot {
  splitModeDefault: SplitMode;
  ownerUid?: string;
  currency?: string;
  participants: ParticipantDoc[];
  accounts: AccountDoc[];
  settlements: SettlementDoc[];
  /** Pagos P5 confirmados que afectan a tickets de esta sesión. */
  externalConfirmed?: Array<{ from: string; to: string; amount: Cents }>;
  /**
   * VINCULACIÓN (ADR-037): `manualId → uid` de los manuales ya vinculados y
   * APROBADOS por el anfitrión. No cambia ningún actor: solo hace que la
   * persona vinculada sea LECTORA de las obligaciones que ya existían.
   */
  manualAliases?: Record<string, string>;
}

export interface TicketParticipantProjection {
  ticketId: string;
  pid: string;
  /** Identidad ESTABLE del participante; nunca el nombre. */
  manualId?: string;
  claimedByDevice?: string;
}

export interface RecomputeResult {
  accountTotals: Record<string, { grandTotal: Cents }>;
  sessionTotals: {
    grandTotal: Cents;
    /**
     * Importe total del ciclo de liquidación: pagos ya confirmados más las
     * obligaciones residuales que siguen siendo necesarias. Es el
     * denominador autoritativo del progreso; nunca se compara contra el gasto.
     */
    settlementRequired: Cents;
    settledConfirmed: Cents;
    settledMarked: Cents;
  };
  balances: Record<string, ParticipantBalance>;
  pendingSettlements: number;
  settlementSync: {
    /**
     * Docs a escribir con ID DETERMINISTA `pending_{from}_{to}`.
     * Clave del diseño: N recomputes concurrentes (uno por línea de un
     * batch) escriben el MISMO doc con el MISMO contenido → imposible
     * duplicar liquidaciones (la causa raíz del bug de pagos duplicados).
     */
    writes: SettlementDraft[];
    /** Ids que coinciden exactamente con el objetivo: NO se tocan
     * (preserva el estado `marked` del invitado). */
    untouched: string[];
    /** Ids no confirmados que ya no corresponden a ningún objetivo
     * (incluye docs legacy con id aleatorio). */
    removals: string[];
  };
  /** Obligaciones originales por ticket, reconstruibles y explicables. */
  economicEntries: EconomicEntryDraft[];
  /**
   * Proyección DERIVADA y autoritativa de quién participa en cada ticket
   * (Sprint 5, ADR-036). No interviene en ningún cálculo económico: existe
   * para que las Rules puedan DEMOSTRAR, con un exists() sobre una ruta
   * determinista, que un participante pertenece de verdad a un ticket. Sin
   * ella esa condición dependería de un array escrito por el cliente.
   */
  ticketParticipants: TicketParticipantProjection[];
  /**
   * Derecho histórico por ticket (A11d). Proyección MONOTÓNICA: se concede
   * cuando un UID participa económicamente en un ticket y NO se retira
   * jamás, ni aunque una corrección A11c posterior le quite el consumo y
   * recompute borre su `economicEntry`. Es lo único que permite que quien
   * deja de ser miembro pueda seguir auditando la deuda que ya tenía.
   */
  ticketEntitlements: TicketEntitlementDraft[];
  /** Espejo de pagos legacy confirmados/pendientes con participantes UID. */
  legacyPayments: LegacyPaymentDraft[];
  /** Escrituras del protocolo de cierre de consumo (A19). */
  pickingWrites: Array<{
    accountId: string;
    ticketId: string;
    /** Sellar la topología vigente. */
    fingerprint?: string;
    /** Devolver a TODOS los activos a `picking.open`. */
    reopen?: boolean;
    /** Congelar la economía del cierre. */
    firmContribution?: TicketContribution;
  }>;
}

export interface TicketEntitlementDraft {
  /** `{ticketId}_{uid}`: la ruta que las Rules reconstruyen sin consultas. */
  id: string;
  ticketId: string;
  /** Un ticket vive bajo su cuenta; sin esto habría que LISTARLAS. */
  accountId: string;
  uid: string;
  /** pid → nombre, SOLO de los participantes de ESE ticket. */
  participantNames: Record<string, string>;
}

export interface EconomicEntryDraft {
  id: string;
  /**
   * UIDs REALES que pueden leer la obligación (Rules + array-contains). Con
   * un participante manual queda un solo lector; nunca contiene actores
   * manuales, que no tienen cuenta con la que leer.
   */
  memberUids: string[];
  /** Actor deudor: UID de cuenta o `manual:{id}` (ADR-033). */
  debtorUid: string;
  /** Actor acreedor: UID de cuenta o `manual:{id}`. */
  creditorUid: string;
  amount: Cents;
  currency: string;
  accountId: string;
  ticketId: string;
  ticketName: string;
  ticketDate?: string;
  spaceId?: string;
}

export interface LegacyPaymentDraft {
  id: string;
  /** UIDs reales que pueden leerlo (ver EconomicEntryDraft.memberUids). */
  memberUids: string[];
  /** Actor pagador: UID de cuenta o `manual:{id}`. */
  payerUid: string;
  /** Actor receptor: UID de cuenta o `manual:{id}`. */
  receiverUid: string;
  amount: Cents;
  currency: string;
  status: 'pending' | 'confirmed';
  settlementId: string;
}

/** Id determinista de una liquidación pendiente. */
export const settlementId = (draft: SettlementDraft): string =>
    `pending_${draft.from}_${draft.to}`;

const orderedUids = (left: string, right: string): [string, string] =>
  left < right ? [left, right] : [right, left];

const encodedPair = (left: string, right: string): string =>
  orderedUids(left, right)
    .map((uid) => Buffer.from(uid, 'utf8').toString('hex'))
    .join('_');

/**
 * Núcleo puro del recompute (testeable sin Firestore).
 *
 * Orden de participantes = campo `order` (índice de inserción que escribe la
 * app) con desempate por id: DEBE coincidir con el orden que usa la app en su
 * cálculo optimista para que ambos redondeos sean idénticos.
 */
export function computeAggregates(s: SessionSnapshot): RecomputeResult {
  const participants = [...s.participants].sort(
    (a, b) =>
      (a.order ?? Number.MAX_SAFE_INTEGER) -
        (b.order ?? Number.MAX_SAFE_INTEGER) || a.id.localeCompare(b.id),
  );
  const activeIds = participants
    .filter((p) => p.active !== false)
    .map((p) => p.id);
  const known = new Set(activeIds);
  const fallbackPayer =
    participants.find((p) => p.isOwner)?.id ?? activeIds[0];
  const currency = s.currency ?? 'EUR';
  // pid → actor económico: UID de cuenta, o `manual:{id}` sin cuenta. Un
  // participante con cuenta nunca se degrada a manual (ADR-033).
  const actorByPid = new Map<string, string>();
  for (const participant of participants) {
    const resolved = participant.userUid ??
      (participant.isOwner ? s.ownerUid : undefined) ??
      (participant.manualId ? manualActor(participant.manualId) : undefined);
    if (resolved) actorByPid.set(participant.id, resolved);
  }

  const manualAliases = s.manualAliases ?? {};
  const accountTotals: RecomputeResult['accountTotals'] = {};
  const contributions: TicketContribution[] = [];
  const economicEntries: EconomicEntryDraft[] = [];
  const ticketParticipants: TicketParticipantProjection[] = [];
  const ticketEntitlements: TicketEntitlementDraft[] = [];
  const pickingWrites: RecomputeResult['pickingWrites'] = [];
  /**
   * Actores con peso económico YA CONTRAÍDO que pueden no estar activos:
   * los de una contribución congelada en uso y los extremos de una
   * liquidación confirmada. El libro tiene que poder nombrarlos (A19).
   */
  const historicPids = new Set<string>();

  for (const account of s.accounts) {
    let accountTotal = 0;
    for (const ticket of account.tickets) {
      accountTotal += ticket.grandTotal;
      const mode = ticket.splitModeOverride ?? s.splitModeDefault;

      // El pagador efectivo se resuelve ANTES de repartir: en "cada uno paga
      // lo suyo", las líneas aún NO reclamadas recaen sobre quien pagó (ver
      // sanitizeLine), nunca se promedian entre todos.
      let paidBy = ticket.paidByParticipantId;
      if (!known.has(paidBy)) {
        logger.warn('Pagador desconocido; se reasigna al owner', {
          ticket: ticket.id,
          paidBy,
        });
        paidBy = fallbackPayer;
      }

      const consumption = splitTicket({
        participantIds: activeIds,
        mode,
        ticket: {
          grandTotal: ticket.grandTotal,
          lines: ticket.lines.map((l) => sanitizeLine(l, known, paidBy)),
        },
        // 'error', JAMÁS 'splitAmongAll'. Repartir lo no seleccionado entre
        // TODOS producía una "media previa" (cada persona pagando 1/N de lo
        // que nadie ha cogido, SUMADO a lo suyo): el bug que este arreglo
        // erradica. sanitizeLine ya reasigna las líneas sin dueño al pagador,
        // así que aquí no debe quedar ninguna sin asignar; si quedara, es un
        // bug y preferimos que salte a que se promedie en silencio.
        unassignedPolicy: 'error',
        // Residual por unidades (P2.1): lo reclamado parcialmente también
        // recae en el pagador, unidad a unidad.
        payerId: paidBy,
      });
      // ── Puerta de firmeza (A19) ──────────────────────────────────────
      // Firme: la economía es la del reparto real. Reabierto: la última que
      // fue firme, congelada. Nunca cerrado: ninguna. Lo pagado (`accountTotal`,
      // arriba) NO depende de esto: es descriptivo, no un balance.
      const firm = ticketIsFirm(ticket, mode, activeIds);
      const economic = firm
        ? { paidBy, grandTotal: ticket.grandTotal, consumption }
        : frozenContribution(ticket);
      if (economic) {
        contributions.push(economic);
        // Actores con peso económico ya contraído: pueden no estar activos
        // hoy y aun así tener que ser NOMBRADOS por el libro.
        if (!firm) {
          historicPids.add(economic.paidBy);
          for (const pid of Object.keys(economic.consumption)) {
            historicPids.add(pid);
          }
        }
      }
      // La economía que se publica: la viva si el ticket es firme, la
      // congelada si está reabierto. Todo lo que sigue —obligaciones P5
      // incluidas— sale de aquí, para que una obligación de un ticket
      // reabierto sea byte a byte la misma que antes de reabrirlo.
      const economicPaidBy = economic?.paidBy ?? paidBy;
      const economicConsumption = economic?.consumption ?? {};

      // ── Sello de topología y congelación (A19) ───────────────────────
      if (ticket.pickingModelVersion === 1) {
        const fingerprint = pickingFingerprint(mode, ticket.lines);
        const stored = ticket.picking?.fingerprint;
        // Al cerrar se congela la economía del cierre: es la que sostendrá
        // los pagos si alguien vuelve a abrir el reparto después.
        const freeze = firm &&
          comparableContribution(economic) !==
            comparableContribution(ticket.picking?.firmContribution);
        if (stored !== fingerprint || freeze) {
          pickingWrites.push({
            accountId: account.id,
            ticketId: ticket.id,
            ...(stored !== fingerprint ? { fingerprint } : {}),
            // La PRIMERA vez solo se sella la huella: el ticket acaba de
            // nacer con su `open` ya sembrado por quien lo creó y no hay
            // nada que reabrir. Después, cualquier cambio de topología
            // devuelve a TODOS los activos a elegir — una unidad nueva no
            // puede convertirse en residual del pagador sin que nadie haya
            // tenido ocasión de reclamarla.
            ...(stored !== undefined && stored !== fingerprint
              ? { reopen: true }
              : {}),
            ...(freeze && economic ? { firmContribution: economic } : {}),
          });
        }
      }

      // Participa quien consume algo o quien paga. Se proyecta la identidad
      // estable (manualId / claimedByDevice), nunca el nombre.
      //
      // OJO: esto sale del consumo VIVO, no del económico. Ni la proyección
      // de participación ni el derecho histórico esperan al cierre:
      //  - el enlace de ticket (ADR-036) existe justamente para preguntarle a
      //    alguien qué consumió: bloquearlo mientras se elige sería al revés;
      //  - el derecho histórico (A11d) es autoridad de LECTURA y es monótono.
      //    El pagador lo necesita desde el primer instante: concedido solo al
      //    cerrar, alguien expulsado del grupo con el reparto aún abierto
      //    perdería el gasto que pagó él.
      const participatingPids = new Set<string>([paidBy]);
      for (const [pid, amount] of Object.entries(consumption)) {
        if (amount > 0) participatingPids.add(pid);
      }
      // Nombres de ESTE ticket, para que el reparto siga siendo legible sin
      // abrir el censo de la sesión (A11d). Se congelan en el derecho
      // histórico: un `pid` sin nombre detrás no explica ninguna deuda.
      //
      // Se indexan por `pid` (el reparto, línea a línea) y ADEMÁS por ACTOR
      // económico cuando el participante es MANUAL: la deuda de P5 nombra a
      // `manual:{id}`, nunca a un `pid`, y el nombre de un manual lo custodia
      // el ESPACIO (ADR-033), que un ex-miembro ya no puede leer. Sin este
      // alias su propio saldo se leía «Persona sin nombre». Una cuenta no lo
      // necesita: su nombre vive en el perfil público, que sí es legible.
      const participantNames: Record<string, string> = {};
      for (const pid of [...participatingPids].sort()) {
        const participant = participants.find((p) => p.id === pid);
        const name = participant?.name;
        if (!participant || !name) continue;
        participantNames[pid] = name;
        if (participant.manualId && !participant.userUid) {
          participantNames[manualActor(participant.manualId)] = name;
        }
      }
      for (const pid of participatingPids) {
        const participant = participants.find((p) => p.id === pid);
        if (!participant) continue;
        ticketParticipants.push({
          ticketId: ticket.id,
          pid,
          ...(participant.manualId ? { manualId: participant.manualId } : {}),
          ...(participant.claimedByDevice
            ? { claimedByDevice: participant.claimedByDevice }
            : {}),
        });
        // Solo identidades REALES: un `manual:{id}` sin vincular no tiene
        // cuenta con la que leer nada. Un manual ya VINCULADO sí, y es la
        // misma persona a la que ADR-037 reconoce como lectora.
        const uid = participant.userUid ??
          (participant.isOwner ? s.ownerUid : undefined) ??
          (participant.manualId
            ? manualAliases[participant.manualId]
            : undefined);
        if (!uid) continue;
        ticketEntitlements.push({
          id: `${ticket.id}_${uid}`,
          ticketId: ticket.id,
          accountId: account.id,
          uid,
          participantNames,
        });
      }

      // P5 conserva la deuda ORIGINAL por ticket entre dos ACTORES. Un actor
      // es una cuenta (su UID) o un participante MANUAL (`manual:{id}`), que
      // económicamente pesa igual aunque no tenga cuenta ni dispositivo. Un
      // nombre suelto sin identidad sigue sin publicarse: no se inventa
      // identidad a partir del nombre (ADR-033).
      const payerActor = actorByPid.get(economicPaidBy);
      if (payerActor) {
        const byDebtor = new Map<string, Cents>();
        const aliases = s.manualAliases ?? {};
        // C2: dos actores DISTINTOS pueden ser la misma persona — su UID y un
        // `manual:{id}` vinculado a ese UID. Sin esto se generaba una
        // obligación de alguien consigo mismo, con un único lector en ambos
        // extremos y una liquidación pidiendo transferirse dinero a sí mismo.
        // Se compara la IDENTIDAD efectiva, no el actor: los actores
        // históricos siguen intactos en los documentos.
        const payerIdentity = resolveActorIdentity(payerActor, aliases);
        for (const [pid, amount] of Object.entries(economicConsumption)) {
          const debtorActor = actorByPid.get(pid);
          if (!debtorActor || debtorActor === payerActor || amount <= 0) {
            continue;
          }
          if (resolveActorIdentity(debtorActor, aliases) === payerIdentity) {
            continue;
          }
          byDebtor.set(debtorActor, (byDebtor.get(debtorActor) ?? 0) + amount);
        }
        for (const [debtorActor, amount] of [...byDebtor.entries()]
          .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)) {
          // Entre dos manuales no hay nadie que pueda leerla: esa deuda vive
          // en el balance de su sesión, no en la economía global.
          const readers = accountUidsOf(
            [debtorActor, payerActor], manualAliases);
          if (readers.length === 0) continue;
          economicEntries.push({
            id: `${account.id}_${ticket.id}_${
              encodedPair(debtorActor, payerActor)}`,
            memberUids: readers,
            debtorUid: debtorActor,
            creditorUid: payerActor,
            amount,
            currency,
            accountId: account.id,
            ticketId: ticket.id,
            ticketName: ticket.merchantName ?? account.name ?? ticket.id,
            ticketDate: ticket.date,
            spaceId: ticket.spaceId,
          });
        }
      }
    }
    accountTotals[account.id] = { grandTotal: accountTotal };
  }

  const frozen: FrozenSettlement[] = s.settlements
    .filter((st) => st.state === 'confirmed')
    .map((st) => ({ from: st.from, to: st.to, amount: st.amount }))
    .concat(s.externalConfirmed ?? []);

  // Una liquidación CONFIRMADA es peso económico contraído: sus dos extremos
  // tienen que existir en el libro aunque uno ya no participe.
  for (const settlement of frozen) {
    historicPids.add(settlement.from);
    historicPids.add(settlement.to);
  }

  // ── El universo del LIBRO no es el del REPARTO (A19) ─────────────────
  //
  // `activeIds` decide quién puede recibir consumo NUEVO: eso no cambia, y
  // es lo que reciben `splitTicket` y `sanitizeLine`. El libro, en cambio,
  // tiene que poder NOMBRAR a cualquiera con peso económico ya contraído,
  // porque si no puede nombrarlo no puede cuadrarlo.
  //
  // Medido: con un único universo, desactivar a alguien que tiene una
  // liquidación confirmada hacía que `computeBalance` lanzara
  // `unknownParticipant` y la sesión ENTERA dejaba de recalcularse.
  //
  // Estar en el libro NO es estar activo: no da permisos, no permite
  // seleccionar, no entra en `picking.open` y no recibe consumo nuevo.
  const ledgerIds = [
    ...activeIds,
    ...[...historicPids].filter((pid) => !known.has(pid)).sort(),
  ];

  const legacyPayments: LegacyPaymentDraft[] = [];
  for (const settlement of s.settlements) {
    // `pending` es una sugerencia de recompute, no un pago humano. Solo
    // `marked` (el deudor dice que pagó) y `confirmed` son movimientos.
    if (settlement.state === 'pending') continue;
    const payerUid = actorByPid.get(settlement.from);
    const receiverUid = actorByPid.get(settlement.to);
    if (!payerUid || !receiverUid || payerUid === receiverUid ||
        settlement.amount <= 0) continue;
    // Un pago que salda a un manual también reduce su deuda global; si nadie
    // puede leerlo (manual↔manual) se queda en el balance de la sesión.
    const readers = accountUidsOf(
      [payerUid, receiverUid], manualAliases);
    if (readers.length === 0) continue;
    legacyPayments.push({
      id: `legacy_${settlement.id}`,
      memberUids: readers,
      payerUid,
      receiverUid,
      amount: settlement.amount,
      currency,
      status: settlement.state === 'confirmed' ? 'confirmed' : 'pending',
      settlementId: settlement.id,
    });
  }

  const balance = computeBalance({
    participantIds: ledgerIds,
    tickets: contributions,
    frozenSettlements: frozen,
  });

  // Sincronización de liquidaciones (idempotente y a prueba de carreras):
  // - Confirmadas: intocables (congeladas, RF-53).
  // - Objetivos con id determinista pending_{from}_{to}: si el doc existe
  //   con el MISMO importe, no se toca (preserva `marked`); si difiere o
  //   no existe, se (sobre)escribe como pending.
  // - Cualquier doc no confirmado que no corresponda a un objetivo se borra
  //   (incluye duplicados legacy con id aleatorio).
  const nonConfirmed = s.settlements.filter((st) => st.state !== 'confirmed');
  const writes: SettlementDraft[] = [];
  const untouched: string[] = [];
  for (const target of balance.settlements) {
    const id = settlementId(target);
    const existing = nonConfirmed.find((st) => st.id === id);
    if (existing && existing.amount === target.amount) {
      untouched.push(id);
    } else {
      writes.push(target);
    }
  }
  const targetIds = new Set(balance.settlements.map(settlementId));
  const removals = nonConfirmed
    .filter((st) => !targetIds.has(st.id))
    .map((st) => st.id);

  let grandTotal = 0;
  for (const t of Object.values(accountTotals)) grandTotal += t.grandTotal;
  let settledConfirmed = 0;
  let settledMarked = 0;
  for (const st of s.settlements) {
    if (st.state === 'confirmed') settledConfirmed += st.amount;
    if (st.state === 'marked' && untouched.includes(st.id)) {
      settledMarked += st.amount;
    }
  }
  settledConfirmed += (s.externalConfirmed ?? [])
    .reduce((sum, settlement) => sum + settlement.amount, 0);
  const settlementRequired =
    settledConfirmed +
    balance.settlements.reduce((total, st) => total + st.amount, 0);

  return {
    accountTotals,
    sessionTotals: {
      grandTotal,
      settlementRequired,
      settledConfirmed,
      settledMarked,
    },
    balances: balance.balances,
    pendingSettlements:
      balance.settlements.length -
      s.settlements.filter(
        (st) => st.state === 'marked' && untouched.includes(st.id),
      ).length,
    settlementSync: { writes, untouched, removals },
    economicEntries,
    ticketParticipants,
    ticketEntitlements,
    legacyPayments,
    pickingWrites,
  };
}

/**
 * Serialización estable de una contribución, para poder comparar la del
 * cierre con la ya congelada sin reescribir el ticket en cada recompute
 * (y sin disparar una cascada de triggers por nada).
 */
function comparableContribution(
  contribution: TicketContribution | FirmContribution | undefined,
): string {
  if (!contribution) return '';
  const consumption = Object.entries(contribution.consumption)
    .filter(([, cents]) => cents !== 0)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return JSON.stringify([
    contribution.paidBy,
    contribution.grandTotal,
    consumption,
  ]);
}

/**
 * Huella de la TOPOLOGÍA de reparto de un ticket (A19).
 *
 * Cambia si y solo si cambia algo que invalida una elección ya hecha: el
 * modo efectivo, el conjunto de líneas o los `unitIds` de alguna. NO cambia
 * con el nombre, el precio ni el total, porque corregir un importe no altera
 * QUÉ consumió nadie.
 *
 * Vive solo en el servidor: ningún cliente la calcula ni la escribe, así que
 * no hay una tercera implementación que mantener en paridad.
 */
export function pickingFingerprint(
  mode: SplitMode,
  lines: readonly LineDoc[],
): string {
  const parts = [...lines]
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((line) => `${line.id}:${[...(line.unitIds ?? [])].join(',')}`);
  return `${mode}|${parts.join(';')}`;
}

/**
 * ¿Entra este ticket en la economía firme? (A19)
 *
 * Un ticket sin `pickingModelVersion` es de antes del protocolo y se comporta
 * como siempre. A partes iguales el reparto no mira las líneas, así que no
 * hay nada que esperar. En «cada uno lo suyo» hace falta que todos los
 * ACTIVOS hayan terminado —a quien ya no participa no se le espera, porque
 * tampoco va a mover un céntimo— y que la topología no haya cambiado desde
 * el cierre: si cambió, este mismo recompute está a punto de reabrirlo.
 */
export function ticketIsFirm(
  ticket: TicketDoc,
  mode: SplitMode,
  activeIds: readonly string[],
): boolean {
  if (ticket.pickingModelVersion !== 1) return true;
  if (mode === 'equal') return true;
  const stored = ticket.picking?.fingerprint;
  if (stored !== undefined &&
      stored !== pickingFingerprint(mode, ticket.lines)) {
    return false;
  }
  return Object.keys(ticket.picking?.open ?? {})
    .every((pid) => !activeIds.includes(pid));
}

/**
 * Aportación económica de un ticket REABIERTO: la última que fue firme.
 *
 * No se retira, se congela. Retirarla dejaría un pago `confirmed` sin la
 * obligación que lo justificaba, y el modelo leería eso como un sobrepago:
 * aparecería una liquidación INVERSA por el importe entero, nueva y
 * cobrable, provocada solo por el hecho de estar editando.
 *
 * Se devuelve TAL CUAL, sin reinterpretarla según quién siga activo hoy.
 * Congelada significa congelada: el `paidBy`, el total y el consumo son los
 * del cierre. Quien figure aquí y ya no esté activo entra igualmente en el
 * universo del LIBRO (ver `ledgerIds`), que es lo que permite que la
 * economía del último cierre siga cuadrando byte a byte.
 *
 * `undefined` = el ticket nunca llegó a ser firme, así que no ha podido
 * generar ningún pago y sale de la economía sin descuadrar nada.
 */
export function frozenContribution(
  ticket: TicketDoc,
): TicketContribution | undefined {
  const frozen = ticket.picking?.firmContribution;
  if (!frozen) return undefined;
  return {
    paidBy: frozen.paidBy,
    grandTotal: frozen.grandTotal,
    consumption: { ...frozen.consumption },
  };
}

/**
 * Normaliza una línea de Firestore al modelo del motor y RESUELVE las líneas
 * sin dueño hacia el pagador:
 *  - `all`: elección explícita del anfitrión → se respeta tal cual.
 *  - con consumidores válidos: `one` (1 y venía como `one`) o `shared`.
 *  - sin consumidores (sin reclamar): la cubre `payerId` como `one`. Esto es
 *    lo que elimina la "media previa": lo que nadie ha cogido es de quien
 *    pagó (neto cero para él en esa parte), y se reduce a medida que la gente
 *    reclama sus productos.
 */
function sanitizeLine(
  line: LineDoc,
  known: ReadonlySet<string>,
  payerId: string,
): SplitLine {
  const rawType = line.assignment?.type ?? 'unassigned';
  const units = unitsFromQuantityMilli(line.quantityMilli ?? 1000);

  // P2.2 es opt-in por línea. La ausencia de schemaVersion conserva el
  // reparto histórico/P2.1 sin reinterpretarlo silenciosamente.
  if (line.assignment?.schemaVersion === 2 && rawType === 'units') {
    const unitConsumers: Record<string, string[]> = {};
    for (let unit = 0; unit < units; unit++) {
      const members = line.assignment?.units?.[`u${unit}`] ?? {};
      const consumers: string[] = [];
      for (const [pid, selected] of Object.entries(members)) {
        if (!selected) continue;
        if (known.has(pid)) consumers.push(pid);
        else {
          logger.warn('Consumidor de unidad desconocido; se ignora', {
            line: line.id,
            unit,
            pid,
          });
        }
      }
      if (consumers.length > 0) unitConsumers[String(unit)] = consumers;
    }
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      unitConsumers,
      // Ignorado por el motor cuando existe unitConsumers.
      assignment: { type: 'unassigned', weights: {} },
    };
  }

  if (rawType === 'all') {
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      assignment: { type: 'all', weights: {} },
    };
  }

  const weights: Record<string, number> = {};
  for (const [pid, weight] of Object.entries(
    line.assignment?.participants ?? {},
  )) {
    if (known.has(pid) && weight > 0) weights[pid] = weight;
    else if (!known.has(pid)) {
      logger.warn('Asignación a participante desconocido; se ignora', {
        line: line.id,
        pid,
      });
    }
  }

  const consumers = Object.keys(weights);
  if (consumers.length === 0) {
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      assignment: { type: 'one', weights: { [payerId]: 1 } },
    };
  }

  const type = consumers.length === 1 && rawType === 'one' ? 'one' : 'shared';
  return {
    id: line.id,
    totalPrice: line.totalPrice,
    units,
    assignment: { type, weights },
  };
}

// ── Lectura de Firestore y escritura de agregados ─────────────────────────

/** ¿Abortó el commit porque otra ejecución escribió antes? (gRPC 9) */
const isStaleWrite = (error: unknown): boolean =>
  (error as { code?: number } | null)?.code === 9;

/** Intentos máximos ante un conflicto de precondición. Acotado a propósito. */
const RECOMPUTE_ATTEMPTS = 3;

export async function recomputeSession(
  sid: string,
  attempt = 0,
): Promise<void> {
  const db = getFirestore();
  const sessionRef = db.doc(`sessions/${sid}`);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) return; // borrada: cleanup se encarga

  const [
    participantsSnap,
    accountsSnap,
    settlementsSnap,
    economicEntriesSnap,
    economicPaymentsSnap,
    externalPaymentsSnap,
    ticketEntitlementsSnap,
  ] = await Promise.all([
    sessionRef.collection('participants').get(),
    sessionRef.collection('accounts').get(),
    sessionRef.collection('settlements').get(),
    db.collection('economicEntries').where('sessionId', '==', sid).get(),
    db.collection('economicPayments').where('sourceSessionId', '==', sid).get(),
    db.collection('economicPayments').where('sessionIds', 'array-contains', sid).get(),
    // A11d: se lee ANTES del atajo `unchanged`. Un derecho histórico que
    // falte tiene que crearse aunque la economía no haya cambiado —si no, la
    // proyección quedaría incompleta justo en los tickets que llevan tiempo
    // quietos, que son precisamente los que alguien va a auditar después.
    sessionRef.collection('ticketEntitlements').get(),
  ]);

  const accounts: AccountDoc[] = await Promise.all(
    accountsSnap.docs.map(async (accountDoc) => {
      const ticketsSnap = await accountDoc.ref.collection('tickets').get();
      const tickets: TicketDoc[] = await Promise.all(
        ticketsSnap.docs.map(async (ticketDoc) => {
          const linesSnap = await ticketDoc.ref.collection('lines').get();
          return {
            id: ticketDoc.id,
            grandTotal: (ticketDoc.data().grandTotal as number) ?? 0,
            paidByParticipantId:
              (ticketDoc.data().paidByParticipantId as string) ?? '',
            splitModeOverride: ticketDoc.data().splitModeOverride as
              | SplitMode
              | undefined,
            merchantName:
              (ticketDoc.data().merchant as { name?: string } | undefined)
                ?.name,
            date: ticketDoc.data().date as string | undefined,
            spaceId: ticketDoc.data().spaceId as string | undefined,
            pickingModelVersion:
              ticketDoc.data().pickingModelVersion as number | undefined,
            picking: ticketDoc.data().picking as TicketDoc['picking'],
            lines: linesSnap.docs.map((l) => ({
              id: l.id,
              totalPrice: (l.data().totalPrice as number) ?? 0,
              quantityMilli: l.data().quantityMilli as number | undefined,
              unitIds: l.data().unitIds as string[] | undefined,
              assignment: l.data().assignment,
            })),
          };
        }),
      );
      return {
        id: accountDoc.id,
        name: accountDoc.data().name as string | undefined,
        tickets,
      };
    }),
  );

  // `claimedByDevice` también identifica invitados anónimos. Solo se eleva
  // a identidad económica si existe un perfil público registrado con ese UID.
  const claimedUids = [
    ...new Set(
      participantsSnap.docs
        .map((p) => p.data().claimedByDevice as string | undefined)
        .filter((value): value is string => Boolean(value)),
    ),
  ];
  // Identidad registrada = perfil público (P2) O identidad de invitado
  // (ADR-034). El invitado no tiene perfil por diseño, pero tiene UID propio
  // y participa económicamente igual que una cuenta.
  const claimedIdentities = claimedUids.length === 0
    ? []
    : await db.getAll(
      ...claimedUids.map((claimedUid) => db.doc(`profiles/${claimedUid}`)),
      ...claimedUids.map((claimedUid) =>
        db.doc(`guestIdentities/${claimedUid}`)),
    );
  const registeredClaims = new Set(
    claimedIdentities.filter((doc) => doc.exists).map((doc) => doc.id),
  );
  const sessionOwnerUid = sessionSnap.data()?.ownerUid as string | undefined;
  const pidByUid = new Map<string, string>();
  for (const participant of participantsSnap.docs) {
    const data = participant.data();
    const uid = resolveParticipantUid({
      isOwner: data.isOwner as boolean | undefined,
      claimedByDevice: data.claimedByDevice as string | undefined,
      sessionOwnerUid,
      registeredUids: registeredClaims,
    });
    if (uid) pidByUid.set(uid, participant.id);
  }
  const currentEntryIds = new Set(economicEntriesSnap.docs.map((doc) => doc.id));
  // VINCULACIÓN (ADR-037): alias `manualId → uid` de los manuales que el
  // anfitrión ya APROBÓ. Vive en el espacio, que es donde vive la identidad
  // manual. Un alias NO cambia el actor: solo añade lectores.
  const manualAliases: Record<string, string> = {};
  const spaceId = sessionSnap.data()?.spaceId as string | undefined;
  if (spaceId) {
    const manuals = await db
      .collection(`spaces/${spaceId}/manualParticipants`)
      .get();
    for (const manual of manuals.docs) {
      const linked = manual.data().linkedUid as string | undefined;
      if (linked) manualAliases[manual.id] = linked;
    }
  }

  const externalConfirmed: Array<{ from: string; to: string; amount: Cents }> = [];
  for (const payment of externalPaymentsSnap.docs) {
    const data = payment.data();
    if (data.source !== 'user' || data.status !== 'confirmed') continue;
    const from = pidByUid.get(data.payerUid as string);
    const to = pidByUid.get(data.receiverUid as string);
    if (!from || !to || from === to) continue;
    const allocations = data.allocations as Record<string, number> | undefined;
    const amount = Object.entries(allocations ?? {})
      .filter(([entryId]) => currentEntryIds.has(entryId))
      .reduce((sum, [, cents]) => sum + cents, 0);
    if (amount > 0) externalConfirmed.push({ from, to, amount });
  }

  const snapshot: SessionSnapshot = {
    splitModeDefault:
      (sessionSnap.data()?.splitModeDefault as SplitMode) ?? 'equal',
    ownerUid: sessionOwnerUid,
    currency: (sessionSnap.data()?.currency as string | undefined) ?? 'EUR',
    participants: participantsSnap.docs.map((p) => {
      const isOwner = p.data().isOwner as boolean | undefined;
      const claimed = p.data().claimedByDevice as string | undefined;
      return {
        id: p.id,
        name: p.data().name as string | undefined,
        isOwner,
        active: p.data().active as boolean | undefined,
        order: p.data().order as number | undefined,
        userUid: resolveParticipantUid({
          isOwner,
          claimedByDevice: claimed,
          sessionOwnerUid,
          registeredUids: registeredClaims,
        }),
        manualId: p.data().manualId as string | undefined,
        claimedByDevice: claimed,
      };
    }),
    accounts,
    settlements: settlementsSnap.docs.map((st) => ({
      id: st.id,
      from: st.data().from as string,
      to: st.data().to as string,
      amount: st.data().amount as number,
      state: st.data().state as SettlementDoc['state'],
    })),
    externalConfirmed,
    manualAliases,
  };

  if (snapshot.participants.length === 0) return; // sesión a medio crear

  const result = computeAggregates(snapshot);

  const entryData = (entry: EconomicEntryDraft): Record<string, unknown> => ({
    memberUids: entry.memberUids,
    debtorUid: entry.debtorUid,
    creditorUid: entry.creditorUid,
    amount: entry.amount,
    currency: entry.currency,
    sessionId: sid,
    accountId: entry.accountId,
    ticketId: entry.ticketId,
    ticketName: entry.ticketName,
    ...(entry.ticketDate ? { ticketDate: entry.ticketDate } : {}),
    ...(entry.spaceId ? { spaceId: entry.spaceId } : {}),
    // Propiedad DERIVADA e inmutable de la obligación: si una de sus partes
    // no tiene cuenta, alguien tiene que poder representarla (ADR-038). Se
    // persiste porque una query no puede filtrar por el prefijo del actor, y
    // sin ella la consulta del administrador arrastraría obligaciones entre
    // dos cuentas que no le corresponde leer.
    hasManualParty: isManualActor(entry.debtorUid) ||
      isManualActor(entry.creditorUid),
    schemaVersion: 1,
  });
  const legacyPaymentData = (
    payment: LegacyPaymentDraft,
  ): Record<string, unknown> => ({
    memberUids: payment.memberUids,
    pairId: encodedPair(payment.payerUid, payment.receiverUid),
    payerUid: payment.payerUid,
    receiverUid: payment.receiverUid,
    amount: payment.amount,
    currency: payment.currency,
    status: payment.status,
    source: 'legacySettlement',
    sourceSessionId: sid,
    settlementId: payment.settlementId,
    schemaVersion: 1,
  });
  const desiredEntries = new Map(
    result.economicEntries.map((entry) => [
      `${sid}_${entry.id}`,
      entryData(entry),
    ]),
  );
  const desiredLegacyPayments = new Map(
    result.legacyPayments.map((payment) => [
      `${sid}_${payment.id}`,
      legacyPaymentData(payment),
    ]),
  );
  const comparable = (data: Record<string, unknown>): string => {
    const copy = { ...data };
    delete copy.createdAt;
    delete copy.updatedAt;
    delete copy.confirmedAt;
    return JSON.stringify(copy);
  };
  const economicEntriesUnchanged =
    economicEntriesSnap.size === desiredEntries.size &&
    economicEntriesSnap.docs.every((doc) => {
      const desired = desiredEntries.get(doc.id);
      return desired !== undefined &&
        comparable(doc.data()) === comparable(desired);
    });
  const legacyDocs = economicPaymentsSnap.docs.filter(
    (doc) => doc.data().source === 'legacySettlement',
  );
  const legacyPaymentsUnchanged =
    legacyDocs.length === desiredLegacyPayments.size &&
    legacyDocs.every((doc) => {
      const desired = desiredLegacyPayments.get(doc.id);
      return desired !== undefined &&
        comparable(doc.data()) === comparable(desired);
    });

  // Derecho histórico (A11d). Solo CRECE: una entrada concedida no se retira
  // nunca, y los nombres se FUNDEN con los ya guardados en vez de sustituirse
  // —quien dejó de consumir por una corrección posterior sigue teniendo que
  // aparecer con su nombre en el reparto que se está auditando—.
  const existingEntitlements = new Map(
    ticketEntitlementsSnap.docs.map((doc) => [doc.id, doc.data()]),
  );
  const entitlementWrites = new Map<string, Record<string, unknown>>();
  for (const entitlement of result.ticketEntitlements) {
    const existing = existingEntitlements.get(entitlement.id);
    const names = {
      ...((existing?.participantNames as Record<string, string> | undefined) ??
        {}),
      ...entitlement.participantNames,
    };
    const desired = {
      uid: entitlement.uid,
      ticketId: entitlement.ticketId,
      accountId: entitlement.accountId,
      participantNames: names,
      schemaVersion: 1,
    };
    const stored = existing === undefined ? undefined : {
      uid: existing.uid,
      ticketId: existing.ticketId,
      accountId: existing.accountId,
      participantNames: existing.participantNames,
      schemaVersion: existing.schemaVersion,
    };
    if (stored && JSON.stringify(stored) === JSON.stringify(desired)) continue;
    entitlementWrites.set(entitlement.id, {
      ...desired,
      grantedAt: existing?.grantedAt ?? FieldValue.serverTimestamp(),
    });
  }

  // ¿Cambió algo? Comparación con lo persistido para evitar escrituras
  // (y notificaciones/lecturas de listeners) innecesarias.
  const current = sessionSnap.data() ?? {};
  const unchanged =
    result.pickingWrites.length === 0 &&
    entitlementWrites.size === 0 &&
    JSON.stringify(current.totals) === JSON.stringify(result.sessionTotals) &&
    JSON.stringify(current.balances) === JSON.stringify(result.balances) &&
    current.pendingSettlements === result.pendingSettlements &&
    result.settlementSync.writes.length === 0 &&
    result.settlementSync.removals.length === 0 &&
    economicEntriesUnchanged &&
    legacyPaymentsUnchanged &&
    accountsSnap.docs.every(
      (a) =>
        JSON.stringify(a.data().totals) ===
        JSON.stringify(result.accountTotals[a.id]),
    );
  if (unchanged) return;

  const batch = db.batch();
  for (const accountDoc of accountsSnap.docs) {
    batch.update(accountDoc.ref, {
      totals: result.accountTotals[accountDoc.id],
    });
  }
  // Serialización de resultados (A19). El batch ENTERO aborta si alguien
  // escribió la sesión después de nuestra lectura, así que una ejecución que
  // llegó tarde con datos viejos no puede sobrescribir la economía que otra
  // acaba de publicar — el caso crítico es «A leyó el ticket abierto, B lo
  // leyó cerrado y publicó, A commitea después y lo borra».
  batch.update(
    sessionRef,
    {
      totals: result.sessionTotals,
      balances: result.balances,
      pendingSettlements: result.pendingSettlements,
      participantsCount: snapshot.participants.length,
      computeVersion: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { lastUpdateTime: sessionSnap.updateTime },
  );
  for (const id of result.settlementSync.removals) {
    batch.delete(sessionRef.collection('settlements').doc(id));
  }
  for (const draft of result.settlementSync.writes) {
    // set() con id determinista: idempotente entre ejecuciones concurrentes.
    batch.set(sessionRef.collection('settlements').doc(settlementId(draft)), {
      from: draft.from,
      to: draft.to,
      amount: draft.amount,
      state: 'pending',
      stateHistory: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const doc of economicEntriesSnap.docs) {
    if (!desiredEntries.has(doc.id)) batch.delete(doc.ref);
  }
  for (const [id, data] of desiredEntries) {
    const existing = economicEntriesSnap.docs.find((doc) => doc.id === id);
    if (existing && comparable(existing.data()) === comparable(data)) continue;
    batch.set(db.collection('economicEntries').doc(id), {
      ...data,
      createdAt: existing?.data().createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const doc of legacyDocs) {
    if (!desiredLegacyPayments.has(doc.id)) batch.delete(doc.ref);
  }
  for (const [id, data] of desiredLegacyPayments) {
    const existing = legacyDocs.find((doc) => doc.id === id);
    if (existing && comparable(existing.data()) === comparable(data)) continue;
    batch.set(db.collection('economicPayments').doc(id), {
      ...data,
      createdAt: existing?.data().createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(data.status === 'confirmed'
        ? { confirmedAt: FieldValue.serverTimestamp() }
        : {}),
    });
  }
  // Derecho histórico por ticket (A11d). NO hay bucle de borrado y eso es
  // deliberado: `ticketParticipants` (más abajo) es la foto del reparto vivo
  // y se retira, esta es la prueba de que alguien participó ALGUNA VEZ. Si
  // se retirase, una corrección A11c posterior dejaría a un ex-miembro sin
  // el ticket que explica la deuda que ya pagó.
  for (const [id, data] of entitlementWrites) {
    batch.set(sessionRef.collection('ticketEntitlements').doc(id), data);
  }

  // Proyección de participación por ticket (ADR-036). Derivada, idempotente
  // y escrita SOLO por Admin: es la fuente que las Rules consultan para
  // demostrar que un participante pertenece de verdad a un ticket. No
  // interviene en ningún cálculo económico.
  const ticketParticipantsRef = sessionRef.collection('ticketParticipants');
  const existingProjection = await ticketParticipantsRef.get();
  const desiredProjection = new Map(
    result.ticketParticipants.map((entry) => [
      `${entry.ticketId}_${entry.pid}`,
      {
        ticketId: entry.ticketId,
        pid: entry.pid,
        ...(entry.manualId ? { manualId: entry.manualId } : {}),
        ...(entry.claimedByDevice
          ? { claimedByDevice: entry.claimedByDevice }
          : {}),
        schemaVersion: 1,
      } as Record<string, unknown>,
    ]),
  );
  for (const doc of existingProjection.docs) {
    if (!desiredProjection.has(doc.id)) batch.delete(doc.ref);
  }
  for (const [id, data] of desiredProjection) {
    const existing = existingProjection.docs.find((doc) => doc.id === id);
    // "Escribe solo si cambia": sin esto, cada recompute tocaría todos los
    // documentos y dispararía cascadas inútiles.
    if (existing && comparable(existing.data()) === comparable(data)) continue;
    batch.set(ticketParticipantsRef.doc(id), data);
  }

  // Señal de PROYECCIÓN PREPARADA (ADR-036). Va en el MISMO batch que las
  // entradas y sus borrados, así que Firestore garantiza que nunca se marca
  // como lista una proyección a medias: o entra todo o no entra nada. Sin
  // esta señal no se podría distinguir «el ticket todavía se está
  // procesando» de «esta persona no participa», y esa ambigüedad es lo que
  // obligaría a un fallback inseguro al crear el enlace.
  const projectionsRef = sessionRef.collection('ticketParticipantProjections');
  const existingMarkers = await projectionsRef.get();
  const pidsByTicket = new Map<string, string[]>();
  for (const entry of result.ticketParticipants) {
    pidsByTicket.set(entry.ticketId, [
      ...(pidsByTicket.get(entry.ticketId) ?? []),
      entry.pid,
    ]);
  }
  const desiredMarkers = new Map(
    [...pidsByTicket.entries()].map(([ticketId, pids]) => [
      ticketId,
      {
        ticketId,
        ready: true,
        // Huella determinista del reparto vigente: cambia en cuanto entra o
        // sale alguien, así que sirve para detectar proyecciones antiguas.
        fingerprint: [...pids].sort().join(','),
        schemaVersion: 1,
      } as Record<string, unknown>,
    ]),
  );
  // Un ticket borrado (o sin participación) pierde su señal: el enlace deja
  // de poder crearse y el acceso antiguo deja de sostenerse.
  for (const doc of existingMarkers.docs) {
    if (!desiredMarkers.has(doc.id)) batch.delete(doc.ref);
  }
  for (const [id, data] of desiredMarkers) {
    const existing = existingMarkers.docs.find((doc) => doc.id === id);
    if (existing && comparable(existing.data()) === comparable(data)) continue;
    batch.set(projectionsRef.doc(id), {
      ...data,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // ── Protocolo de cierre de consumo (A19) ─────────────────────────────
  // Rutas punteadas, nunca el mapa entero: si alguien está pulsando «he
  // terminado» a la vez, las escrituras se funden en vez de pisarse.
  for (const write of result.pickingWrites) {
    const ticketRef = sessionRef
      .collection('accounts').doc(write.accountId)
      .collection('tickets').doc(write.ticketId);
    batch.update(ticketRef, {
      ...(write.fingerprint !== undefined
        ? { 'picking.fingerprint': write.fingerprint }
        : {}),
      ...(write.reopen
        ? Object.fromEntries(
            snapshot.participants
              .filter((p) => p.active !== false)
              .map((p) => [`picking.open.${p.id}`, true]),
          )
        : {}),
      // La economía del cierre se congela ENTERA y de una pieza: por campos
      // sueltos, una escritura a medias dejaría un consumo que no suma el
      // total y `BalanceEngine` lanzaría `consumptionMismatch`.
      ...(write.firmContribution !== undefined
        ? { 'picking.firmContribution': write.firmContribution }
        : {}),
    });
  }

  try {
    await batch.commit();
  } catch (error) {
    // Los triggers de Firestore NO llevan `retry`, así que un commit
    // abortado se perdería sin más y el estado quedaría obsoleto para
    // siempre. El reintento tiene que ser nuestro, y acotado: se relee todo
    // desde cero, nunca es un bucle.
    if (isStaleWrite(error) && attempt + 1 < RECOMPUTE_ATTEMPTS) {
      logger.info('Recompute obsoleto; se repite con datos frescos', {
        sid,
        attempt,
      });
      return recomputeSession(sid, attempt + 1);
    }
    throw error;
  }
  logger.info('Sesión recalculada', {
    sid,
    grandTotal: result.sessionTotals.grandTotal,
    settlements: result.settlementSync,
  });
}

// ── Triggers (una "función" conceptual, tres bindings) ────────────────────

export const recomputeOnLine = onDocumentWritten(
  'sessions/{sid}/accounts/{aid}/tickets/{tid}/lines/{lid}',
  (event) => recomputeSession(event.params.sid),
);

export const recomputeOnTicket = onDocumentWritten(
  'sessions/{sid}/accounts/{aid}/tickets/{tid}',
  (event) => recomputeSession(event.params.sid),
);

export const recomputeOnParticipant = onDocumentWritten(
  'sessions/{sid}/participants/{pid}',
  (event) => recomputeSession(event.params.sid),
);

// Los cambios de estado de pago también actualizan agregados
// (settledConfirmed/Marked, pendientes) y regeneran lo que proceda.
// No hay bucle: recompute solo escribe cuando algo cambia, así que la
// ejecución disparada por sus propias escrituras converge y se detiene.
export const recomputeOnSettlement = onDocumentWritten(
  'sessions/{sid}/settlements/{stid}',
  (event) => recomputeSession(event.params.sid),
);

// Un pago P5 confirmado también debe congelarse en los balances legacy de
// sus sesiones. Así ambas vistas se derivan del mismo evento y no permiten
// volver a pagar desde el detalle antiguo de la cuenta.
export const recomputeOnEconomicPayment = onDocumentWritten(
  'economicPayments/{paymentId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status === after?.status) return;
    if (before?.status !== 'confirmed' && after?.status !== 'confirmed') return;
    const sessionIds = new Set<string>([
      ...((before?.sessionIds as string[] | undefined) ?? []),
      ...((after?.sessionIds as string[] | undefined) ?? []),
    ]);
    await Promise.all([...sessionIds].map(recomputeSession));
  },
);

/** Migración perezosa y reconstruible para sesiones creadas antes de P5. */
export const rebuildMyEconomicRelations = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
  if (
    auth.token.email_verified !== true ||
    auth.token.firebase?.sign_in_provider === 'anonymous'
  ) {
    throw new HttpsError('permission-denied', 'VERIFIED_ACCOUNT_REQUIRED');
  }
  const uid = auth.uid;
  const db = getFirestore();
  const markerRef = db.doc(`users/${uid}`);
  const marker = await markerRef.get();
  if (marker.data()?.economicProjectionVersion === 1) {
    return { rebuilt: 0, version: 1 };
  }

  const [owned, claimed] = await Promise.all([
    db.collection('sessions').where('ownerUid', '==', uid).limit(201).get(),
    db.collectionGroup('participants')
      .where('claimedByDevice', '==', uid).limit(201).get(),
  ]);
  if (owned.size > 200 || claimed.size > 200) {
    throw new HttpsError('resource-exhausted', 'ECONOMIC_REBUILD_TOO_LARGE');
  }
  const sessionIds = new Set(owned.docs.map((doc) => doc.id));
  for (const participant of claimed.docs) {
    const session = participant.ref.parent.parent;
    if (session) sessionIds.add(session.id);
  }
  // Secuencial: evita picos de lecturas/CPU y respeta el techo de coste.
  for (const sid of [...sessionIds].sort()) await recomputeSession(sid);
  await markerRef.set({
    economicProjectionVersion: 1,
    economicProjectionUpdatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { rebuilt: sessionIds.size, version: 1 };
});
