/**
 * Construcción del assignment al (des)marcarse un producto.
 *
 * Debe satisfacer EXACTAMENTE las reglas de Firestore (spec §13.2):
 * solo cambia la entrada del propio pid (peso 1), `lastEditorPid` declara
 * quién edita, y el tipo nunca puede ser "all" desde un invitado.
 */
export interface Assignment {
  type: 'unassigned' | 'one' | 'shared' | 'all';
  participants: Record<string, number>;
  lastEditorPid?: string;
}

export function toggleSelf(current: Assignment | undefined, pid: string): Assignment {
  const participants = { ...(current?.participants ?? {}) };
  if (participants[pid]) {
    delete participants[pid];
  } else {
    participants[pid] = 1;
  }
  const count = Object.keys(participants).length;
  return {
    type: count === 0 ? 'unassigned' : count === 1 ? 'one' : 'shared',
    participants,
    lastEditorPid: pid,
  };
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
