/**
 * Construcción del assignment al (des)marcarse un producto.
 *
 * Debe satisfacer EXACTAMENTE las reglas de Firestore (spec §13.2):
 * solo cambia la entrada del propio pid (peso 1), `lastEditorPid` declara
 * quién edita, y el tipo nunca puede ser "all" desde un invitado.
 */
export interface Assignment {
  type: 'unassigned' | 'one' | 'shared' | 'all' | 'units';
  participants?: Record<string, number>;
  schemaVersion?: number;
  units?: Record<string, Record<string, boolean | number>>;
  lastEditorPid?: string;
  lastEditedUnit?: string;
}

export function usesUnitModel(current: Assignment | undefined): boolean {
  return current?.schemaVersion === 2 && current?.type === 'units';
}

export function unitConsumers(
  current: Assignment | undefined,
  unit: number,
): string[] {
  const members = current?.units?.[`u${unit}`] ?? {};
  return Object.entries(members)
    .filter(([, selected]) => Boolean(selected))
    .map(([pid]) => pid);
}

export function unitIsPickedBy(
  current: Assignment | undefined,
  unit: number,
  pid: string,
): boolean {
  return unitConsumers(current, unit).includes(pid);
}

/**
 * Unidades reclamables de una línea (P2.1). Espejo exacto de
 * SplitLine.unitsFromQuantityMilli (Dart/TS): solo cantidades enteras >= 2
 * son unidades; los pesos (0,466 kg) siguen siendo una.
 */
export function unitsForQuantity(quantityMilli: number): number {
  return quantityMilli >= 2000 && quantityMilli % 1000 === 0
    ? quantityMilli / 1000
    : 1;
}

/**
 * Fija MIS unidades reclamadas (0 = quitarme). Las reglas validan que el
 * peso sea entero y no supere las unidades de la línea.
 */
export function setUnits(
  current: Assignment | undefined,
  pid: string,
  units: number,
): Assignment {
  const participants = { ...(current?.participants ?? {}) };
  if (units <= 0) {
    delete participants[pid];
  } else {
    participants[pid] = units;
  }
  const count = Object.keys(participants).length;
  return {
    type: count === 0 ? 'unassigned' : count === 1 ? 'one' : 'shared',
    participants,
    lastEditorPid: pid,
  };
}

export function toggleSelf(current: Assignment | undefined, pid: string): Assignment {
  return setUnits(current, pid, current?.participants?.[pid] ? 0 : 1);
}

/** Mis unidades reclamadas en la línea (0 si ninguna). */
export function myUnits(current: Assignment | undefined, pid: string): number {
  return current?.participants?.[pid] ?? 0;
}

export function isPickedBy(current: Assignment | undefined, pid: string): boolean {
  return Boolean(current?.participants?.[pid]);
}

/** Consumidores de la línea distintos de `pid`. */
export function otherConsumers(
  current: Assignment | undefined,
  pid: string,
): string[] {
  return Object.keys(current?.participants ?? {}).filter((p) => p !== pid);
}

/**
 * ¿Hay que pedir confirmación antes de sumarme a esta línea?
 * Sí cuando ya la seleccionó OTRA persona y yo todavía no estoy en ella:
 * entonces mostramos "X ya lo ha seleccionado, ¿compartir?" en vez de crear
 * una línea duplicada (el producto sigue siendo UNO con varios consumidores).
 * Quitarme de una línea que ya es mía nunca pregunta.
 */
export function needsShareConfirmation(
  current: Assignment | undefined,
  pid: string,
): boolean {
  if (isPickedBy(current, pid)) return false;
  return otherConsumers(current, pid).length > 0;
}
