/// Errores de dominio con código estable.
///
/// El `code` forma parte del contrato de los vectores dorados: la
/// implementación TS de las functions lanza los mismos códigos, y los tests
/// de paridad comparan por código (los mensajes pueden diferir).
class DomainException implements Exception {
  const DomainException(this.code, this.message);

  /// Línea de ticket sin asignar con política `error` (RF-46).
  static const unassignedLine = 'unassignedLine';

  /// Referencia a un participante que no existe en la sesión.
  static const unknownParticipant = 'unknownParticipant';

  /// Operación que requiere al menos un participante.
  static const emptyParticipants = 'emptyParticipants';

  /// La suma del consumo de un ticket no cuadra con su total.
  static const consumptionMismatch = 'consumptionMismatch';

  /// Asignación con pesos inválidos (vacíos, negativos o cero).
  static const invalidWeights = 'invalidWeights';

  /// Obligación o pago con UID, importe o moneda inválidos.
  static const invalidEconomicRecord = 'invalidEconomicRecord';

  final String code;
  final String message;

  @override
  String toString() => 'DomainException($code): $message';
}
