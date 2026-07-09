/**
 * Errores de dominio con código estable — espejo de
 * packages/domain/lib/src/errors.dart. Los códigos forman parte del
 * contrato de los vectores dorados: deben coincidir carácter a carácter.
 */
export type DomainErrorCode =
  | 'unassignedLine'
  | 'unknownParticipant'
  | 'emptyParticipants'
  | 'consumptionMismatch'
  | 'invalidWeights';

export class DomainError extends Error {
  constructor(
    readonly code: DomainErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'DomainError';
  }
}
