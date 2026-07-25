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

import 'package:domain/domain.dart' show manualActor;

enum SpaceStatus { active, archived }

/// Tipo funcional del contexto principal de Salda.
///
/// Los espacios P4 anteriores a este campo se leen como [group]. Esa
/// compatibilidad es deliberada: no se puede deducir una relación social a
/// partir de tickets o de una lista histórica de miembros.
enum SpaceKind { relationship, group }

enum SpaceInviteStatus { pending, accepted, rejected, cancelled }

class Space {
  const Space({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.status,
    this.kind = SpaceKind.group,
    this.relationshipUids = const [],
    this.guestsCanCreateExpenses = false,
    this.avatarEmoji,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String ownerUid;
  final SpaceStatus status;
  final SpaceKind kind;

  /// Pareja canónica reservada por una relación, incluso mientras la segunda
  /// persona todavía no haya aceptado la invitación.
  final List<String> relationshipUids;

  /// Avatar básico opcional (un emoji). El COLOR se deriva siempre del id
  /// del espacio (avatarColorIndex), igual que los avatares de personas.
  final String? avatarEmoji;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Política del anfitrión (ADR-034): si los INVITADOS de este contexto
  /// pueden originar gastos. Por defecto NO (valor conservador).
  final bool guestsCanCreateExpenses;

  bool get isActive => status == SpaceStatus.active;
  bool get isRelationship => kind == SpaceKind.relationship;
}

/// ID canónico e independiente del orden para una relación entre dos UID.
/// Firebase Auth genera UID sin `/`; `~` mantiene el ID verificable también
/// desde Rules, que así puede impedir parejas duplicadas sin una Function.
String relationshipSpaceId(String leftUid, String rightUid) {
  if (leftUid == rightUid) {
    throw ArgumentError.value(rightUid, 'rightUid', 'Debe ser otro usuario');
  }
  final pair = [leftUid, rightUid]..sort();
  if (pair.any((value) => value.contains('/') || value.contains('~'))) {
    throw ArgumentError('UID incompatible con el identificador de relación');
  }
  return 'relationship_${pair.first}~${pair.last}';
}

/// Membresía = acceso al espacio. El ROL no se persiste: propietario es
/// quien coincide con `space.ownerUid` (fuente única de verdad, lo que hace
/// atómica la transferencia); miembro, el resto.
class SpaceMember {
  const SpaceMember({
    required this.uid,
    this.joinedAt,
    this.kind = SpaceMemberKind.account,
    this.displayName,
  });

  final String uid;
  final DateTime? joinedAt;

  /// Cuenta o INVITADO (ADR-034). Un invitado participa igual, pero no
  /// administra nada ni tiene perfil público.
  final SpaceMemberKind kind;

  /// Nombre visible congelado al unirse, SOLO para invitados: no tienen
  /// perfil público del que leerlo en vivo.
  final String? displayName;

  bool get isGuest => kind == SpaceMemberKind.guest;
}

enum SpaceMemberKind { account, guest }

/// Participante MANUAL (ADR-033): una persona sin cuenta que el anfitrión
/// escribe a mano. No tiene UID ni dispositivo — no lee ni confirma nada —
/// pero económicamente pesa igual que una cuenta: su actor es
/// `manual:{id}` y con él aparece en repartos, balances y obligaciones.
///
/// El identificador es opaco y estable, NUNCA el nombre: renombrar no toca
/// el historial y una futura vinculación con una cuenta real solo tendrá
/// que reescribir la referencia del actor (`linkedUid`, hoy siempre null).
class ManualParticipant {
  const ManualParticipant({
    required this.id,
    required this.displayName,
    this.linkedUid,
    this.createdByUid = '',
    this.createdAt,
  });

  final String id;
  final String displayName;

  /// Reservado para la fase de vinculación; hoy siempre null.
  final String? linkedUid;
  final String createdByUid;
  final DateTime? createdAt;

  /// Identidad económica canónica de este participante.
  String get actor => manualActor(id);
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
