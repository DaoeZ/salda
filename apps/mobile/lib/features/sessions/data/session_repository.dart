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

  /// Abre UN ticket por derecho histórico (A11d), sin listar nada.
  ///
  /// Existe porque la resolución normal recorre las cuentas de la sesión, y
  /// a quien ya no es miembro no se le permite —deliberadamente— listarlas.
  /// El derecho histórico guarda la cuenta, así que el ticket se alcanza con
  /// dos lecturas deterministas. Devuelve null si no hay derecho.
  Future<HistoricTicket?> fetchHistoricTicket(
    String sessionId,
    String ticketId,
  );

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
  ///
  /// [myPid] es MI participante en este gasto (null si no soy participante).
  /// Sirve para una sola cosa: decidir si la escritura firma la procedencia.
  Future<void> setUnitConsumer(
    String linePath, {
    required int unit,
    required String participantId,
    required bool selected,
    String? myPid,
  });

  /// Registra la ruta de Storage de la foto del ticket.
  Future<void> setTicketImage(String ticketPath, String storagePath);

  /// Corrige la cabecera del ticket (A11c): comercio, fecha y total. Firma
  /// la corrección con actor y fecha del servidor — sin eso, un gasto podría
  /// cambiar de importe sin que nadie pudiera explicar después quién lo hizo.
  Future<void> correctTicketHeader(
    String ticketPath, {
    required String merchantName,
    String? date,
    required Money grandTotal,
  });

  /// Corrige el contenido de un producto y ajusta el total del ticket con la
  /// diferencia, para que el gasto siga cuadrando.
  ///
  /// [removedUnitIds] son las unidades que dejan de existir: se borran una a
  /// una, por su ruta. Las que sobreviven no se reescriben —así nadie puede
  /// acabar en una unidad que no eligió— y las Rules comprueban justo eso.
  Future<void> correctLine(
    String linePath, {
    required String name,
    required int quantityMilli,
    required Money totalPrice,
    List<String> removedUnitIds = const [],
    List<String>? unitIds,
  });

  /// Retira un producto del ticket y descuenta su importe del total. Sus
  /// asignaciones se van con él: el documento entero desaparece.
  Future<void> removeLine(String linePath);

  /// Elimina el gasto entero (A2): un solo commit con el borrado del ticket y
  /// la evidencia inmutable de quién lo borró. Lo derivado —líneas, foto,
  /// enlaces, derechos históricos, cuenta vacía y agregados— lo purga
  /// `cleanup` después; los PAGOS y la actividad no se tocan nunca.
  Future<void> deleteTicket(String ticketPath);

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
