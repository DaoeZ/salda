import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/session_models.dart';
import 'firestore_session_repository.dart';

/// Puerto del almacenamiento de sesiones. La UI depende de esta interfaz;
/// la implementación real es Firestore (tests: fake_cloud_firestore).
abstract interface class SessionRepository {
  Stream<List<SessionSummary>> watchSessions();
  Stream<SessionDetail?> watchSession(String sessionId);
  Stream<List<SessionParticipant>> watchParticipants(String sessionId);
  Stream<List<SessionAccount>> watchAccounts(String sessionId);
  Stream<List<Settlement>> watchSettlements(String sessionId);

  /// Crea la sesión completa desde la revisión de un ticket.
  /// Devuelve el id de la sesión y la ruta del ticket (para subir su foto).
  Future<({String sessionId, String ticketPath})> createSession(
    NewSessionInput input,
  );

  /// Añade un ticket como cuenta nueva de una sesión existente.
  /// Con la segunda cuenta, la sesión pasa a `kind: multi`.
  /// Devuelve la ruta del ticket creado.
  Future<String> addTicket(
    String sessionId,
    NewTicketInput ticket, {
    required String payerPid,
    required String spaceId,
  });

  Stream<List<SessionTicket>> watchTickets(String sessionId, String accountId);

  /// Líneas de un ticket (lectura puntual para el detalle).
  Future<List<LineExport>> fetchTicketLines(String ticketPath);

  /// Líneas VIVAS de un ticket con su asignación (P2.1): el creador ve a
  /// los invitados elegir en tiempo real y selecciona él mismo.
  Stream<List<TicketLine>> watchTicketLines(String ticketPath);

  /// Escribe la asignación de una línea (solo el owner pasa por aquí; los
  /// invitados escriben desde la web con las reglas quirúrgicas).
  Future<void> setLineAssignment(
    String linePath,
    Map<String, int> weights, {
    required String editorPid,
  });

  /// Convierte EXPLÍCITAMENTE una asignación histórica al modelo P2.2. La
  /// conversión parte vacía porque los pesos anteriores no identifican qué
  /// unidad concreta se compartía.
  Future<void> convertLineToUnitAssignment(
    String linePath, {
    required String editorPid,
    required int unitCount,
  });

  /// Añade o quita un consumidor de UNA unidad mediante ruta punteada. Así
  /// dos dispositivos pueden editar la misma unidad sin pisarse entre sí.
  Future<void> setUnitConsumer(
    String linePath, {
    required int unit,
    required String participantId,
    required bool selected,
  });

  /// Registra la ruta de Storage de la foto del ticket.
  Future<void> setTicketImage(String ticketPath, String storagePath);

  Future<void> updateSettlementState(
    String sessionId,
    String settlementId,
    SettlementState state,
  );

  Future<void> setStatus(String sessionId, SessionStatus status);
  Future<void> deleteSession(String sessionId);

  /// Regenera el shareCode (invalida enlaces) y revoca los guestAccess.
  Future<String> regenerateShareCode(String sessionId);

  /// Árbol completo de cuentas→tickets→líneas (para exportar PDF).
  Future<List<AccountExport>> fetchFullTree(String sessionId);
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return FirestoreSessionRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => uid,
    shareCodeFactory: () => ShareCode.generate().value,
  );
});
