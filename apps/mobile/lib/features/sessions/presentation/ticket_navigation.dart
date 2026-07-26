import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/session_providers.dart';
import '../domain/session_models.dart';
import 'ticket_detail_screen.dart';

/// ÚNICA forma de abrir un ticket existente, desde cualquier superficie.
///
/// Antes el detalle solo se alcanzaba pasando un `TicketRef` ya montado por
/// `extra`, y ese objeto únicamente existía dentro del detalle de la sesión.
/// Cualquier otra pantalla —los tickets de un espacio, la actividad, el
/// desglose económico— tiene ids, no objetos, así que sencillamente no podía
/// navegar: unas no tenían `onTap` y otras llevaban a la sesión entera.
///
/// La ruta viaja por IDENTIFICADORES y el destino se hidrata solo. Así el
/// enlace es reconstruible (deep link, volver atrás, restaurar estado) y
/// ninguna pantalla necesita conocer la forma interna de un ticket.
String ticketRoute({required String sessionId, required String ticketId}) =>
    '/home/session/$sessionId/ticket/$ticketId';

/// Última navegación aceptada, para descartar el rebote de un doble toque.
String? _ultimaRuta;
DateTime? _ultimoInstante;

/// Ventana en la que un segundo toque sobre la MISMA fila se considera parte
/// del primero. Una lista con filas juntas y un dedo rápido apilaban dos
/// pantallas idénticas, y había que volver dos veces.
const _antirrebote = Duration(milliseconds: 700);

/// Abre el detalle del ticket. [ticketId] es el id del documento, no la ruta.
void openTicket(
  BuildContext context, {
  required String sessionId,
  required String ticketId,
}) {
  if (sessionId.isEmpty || ticketId.isEmpty) return;
  final ruta = ticketRoute(sessionId: sessionId, ticketId: ticketId);
  final ahora = DateTime.now();
  if (_ultimaRuta == ruta &&
      _ultimoInstante != null &&
      ahora.difference(_ultimoInstante!) < _antirrebote) {
    return;
  }
  _ultimaRuta = ruta;
  _ultimoInstante = ahora;
  context.push(ruta);
}

/// Solo para pruebas: olvida el antirrebote entre casos.
@visibleForTesting
void resetTicketNavigationDebounce() {
  _ultimaRuta = null;
  _ultimoInstante = null;
}

/// Ticket de una sesión buscado por su id, sin conocer su cuenta.
///
/// Un ticket vive en `sessions/{sid}/accounts/{aid}/tickets/{tid}`, pero las
/// superficies que enlazan a él casi nunca saben el `aid`: la actividad
/// guarda `sessionId` + `ticketId`, y el resumen económico lo mismo. Se
/// recorren las cuentas de la sesión —son pocas y ya están en caché— en vez
/// de obligar a cada llamante a arrastrar la ruta completa.
final sessionTicketProvider = Provider.autoDispose
    .family<AsyncValue<SessionTicket?>, ({String sid, String tid})>((ref, key) {
      final accounts = ref.watch(accountsProvider(key.sid));
      if (accounts.isLoading) return const AsyncValue.loading();
      if (accounts.hasError) {
        return AsyncValue.error(accounts.error!, accounts.stackTrace!);
      }
      var loading = false;
      for (final account in accounts.value ?? const <SessionAccount>[]) {
        final tickets = ref.watch(
          accountTicketsProvider((sid: key.sid, aid: account.id)),
        );
        if (tickets.isLoading) {
          loading = true;
          continue;
        }
        for (final ticket in tickets.value ?? const <SessionTicket>[]) {
          if (ticket.id == key.tid) return AsyncValue.data(ticket);
        }
      }
      // Mientras quede una cuenta por resolver no se puede afirmar que el
      // ticket no exista.
      return loading ? const AsyncValue.loading() : const AsyncValue.data(null);
    });

/// Pantalla de la ruta: resuelve el ticket y delega en el detalle de siempre.
///
/// No duplica el detalle ni lo diferencia por tipo de espacio — un ticket es
/// un ticket, venga de una relación o de un grupo.
class TicketRoute extends ConsumerWidget {
  const TicketRoute({
    super.key,
    required this.sessionId,
    required this.ticketId,
  });

  final String sessionId;
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ticket = ref.watch(
      sessionTicketProvider((sid: sessionId, tid: ticketId)),
    );
    final participants =
        ref.watch(participantsProvider(sessionId)).value ??
        const <SessionParticipant>[];

    return switch (ticket) {
      AsyncData(:final value?) => TicketDetailScreen(
        ticket: TicketRef(
          sessionId: sessionId,
          ticket: value,
          payerName:
              participants
                  .where((p) => p.id == value.paidBy)
                  .map((p) => p.name)
                  .firstOrNull ??
              '',
        ),
      ),
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: ScreenBody(
          children: [
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.ticketGoneTitle,
              body: l10n.ticketGoneBody,
            ),
          ],
        ),
      ),
      AsyncError() => Scaffold(
        appBar: AppBar(),
        body: ScreenBody(
          children: [ErrorStateView(message: l10n.spacesLoadError)],
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(),
        body: const ScreenBody(children: [SkeletonList(rows: 3)]),
      ),
    };
  }
}
