/**
 * Dinero en céntimos enteros y reparto por resto mayor — espejo exacto de
 * packages/domain/lib/src/money.dart. Si cambias el algoritmo aquí, cambia
 * también la versión Dart: los vectores dorados vigilan la paridad.
 */
import { DomainError } from './errors.js';

/** Céntimos. Se usa `number` como entero; los importes reales caben de sobra en 2^53. */
export type Cents = number;

/**
 * Reparte `total` proporcionalmente a `weights` con el método del resto
 * mayor: Σ resultado === total, determinista (empates → índice menor).
 */
export function allocateProportionally(
  total: Cents,
  weights: readonly number[],
): Cents[] {
  if (weights.length === 0) {
    throw new DomainError(
      'emptyParticipants',
      'No se puede repartir entre cero partes',
    );
  }
  if (weights.some((w) => w < 0)) {
    throw new DomainError('invalidWeights', 'Los pesos no pueden ser negativos');
  }
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  if (totalWeight === 0) {
    throw new DomainError('invalidWeights', 'La suma de pesos no puede ser cero');
  }

  if (total < 0) {
    return allocateProportionally(-total, weights).map((c) => -c);
  }

  const base = weights.map((w) => Math.floor((total * w) / totalWeight));
  const remainders = weights.map((w) => (total * w) % totalWeight);

  let leftover = total - base.reduce((a, b) => a + b, 0);
  const result = [...base];

  const order = weights
    .map((_, i) => i)
    .sort((a, b) => remainders[b] - remainders[a] || a - b);
  for (const i of order) {
    if (leftover === 0) break;
    result[i] += 1;
    leftover -= 1;
  }
  return result;
}

/** Reparto a partes iguales entre `parts`. */
export function allocateEvenly(total: Cents, parts: number): Cents[] {
  return allocateProportionally(total, Array<number>(parts).fill(1));
}
