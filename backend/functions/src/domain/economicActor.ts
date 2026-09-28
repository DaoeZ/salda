/**
 * Identidad económica canónica — espejo exacto de
 * packages/domain/lib/src/identity/economic_actor.dart (ADR-033).
 *
 * Actor = UID de cuenta, o `manual:{manualId}` para un participante sin
 * cuenta. Los UID de Firebase nunca contienen ':', así que los documentos
 * económicos anteriores siguen siendo válidos sin migración.
 */
export const manualActorPrefix = 'manual:';

export function manualActor(manualId: string): string {
  if (!manualId || manualId.includes(':')) {
    throw new Error(`Identificador manual inválido: ${manualId}`);
  }
  return `${manualActorPrefix}${manualId}`;
}

export const isManualActor = (actor: string): boolean =>
  actor.startsWith(manualActorPrefix);

export const isAccountActor = (actor: string): boolean =>
  actor.length > 0 && !isManualActor(actor);

export const manualIdOf = (actor: string): string | undefined =>
  isManualActor(actor) ? actor.slice(manualActorPrefix.length) : undefined;

/**
 * UIDs reales de una pareja de actores: la audiencia que puede leerla.
 *
 * VINCULACIÓN (ADR-037). `aliases` mapea `manualId → uid` de los
 * participantes manuales ya vinculados. Un actor manual vinculado NO se
 * sustituye —el actor es y seguirá siendo `manual:{id}`, que es la clave con
 * la que están escritas todas las obligaciones—, pero su persona pasa a ser
 * LECTORA de lo suyo. Esa es toda la vinculación: se AÑADE identidad, no se
 * reescribe historia.
 */
export const accountUidsOf = (
  actors: readonly string[],
  aliases: Readonly<Record<string, string>> = {},
): string[] => {
  const uids = new Set<string>();
  for (const actor of actors) {
    if (isAccountActor(actor)) {
      uids.add(actor);
      continue;
    }
    const manualId = manualIdOf(actor);
    const linked = manualId ? aliases[manualId] : undefined;
    if (linked) uids.add(linked);
  }
  return [...uids].sort();
};

/**
 * Resuelve un actor a la identidad con la que se PRESENTA hoy.
 *
 * Se usa solo para consolidar saldos al leer: dos actores distintos que son
 * la misma persona (su UID y su `manual:{id}` vinculado) no deben aparecer
 * como dos deudas partidas. Los documentos no se tocan.
 */
export const resolveActorIdentity = (
  actor: string,
  aliases: Readonly<Record<string, string>> = {},
): string => {
  const manualId = manualIdOf(actor);
  const linked = manualId ? aliases[manualId] : undefined;
  return linked ?? actor;
};
