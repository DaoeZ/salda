/// Enlaces de TICKET (Sprint 5, ADR-036).
///
/// Un enlace de grupo (ADR-035) incorpora a alguien de forma permanente a un
/// contexto. Este abre UN ticket y permite identificarse **temporalmente**
/// como uno de sus participantes MANUAL. Alcance y amenazas distintos ⇒
/// colección distinta: si `spaceLinks` se reutilizara, una fuga de un enlace
/// de ticket habría dado acceso al grupo entero.
library;

/// Un MANUAL elegible, tal como se pinta en «¿Quién eres?».
///
/// Se denormaliza en el enlace porque quien todavía no se ha identificado no
/// puede leer los participantes de la sesión — y para leerlos necesitaría ya
/// el acceso que está intentando obtener. Contiene lo mínimo: nombre visible
/// e identificadores opacos. Nunca correos, UID ni roles.
class EligibleManual {
  const EligibleManual({
    required this.pid,
    required this.manualId,
    required this.displayName,
  });

  final String pid;
  final String manualId;
  final String displayName;

  Map<String, Object?> toJson() => {
    'pid': pid,
    'manualId': manualId,
    'displayName': displayName,
  };

  static EligibleManual? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pid = raw['pid'] as String?;
    final manualId = raw['manualId'] as String?;
    if (pid == null || manualId == null) return null;
    return EligibleManual(
      pid: pid,
      manualId: manualId,
      displayName: (raw['displayName'] as String?) ?? '',
    );
  }
}

/// Enlace a un ticket concreto. El [token] es el id del documento y a la vez
/// el secreto (128 bits), igual que en ADR-035.
class TicketJoinLink {
  const TicketJoinLink({
    required this.token,
    required this.sessionId,
    required this.accountId,
    required this.ticketId,
    required this.merchantName,
    required this.createdByUid,
    required this.revoked,
    this.spaceId = '',
    this.manuals = const [],
    this.createdAt,
    this.expiresAt,
  });

  final String token;
  final String sessionId;
  final String accountId;
  final String ticketId;

  /// ÚNICA información visible antes de identificarse. Sin importe, sin
  /// líneas y sin participantes: un enlace filtrado no dice cuánto se gastó.
  final String merchantName;
  final String createdByUid;
  final bool revoked;
  final String spaceId;
  final List<EligibleManual> manuals;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// Misma política que los enlaces de grupo: revocado y caducado cierran
  /// igual, y Rules aplica esta misma comprobación en cada uso.
  bool usableAt(DateTime now) => !revoked && !isExpiredAt(now);

  /// Ruta del ticket al que abre.
  String get ticketPath =>
      'sessions/$sessionId/accounts/$accountId/tickets/$ticketId';
}

/// Identificación TEMPORAL de un dispositivo para un ticket.
///
/// **No es vinculación.** No escribe `linkedUid`, no cambia el actor
/// económico (`manual:{manualId}` sigue intacto) y `recompute` no la lee
/// jamás: borrarla no mueve un solo céntimo. Con [manualId] vacío es solo
/// permiso de lectura, sin decir ser nadie.
class TicketAccess {
  const TicketAccess({
    required this.uid,
    required this.token,
    required this.ticketId,
    this.pid = '',
    this.manualId = '',
    this.createdAt,
  });

  final String uid;
  final String token;
  final String ticketId;
  final String pid;
  final String manualId;
  final DateTime? createdAt;

  bool get identifiesAManual => manualId.isNotEmpty;
}

/// Por qué no se puede abrir un enlace de ticket. Revocado, caducado e
/// inexistente colapsan en [invalid] a propósito: distinguirlos convertiría
/// la pantalla en un oráculo de qué tickets existen.
enum TicketLinkOutcome {
  opened,
  needsIdentity,
  needsManualChoice,
  invalid,
  manualTaken,
}
