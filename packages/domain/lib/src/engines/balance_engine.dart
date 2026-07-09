import '../errors.dart';
import '../money.dart';

/// Aportación de un ticket al balance: quién lo pagó y qué consumió cada uno
/// (el consumo lo produce SplitEngine; Σ consumo == grandTotal siempre).
class TicketContribution {
  const TicketContribution({
    required this.paidBy,
    required this.grandTotal,
    required this.consumption,
  });

  final String paidBy;
  final Money grandTotal;
  final Map<String, Money> consumption;
}

/// Liquidación ya confirmada (congelada, RF-53): dinero que YA se transfirió
/// y se descuenta antes de generar las pendientes.
class FrozenSettlement {
  const FrozenSettlement({
    required this.from,
    required this.to,
    required this.amount,
  });

  final String from;
  final String to;
  final Money amount;
}

/// Transferencia sugerida "from debe pagar amount a to".
class SettlementDraft {
  const SettlementDraft({
    required this.from,
    required this.to,
    required this.amount,
  });

  final String from;
  final String to;
  final Money amount;

  @override
  bool operator ==(Object other) =>
      other is SettlementDraft &&
      other.from == from &&
      other.to == to &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(from, to, amount);

  @override
  String toString() => 'SettlementDraft($from → $to: ${amount.cents})';
}

/// Posición de un participante (RF-50).
class ParticipantBalance {
  const ParticipantBalance({
    required this.paid,
    required this.consumed,
    required this.net,
    required this.outstanding,
  });

  /// Total de tickets que pagó.
  final Money paid;

  /// Total que consumió.
  final Money consumed;

  /// paid − consumed (positivo = le deben).
  final Money net;

  /// net ajustado por liquidaciones congeladas: lo que queda por moverse.
  final Money outstanding;
}

class BalanceResult {
  const BalanceResult({required this.balances, required this.settlements});

  final Map<String, ParticipantBalance> balances;

  /// Liquidaciones pendientes sugeridas (mínimo nº de transferencias).
  final List<SettlementDraft> settlements;
}

/// Motor de balance de sesión: agrega pagos y consumos, descuenta lo ya
/// liquidado y simplifica deudas con un algoritmo voraz determinista
/// (mayor acreedor ↔ mayor deudor; empates → orden de [participantIds]).
abstract final class BalanceEngine {
  static BalanceResult compute({
    required List<String> participantIds,
    required List<TicketContribution> tickets,
    List<FrozenSettlement> frozenSettlements = const [],
  }) {
    if (participantIds.isEmpty) {
      throw const DomainException(
        DomainException.emptyParticipants,
        'Una sesión necesita al menos un participante',
      );
    }
    final known = participantIds.toSet();

    final paid = {for (final p in participantIds) p: Money.zero};
    final consumed = {for (final p in participantIds) p: Money.zero};

    for (final ticket in tickets) {
      if (!known.contains(ticket.paidBy)) {
        throw DomainException(
          DomainException.unknownParticipant,
          'Pagador desconocido "${ticket.paidBy}"',
        );
      }
      var consumptionSum = Money.zero;
      for (final entry in ticket.consumption.entries) {
        if (!known.contains(entry.key)) {
          throw DomainException(
            DomainException.unknownParticipant,
            'Consumidor desconocido "${entry.key}"',
          );
        }
        consumed[entry.key] = consumed[entry.key]! + entry.value;
        consumptionSum += entry.value;
      }
      if (consumptionSum != ticket.grandTotal) {
        throw DomainException(
          DomainException.consumptionMismatch,
          'El consumo (${consumptionSum.cents}) no cuadra con el total '
          '(${ticket.grandTotal.cents})',
        );
      }
      paid[ticket.paidBy] = paid[ticket.paidBy]! + ticket.grandTotal;
    }

    // outstanding = net ajustado por lo ya transferido (congelado).
    final outstanding = {
      for (final p in participantIds) p: paid[p]! - consumed[p]!,
    };
    for (final frozen in frozenSettlements) {
      if (!known.contains(frozen.from) || !known.contains(frozen.to)) {
        throw DomainException(
          DomainException.unknownParticipant,
          'Liquidación congelada con participante desconocido',
        );
      }
      // `from` ya entregó `amount` a `to`: su posición mejora, la de `to` baja.
      outstanding[frozen.from] = outstanding[frozen.from]! + frozen.amount;
      outstanding[frozen.to] = outstanding[frozen.to]! - frozen.amount;
    }

    return BalanceResult(
      balances: {
        for (final p in participantIds)
          p: ParticipantBalance(
            paid: paid[p]!,
            consumed: consumed[p]!,
            net: paid[p]! - consumed[p]!,
            outstanding: outstanding[p]!,
          ),
      },
      settlements: _simplify(participantIds, outstanding),
    );
  }

  /// Voraz: en cada paso el mayor deudor paga al mayor acreedor todo lo que
  /// pueda. Genera como mucho N−1 transferencias y es determinista.
  static List<SettlementDraft> _simplify(
    List<String> participantIds,
    Map<String, Money> outstanding,
  ) {
    final position = {
      for (var i = 0; i < participantIds.length; i++) participantIds[i]: i,
    };
    // Copias mutables: (pid, importe pendiente positivo).
    final creditors = <MapEntry<String, int>>[];
    final debtors = <MapEntry<String, int>>[];
    for (final p in participantIds) {
      final cents = outstanding[p]!.cents;
      if (cents > 0) creditors.add(MapEntry(p, cents));
      if (cents < 0) debtors.add(MapEntry(p, -cents));
    }

    int byAmountThenOrder(MapEntry<String, int> a, MapEntry<String, int> b) {
      final byAmount = b.value.compareTo(a.value);
      return byAmount != 0
          ? byAmount
          : position[a.key]!.compareTo(position[b.key]!);
    }

    final result = <SettlementDraft>[];
    while (creditors.isNotEmpty && debtors.isNotEmpty) {
      creditors.sort(byAmountThenOrder);
      debtors.sort(byAmountThenOrder);
      final creditor = creditors.first;
      final debtor = debtors.first;
      final amount =
          creditor.value < debtor.value ? creditor.value : debtor.value;

      result.add(SettlementDraft(
        from: debtor.key,
        to: creditor.key,
        amount: Money(amount),
      ));

      final creditorLeft = creditor.value - amount;
      final debtorLeft = debtor.value - amount;
      creditors.removeAt(0);
      debtors.removeAt(0);
      if (creditorLeft > 0) creditors.add(MapEntry(creditor.key, creditorLeft));
      if (debtorLeft > 0) debtors.add(MapEntry(debtor.key, debtorLeft));
    }
    return result;
  }
}
