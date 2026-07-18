/// Espacios compartidos (P4): el contenedor social para organizar tickets
/// entre varias personas. UN MISMO modelo para pareja, amigos, familia, viaje
/// o grupos grandes: no existe un sistema aparte para relaciones de dos.
///
/// Separación de conceptos (ADR-028):
/// - membresía ≠ amistad (se puede compartir espacio sin ser amigos);
/// - membresía ≠ participación en tickets (los tickets siguen viviendo en
///   sesiones con sus participantes por nombre);
/// - membresía ≠ deuda (P4 no consolida balances).
/// Todas las claves relacionales son UID: cambiar username/nombre/avatar no
/// altera membresías ni invitaciones.
library;

enum SpaceStatus { active, archived }

enum SpaceInviteStatus { pending, accepted, rejected, cancelled }

class Space {
  const Space({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.status,
    this.avatarEmoji,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String ownerUid;
  final SpaceStatus status;

  /// Avatar básico opcional (un emoji). El COLOR se deriva siempre del id
  /// del espacio (avatarColorIndex), igual que los avatares de personas.
  final String? avatarEmoji;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == SpaceStatus.active;
}

/// Membresía = acceso al espacio. El ROL no se persiste: propietario es
/// quien coincide con `space.ownerUid` (fuente única de verdad, lo que hace
/// atómica la transferencia); miembro, el resto.
class SpaceMember {
  const SpaceMember({required this.uid, this.joinedAt});

  final String uid;
  final DateTime? joinedAt;
}

/// Invitación con ID determinista `{spaceId}_{toUid}`: por construcción no
/// puede haber dos invitaciones activas a la misma persona para el mismo
/// espacio, y reenviar tras rechazo/cancelación reutiliza el documento.
class SpaceInvite {
  const SpaceInvite({
    required this.id,
    required this.spaceId,
    required this.spaceName,
    required this.fromUid,
    required this.toUid,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String spaceId;

  /// Denormalizado SOLO para pintar la invitación sin leer el espacio (el
  /// receptor aún no puede leerlo). No es clave relacional.
  final String spaceName;
  final String fromUid;
  final String toUid;
  final SpaceInviteStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String idFor(String spaceId, String toUid) => '${spaceId}_$toUid';
}

/// Resumen de un ticket vinculado, leído EN VIVO del propio documento del
/// ticket (collection group por spaceId): nunca hay copia que desincronizar.
class SpaceTicket {
  const SpaceTicket({
    required this.path,
    required this.sessionId,
    required this.merchantName,
    required this.grandTotalCents,
    this.date,
  });

  /// sessions/{sid}/accounts/{aid}/tickets/{tid}
  final String path;
  final String sessionId;
  final String merchantName;
  final int grandTotalCents;
  final String? date;
}
