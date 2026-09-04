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

/// Ticket alcanzado por DERECHO HISTÓRICO (A11d), si lo hay.
///
/// Dos lecturas deterministas: el derecho —que guarda la cuenta— y el
/// ticket. Es el ÚNICO camino que funciona para quien ya no es miembro del
/// grupo, porque a un ex-miembro no se le permite listar las cuentas.
final historicTicketProvider = FutureProvider.autoDispose
    .family<HistoricTicket?, ({String sid, String tid})>(
      (ref, key) => ref
          .watch(sessionRepositoryProvider)
          .fetchHistoricTicket(key.sid, key.tid),
    );

/// Nombres del reparto de un ticket: `pid → nombre`.
///
/// Prioriza los participantes VIVOS de la sesión, que es lo que ve quien
/// tiene acceso normal. Para quien solo conserva el derecho histórico se
/// repliega al snapshot congelado del ticket: sin nombres detrás de cada
/// `pid` el reparto es ilegible, y abrirle el censo entero de la sesión
/// sería mucho más de lo que necesita para auditar SU deuda.
final ticketParticipantNamesProvider = Provider.autoDispose
    .family<Map<String, String>, ({String sid, String tid})>((ref, key) {
      final live = ref.watch(participantsProvider(key.sid)).value;
      if (live != null && live.isNotEmpty) {
        return {for (final p in live) p.id: p.name};
      }
      return ref.watch(historicTicketProvider(key)).value?.participantNames ??
          const {};
    });

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

/// ¿Puedo ELIMINAR este gasto? (A2)
///
/// Misma autoridad que corregirlo —el creador, que en este modelo es el dueño
/// de la sesión porque nadie más puede crear tickets, y quien administra el
/// GRUPO— con una condición añadida: una sesión CERRADA es solo lectura, y
/// borrar es la modificación más destructiva de todas. Cuando el estado no se
/// puede leer (quien administra el grupo no lee la sesión: ahí vive el
/// `shareCode`) se ofrece y mandan las Rules, que comprueban `isOpen`.
final canDeleteTicketProvider = Provider.autoDispose
    .family<bool, ({String sessionId, String spaceId})>((ref, key) {
      if (!ref.watch(canCorrectTicketProvider(key))) return false;
      final session = ref.watch(sessionDetailProvider(key.sessionId)).value;
      return session == null || session.summary.status == SessionStatus.open;
    });

/// ¿Puedo repartir el consumo de OTRAS personas en este gasto? (A10)
///
/// Es una autoridad DISTINTA de corregir el contenido, aunque hoy la tenga
/// el mismo conjunto de personas: quien subió el gasto y quien administra el
/// grupo del que nació. Se declara aparte para que ampliar una no arrastre a
/// la otra por accidente — repartir no da derecho a cambiar precios, y al
/// revés tampoco, y las Rules lo separan igual.
///
/// La sesión cerrada es de solo lectura. Cuando no se puede leer su estado
/// —quien administra el grupo no lee `sessions/{sid}`: ahí vive el
/// `shareCode`— se ofrece y mandan las Rules.
final canAssignConsumptionProvider = Provider.autoDispose
    .family<bool, ({String sessionId, String spaceId})>((ref, key) {
      if (!ref.watch(canCorrectTicketProvider(key))) return false;
      final session = ref.watch(sessionDetailProvider(key.sessionId)).value;
      return session == null || session.summary.status == SessionStatus.open;
    });

/// Líneas vivas de un ticket (P2.1): el creador ve elegir y elige él mismo.
final ticketLinesProvider = StreamProvider.autoDispose
    .family<List<TicketLine>, String>(
      (ref, ticketPath) =>
          ref.watch(sessionRepositoryProvider).watchTicketLines(ticketPath),
    );
