import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// Streams de Firestore acotados a la pantalla visible (autoDispose:
/// los listeners se cancelan al salir — presupuesto de lecturas, spec §11).
final sessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
    (ref) => ref.watch(sessionRepositoryProvider).watchSessions());

final sessionDetailProvider = StreamProvider.autoDispose
    .family<SessionDetail?, String>(
        (ref, sid) => ref.watch(sessionRepositoryProvider).watchSession(sid));

final participantsProvider = StreamProvider.autoDispose
    .family<List<SessionParticipant>, String>((ref, sid) =>
        ref.watch(sessionRepositoryProvider).watchParticipants(sid));

final accountsProvider = StreamProvider.autoDispose
    .family<List<SessionAccount>, String>(
        (ref, sid) => ref.watch(sessionRepositoryProvider).watchAccounts(sid));

final settlementsProvider = StreamProvider.autoDispose
    .family<List<Settlement>, String>((ref, sid) =>
        ref.watch(sessionRepositoryProvider).watchSettlements(sid));

final accountTicketsProvider = StreamProvider.autoDispose
    .family<List<SessionTicket>, ({String sid, String aid})>((ref, key) => ref
        .watch(sessionRepositoryProvider)
        .watchTickets(key.sid, key.aid));

/// Líneas vivas de un ticket (P2.1): el creador ve elegir y elige él mismo.
final ticketLinesProvider = StreamProvider.autoDispose
    .family<List<TicketLine>, String>((ref, ticketPath) =>
        ref.watch(sessionRepositoryProvider).watchTicketLines(ticketPath));
