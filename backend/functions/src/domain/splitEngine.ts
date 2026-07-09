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
}

export interface SplitTicketInput {
  /** Total final del ticket (tras impuestos, descuentos y propina). */
  readonly grandTotal: Cents;
  readonly lines: readonly SplitLine[];
}

export function splitTicket(params: {
  participantIds: readonly string[];
  mode: SplitMode;
  ticket: SplitTicketInput;
  unassignedPolicy?: UnassignedLinePolicy;
}): Record<string, Cents> {
  const { participantIds, mode, ticket } = params;
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
      : lineWeights(participantIds, ticket.lines, unassignedPolicy);

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
): number[] {
  const index = new Map(participantIds.map((pid, i) => [pid, i]));
  const totals = Array<number>(participantIds.length).fill(0);

  for (const line of lines) {
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

    const shares = allocateProportionally(line.totalPrice, weights);
    for (let i = 0; i < shares.length; i++) {
      totals[i] += shares[i];
    }
  }
  return totals;
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
