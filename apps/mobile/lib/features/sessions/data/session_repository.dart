import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  /// Devuelve el id de la sesión creada.
  Future<String> createSession(NewSessionInput input);

  /// Añade un ticket como cuenta nueva de una sesión existente.
  /// Con la segunda cuenta, la sesión pasa a `kind: multi`.
  Future<void> addTicket(
    String sessionId,
    NewTicketInput ticket, {
    required String payerPid,
  });

  Future<void> updateSettlementState(
    String sessionId,
    String settlementId,
    SettlementState state,
  );

  Future<void> setStatus(String sessionId, SessionStatus status);
  Future<void> deleteSession(String sessionId);

  /// Regenera el shareCode (invalida enlaces) y revoca los guestAccess.
  Future<String> regenerateShareCode(String sessionId);
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return FirestoreSessionRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => FirebaseAuth.instance.currentUser!.uid,
    shareCodeFactory: () => ShareCode.generate().value,
  );
});
