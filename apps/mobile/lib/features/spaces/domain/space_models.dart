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
    this.relationshipManualId = '',
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

  /// Participante MANUAL que ocupa la segunda plaza de una relación sin
  /// cuenta (schemaVersion 3). Vacío en las relaciones entre dos cuentas.
  final String relationshipManualId;

  /// Una relación cuya segunda identidad no tiene UID.
  bool get isManualRelationship =>
      isRelationship && relationshipManualId.isNotEmpty;

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

/// ¿Ese id es el de una relación entre dos cuentas? Se deduce del propio
/// identificador porque hay superficies —una invitación recibida— que
/// hablan del espacio ANTES de poder leerlo. Solo las v2 tienen id canónico;
/// las v3 (con MANUAL) usan un id generado y nunca invitan a nadie.
bool isRelationshipSpaceId(String spaceId) =>
    spaceId.startsWith('relationship_') && spaceId.contains('~');

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

/// Estado de una solicitud de vinculación (ADR-037).
enum ManualLinkStatus { pending, accepted, rejected }

/// Solicitud de vinculación de un participante MANUAL con una identidad
/// (cuenta o invitado), Sprint 6 / ADR-037.
///
/// La pide la propia persona y la aprueba el ANFITRIÓN: ese doble paso es lo
/// que impide que alguien se apropie del historial económico de otro. No se
/// borra nunca — es el rastro de que hubo aprobación.
class ManualLinkRequest {
  const ManualLinkRequest({
    required this.id,
    required this.manualId,
    required this.uid,
    required this.status,
    this.displayName = '',
    this.spaceId = '',
    this.attempt = 1,
    this.createdAt,
  });

  final String id;
  final String manualId;
  final String uid;

  /// Espacio al que pertenece. Se deriva de la ruta del documento en la
  /// bandeja global, donde hace falta para agrupar y navegar.
  final String spaceId;

  /// Nombre con el que se presenta quien solicita. Solo presentación: la
  /// identidad es el UID, y el actor económico sigue siendo el manual.
  final String displayName;
  final ManualLinkStatus status;

  /// Número de intento. Un rechazo no deja a nadie sin salida —el anfitrión
  /// puede equivocarse— pero cada reintento queda contado.
  final int attempt;
  final DateTime? createdAt;

  bool get isPending => status == ManualLinkStatus.pending;
}

/// Enlace de incorporación a un GRUPO (Sprint 4, ADR-035).
///
/// El [token] es el identificador del documento y a la vez el secreto (128
/// bits): conocerlo es la autorización, igual que el `shareCode` de una
/// sesión (ADR-012). Por eso nunca se copia a la membresía ni a ningún otro
/// documento legible por los demás miembros.
///
/// No contiene identidades: un enlace solo dice a qué grupo abre y cómo se
/// llama, así que compartirlo no revela quién está dentro ni hace buscable
/// a nadie — la restricción que ADR-034 exige revisar al cerrar este sprint.
class SpaceJoinLink {
  const SpaceJoinLink({
    required this.token,
    required this.spaceId,
    required this.spaceName,
    required this.createdByUid,
    required this.revoked,
    this.createdAt,
    this.expiresAt,
  });

  final String token;
  final String spaceId;

  /// Denormalizado SOLO para que quien recibe el enlace vea a qué grupo
  /// entra antes de ser miembro (todavía no puede leer el espacio). Mismo
  /// criterio que `SpaceInvite.spaceName`: no es clave relacional.
  final String spaceName;
  final String createdByUid;
  final bool revoked;
  final DateTime? createdAt;

  /// Caducidad OPCIONAL. Un enlace es un secreto portador: poder acotarle la
  /// vida limita el daño de una filtración. Null = sin caducidad (el
  /// propietario siempre puede revocar), que es el valor por defecto.
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// Un enlace sirve si no está revocado y no ha caducado. Rules aplica
  /// exactamente la misma regla; esto solo evita el viaje de ida y vuelta.
  bool usableAt(DateTime now) => !revoked && !isExpiredAt(now);
}

/// Resultado de canjear un enlace. Se distingue "no sirve" de "ya estás
/// dentro" porque la salida de la app es distinta: error amable frente a
/// entrar directamente al grupo.
enum JoinLinkOutcome { joined, alreadyMember, invalid, needsGuestName }

/// Caducidades ofrecidas al crear un enlace. Sin caducidad es el valor por
/// defecto: es lo que había y el propietario siempre puede revocar.
enum JoinLinkLifetime {
  never(null),
  oneDay(Duration(days: 1)),
  sevenDays(Duration(days: 7)),
  thirtyDays(Duration(days: 30));

  const JoinLinkLifetime(this.duration);

  final Duration? duration;
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
