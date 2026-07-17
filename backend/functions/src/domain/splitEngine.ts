/**
 * Motor de reparto por ticket — espejo exacto de
 * packages/domain/lib/src/engines/split_engine.dart.
 */
import { DomainError } from './errors.js';
import { allocateProportionally, type Cents } from './money.js';

export type SplitMode = 'equal' | 'byItem';
export type UnassignedLinePolicy = 'error' | 'splitAmongAll';
export type AssignmentType = 'unassigned' | 'one' | 'shared' | 'all';

export interface LineAssignment {
  readonly type: AssignmentType;
  /** participantId → peso (solo `one` y `shared`). */
  readonly weights?: Readonly<Record<string, number>>;
}

export interface SplitLine {
  readonly id: string;
  readonly totalPrice: Cents;
  readonly assignment: LineAssignment;
  /**
   * Unidades de la línea (P2.1): "2 × flauta" son 2 y un peso de 1 reclama
   * UNA. Por defecto 1 = comportamiento histórico (la línea entera).
   */
  readonly units?: number;
  /**
   * P2.2: índice de unidad → consumidores. Ausente conserva la semántica
   * histórica/P2.1; presente activa el reparto físico unidad a unidad.
   */
  readonly unitConsumers?: Readonly<Record<string, readonly string[]>>;
}

/** Unidades "reclamables" a partir de una cantidad ×1000 (espejo Dart). */
export function unitsFromQuantityMilli(quantityMilli: number): number {
  return quantityMilli >= 2000 && quantityMilli % 1000 === 0
    ? quantityMilli / 1000
    : 1;
}

export interface SplitTicketInput {
  /** Total final del ticket (tras impuestos, descuentos y propina). */
  readonly grandTotal: Cents;
  readonly lines: readonly SplitLine[];
}

/**
 * `payerId` activa la regla de residual por unidades (P2.1): si la suma de
 * pesos reclamados de una línea no llega a sus `units`, las unidades sin
 * reclamar recaen en el pagador (extensión de ADR-021). Con suma >= units el
 * reparto es proporcional puro (compartir de siempre, intacto).
 */
export function splitTicket(params: {
  participantIds: readonly string[];
  mode: SplitMode;
  ticket: SplitTicketInput;
  unassignedPolicy?: UnassignedLinePolicy;
  payerId?: string;
}): Record<string, Cents> {
  const { participantIds, mode, ticket, payerId } = params;
  const unassignedPolicy = params.unassignedPolicy ?? 'error';

  if (participantIds.length === 0) {
    throw new DomainError(
      'emptyParticipants',
      'Un ticket necesita al menos un participante',
    );
  }

  const weights =
    mode === 'equal'
      ? Array<number>(participantIds.length).fill(1)
      : lineWeights(participantIds, ticket.lines, unassignedPolicy, payerId);

  // byItem sin consumo en líneas (ticket manual sin desglose): a medias.
  const effectiveWeights = weights.every((w) => w === 0)
    ? Array<number>(participantIds.length).fill(1)
    : weights;

  const shares =
    ticket.grandTotal === 0
      ? Array<Cents>(participantIds.length).fill(0)
      : allocateProportionally(ticket.grandTotal, effectiveWeights);

  return Object.fromEntries(participantIds.map((pid, i) => [pid, shares[i]]));
}

function lineWeights(
  participantIds: readonly string[],
  lines: readonly SplitLine[],
  unassignedPolicy: UnassignedLinePolicy,
  payerId?: string,
): number[] {
  const index = new Map(participantIds.map((pid, i) => [pid, i]));
  const totals = Array<number>(participantIds.length).fill(0);

  for (const line of lines) {
    if (line.unitConsumers !== undefined) {
      addUnitShares({
        line,
        participantIds,
        index,
        totals,
        unassignedPolicy,
        payerId,
      });
      continue;
    }

    let type = line.assignment.type;
    if (type === 'unassigned') {
      if (unassignedPolicy === 'error') {
        throw new DomainError(
          'unassignedLine',
          `La línea ${line.id} no está asignada a nadie`,
        );
      }
      type = 'all';
    }

    const weights =
      type === 'all'
        ? Array<number>(participantIds.length).fill(1)
        : explicitWeights(line, index, participantIds.length);

    // Residual por unidades: reclamar 1 de las 2 flautas deja la otra al
    // pagador. Solo en reclamaciones explícitas: `all` ya cubre el total.
    if (payerId !== undefined && (type === 'one' || type === 'shared')) {
      const payerIndex = index.get(payerId);
      const units = line.units ?? 1;
      const claimed = weights.reduce((a, w) => a + w, 0);
      if (payerIndex !== undefined && claimed < units) {
        weights[payerIndex] += units - claimed;
      }
    }

    const shares = allocateProportionally(line.totalPrice, weights);
    for (let i = 0; i < shares.length; i++) {
      totals[i] += shares[i];
    }
  }
  return totals;
}

function addUnitShares(params: {
  line: SplitLine;
  participantIds: readonly string[];
  index: ReadonlyMap<string, number>;
  totals: number[];
  unassignedPolicy: UnassignedLinePolicy;
  payerId?: string;
}): void {
  const { line, participantIds, index, totals, unassignedPolicy, payerId } =
    params;
  const units = line.units ?? 1;
  if (!Number.isInteger(units) || units <= 0) {
    throw new DomainError(
      'invalidWeights',
      `Número de unidades inválido en la línea ${line.id}`,
    );
  }
  const unitAmounts = allocateProportionally(
    line.totalPrice,
    Array<number>(units).fill(1),
  );
  for (let unit = 0; unit < units; unit++) {
    const requested = line.unitConsumers?.[String(unit)] ?? [];
    const consumers: string[] = [];
    for (const pid of requested) {
      if (!index.has(pid)) {
        throw new DomainError(
          'unknownParticipant',
          `Participante desconocido "${pid}" en la unidad ${unit} de la línea ${line.id}`,
        );
      }
      if (!consumers.includes(pid)) consumers.push(pid);
    }
    if (consumers.length === 0) {
      if (payerId !== undefined && index.has(payerId)) {
        consumers.push(payerId);
      } else if (unassignedPolicy === 'splitAmongAll') {
        consumers.push(...participantIds);
      } else {
        throw new DomainError(
          'unassignedLine',
          `La unidad ${unit} de la línea ${line.id} no está asignada`,
        );
      }
    }
    const weights = participantIds.map((pid) =>
      consumers.includes(pid) ? 1 : 0,
    );
    const shares = allocateProportionally(unitAmounts[unit], weights);
    for (let i = 0; i < shares.length; i++) totals[i] += shares[i];
  }
}

function explicitWeights(
  line: SplitLine,
  index: ReadonlyMap<string, number>,
  count: number,
): number[] {
  const entries = Object.entries(line.assignment.weights ?? {});
  if (entries.length === 0 || entries.some(([, w]) => w <= 0)) {
    throw new DomainError(
      'invalidWeights',
      `Pesos inválidos en la línea ${line.id}`,
    );
  }
  if (line.assignment.type === 'one' && entries.length !== 1) {
    throw new DomainError(
      'invalidWeights',
      `Asignación "one" con ${entries.length} participantes en la línea ${line.id}`,
    );
  }
  const weights = Array<number>(count).fill(0);
  for (const [pid, weight] of entries) {
    const i = index.get(pid);
    if (i === undefined) {
      throw new DomainError(
        'unknownParticipant',
        `Participante desconocido "${pid}" en la línea ${line.id}`,
      );
    }
    weights[i] = weight;
  }
  return weights;
}
