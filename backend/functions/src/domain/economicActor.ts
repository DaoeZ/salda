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

/** UIDs reales de una pareja de actores: la audiencia que puede leerla. */
export const accountUidsOf = (actors: readonly string[]): string[] =>
  [...new Set(actors.filter(isAccountActor))].sort();
