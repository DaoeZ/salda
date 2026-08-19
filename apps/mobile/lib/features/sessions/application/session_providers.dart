import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../spaces/data/spaces_repository.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// Streams de Firestore acotados a la pantalla visible (autoDispose:
/// los listeners se cancelan al salir — presupuesto de lecturas, spec §11).
final sessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
  (ref) => ref.watch(sessionRepositoryProvider).watchSessions(),
);

final sessionDetailProvider = StreamProvider.autoDispose
    .family<SessionDetail?, String>(
      (ref, sid) => ref.watch(sessionRepositoryProvider).watchSession(sid),
    );

final participantsProvider = StreamProvider.autoDispose
    .family<List<SessionParticipant>, String>(
      (ref, sid) => ref.watch(sessionRepositoryProvider).watchParticipants(sid),
    );

final accountsProvider = StreamProvider.autoDispose
    .family<List<SessionAccount>, String>(
      (ref, sid) => ref.watch(sessionRepositoryProvider).watchAccounts(sid),
    );

final settlementsProvider = StreamProvider.autoDispose
    .family<List<Settlement>, String>(
      (ref, sid) => ref.watch(sessionRepositoryProvider).watchSettlements(sid),
    );

final accountTicketsProvider = StreamProvider.autoDispose
    .family<List<SessionTicket>, ({String sid, String aid})>(
      (ref, key) =>
          ref.watch(sessionRepositoryProvider).watchTickets(key.sid, key.aid),
    );

/// ¿Puedo INTERVENIR en esta sesión, o solo auditarla? (A11b)
///
/// Un miembro del grupo lee el ticket entero —foto, líneas, reparto— pero no
/// escribe nada, y en particular NO puede leer `sessions/{sid}`: ahí vive el
/// `shareCode`, que es la credencial de invitado. Poder leer ese documento
/// es, por tanto, exactamente el conjunto de siempre (dueño de la sesión y
/// su invitado), así que la interfaz pregunta eso en vez de inventarse un
/// segundo modelo de permisos que se desincronizaría de las Rules.
final canEditSessionProvider = Provider.autoDispose.family<bool, String>(
  (ref, sid) => ref.watch(sessionDetailProvider(sid)).hasValue,
);

/// ¿Puedo CORREGIR este gasto? (A11c)
///
/// Dos caminos distintos que acaban en la misma pantalla: el creador de la
/// sesión —que ya podía— y quien administra el GRUPO del que nació el
/// ticket. La autoridad real la aplican las Rules; esto solo decide qué se
/// ofrece. Una relación nunca entra: no tiene administradores.
final canCorrectTicketProvider = Provider.autoDispose
    .family<bool, ({String sessionId, String spaceId})>((ref, key) {
      if (ref.watch(canEditSessionProvider(key.sessionId))) return true;
      if (key.spaceId.isEmpty) return false;
      final space = ref.watch(spaceProvider(key.spaceId)).value;
      if (space == null || space.isRelationship) return false;
      return ref.watch(iAdministerSpaceProvider(key.spaceId));
    });

/// Líneas vivas de un ticket (P2.1): el creador ve elegir y elige él mismo.
final ticketLinesProvider = StreamProvider.autoDispose
    .family<List<TicketLine>, String>(
      (ref, ticketPath) =>
          ref.watch(sessionRepositoryProvider).watchTicketLines(ticketPath),
    );
