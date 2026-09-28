import 'package:domain/domain.dart' show EconomicPaymentStatus, Money;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/economic_repository.dart';

/// Pagos humanos que SOBREVIVIRÁN a la eliminación de un gasto (A2).
///
/// Se distingue lo que no puede mezclarse: un pago CONFIRMADO es dinero que
/// alguien reconoció haber recibido —y al desaparecer la deuda se convierte
/// en crédito del pagador—, mientras que una DECLARACIÓN pendiente sigue
/// esperando esa confirmación y no mueve ningún saldo todavía.
class TicketPaymentImpact {
  const TicketPaymentImpact({
    this.confirmedCount = 0,
    this.confirmedTotal = const Money(0),
    this.pendingCount = 0,
    this.pendingTotal = const Money(0),
    this.currency = 'EUR',
  });

  final int confirmedCount;
  final Money confirmedTotal;
  final int pendingCount;
  final Money pendingTotal;
  final String currency;

  bool get hasConfirmed => confirmedCount > 0;
  bool get hasPending => pendingCount > 0;
  bool get hasAny => hasConfirmed || hasPending;
}

/// Pagos ligados a las obligaciones de ESE ticket, según lo que quien mira
/// está autorizado a ver.
///
/// El vínculo es el que ya existe en el modelo: un pago guarda `allocations`
/// por obligación, y las obligaciones de un ticket se identifican por
/// `sessionId` + `ticketId`. No se inventa ninguna cifra.
///
/// Límite deliberado: solo cuenta pagos que la propia persona puede leer
/// (P5 los acota a sus `memberUids`). Quien administra el grupo y no es parte
/// de esa deuda no verá el detalle —y no debe verlo—, así que el diálogo le
/// muestra la advertencia general en vez de números que no puede demostrar.
final ticketPaymentImpactProvider = Provider.autoDispose
    .family<TicketPaymentImpact, ({String sessionId, String ticketId})>((
      ref,
      key,
    ) {
      final overview = ref.watch(participantEconomicOverviewProvider).value;
      if (overview == null) return const TicketPaymentImpact();

      final entryIds = {
        for (final entry in overview.entries)
          if (entry.sessionId == key.sessionId &&
              entry.ticketId == key.ticketId)
            entry.id,
      };
      if (entryIds.isEmpty) return const TicketPaymentImpact();

      var confirmedCount = 0;
      var confirmedCents = 0;
      var pendingCount = 0;
      var pendingCents = 0;
      var currency = 'EUR';
      for (final payment in overview.payments) {
        if (payment.status == EconomicPaymentStatus.cancelled) continue;
        // El importe que se enseña es el ASIGNADO a este ticket, no el total
        // del pago: un pago puede cubrir varias deudas y solo desaparece la
        // de aquí.
        var cents = 0;
        for (final allocation in payment.allocations.entries) {
          if (entryIds.contains(allocation.key)) {
            cents += allocation.value.cents;
          }
        }
        if (cents <= 0) continue;
        currency = payment.currency;
        if (payment.status == EconomicPaymentStatus.confirmed) {
          confirmedCount++;
          confirmedCents += cents;
        } else {
          pendingCount++;
          pendingCents += cents;
        }
      }
      return TicketPaymentImpact(
        confirmedCount: confirmedCount,
        confirmedTotal: Money(confirmedCents),
        pendingCount: pendingCount,
        pendingTotal: Money(pendingCents),
        currency: currency,
      );
    });
