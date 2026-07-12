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
