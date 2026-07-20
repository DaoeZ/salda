import '../errors.dart';
import '../money.dart';

enum EconomicPaymentStatus { pending, confirmed, cancelled }

/// Deuda original explicable por un ticket. Nunca se modifica por un pago.
class EconomicObligation {
  const EconomicObligation({
    required this.id,
    required this.debtorUid,
    required this.creditorUid,
    required this.amount,
    required this.currency,
  });

  final String id;
  final String debtorUid;
  final String creditorUid;
  final Money amount;
  final String currency;
}

/// Transferencia humana. Solo [EconomicPaymentStatus.confirmed] reduce saldo.
class EconomicPaymentRecord {
  const EconomicPaymentRecord({
    required this.id,
    required this.payerUid,
    required this.receiverUid,
    required this.amount,
    required this.currency,
    required this.status,
  });

  final String id;
  final String payerUid;
  final String receiverUid;
  final Money amount;
  final String currency;
  final EconomicPaymentStatus status;
}

/// Balance canónico entre dos UID. Un signo positivo significa que [firstUid]
/// debe a [secondUid]; uno negativo, la dirección contraria.
class BilateralEconomicBalance {
  const BilateralEconomicBalance({
    required this.firstUid,
    required this.secondUid,
    required this.currency,
    required this.originalFirstToSecond,
    required this.originalSecondToFirst,
    required this.confirmedFirstToSecond,
    required this.confirmedSecondToFirst,
    required this.pendingFirstToSecond,
    required this.pendingSecondToFirst,
  });

  final String firstUid;
  final String secondUid;
  final String currency;
  final Money originalFirstToSecond;
  final Money originalSecondToFirst;
  final Money confirmedFirstToSecond;
  final Money confirmedSecondToFirst;
  final Money pendingFirstToSecond;
  final Money pendingSecondToFirst;

  int get signedOutstandingCents =>
      originalFirstToSecond.cents -
      originalSecondToFirst.cents -
      confirmedFirstToSecond.cents +
      confirmedSecondToFirst.cents;

  Money get outstanding => Money(signedOutstandingCents.abs());

  String? get debtorUid => switch (signedOutstandingCents) {
    > 0 => firstUid,
    < 0 => secondUid,
    _ => null,
  };

  String? get creditorUid => switch (signedOutstandingCents) {
    > 0 => secondUid,
    < 0 => firstUid,
    _ => null,
  };
}

/// Neteo BILATERAL únicamente. No reasigna acreedores entre terceras personas.
abstract final class EconomicLedger {
  static List<BilateralEconomicBalance> compute({
    required List<EconomicObligation> obligations,
    List<EconomicPaymentRecord> payments = const [],
  }) {
    final accumulators = <String, _Accumulator>{};

    for (final obligation in obligations) {
      _validate(
        obligation.debtorUid,
        obligation.creditorUid,
        obligation.amount,
        obligation.currency,
      );
      final accumulator = _forPair(
        accumulators,
        obligation.debtorUid,
        obligation.creditorUid,
        obligation.currency,
      );
      if (obligation.debtorUid == accumulator.firstUid) {
        accumulator.originalFirstToSecond += obligation.amount.cents;
      } else {
        accumulator.originalSecondToFirst += obligation.amount.cents;
      }
    }

    for (final payment in payments) {
      _validate(
        payment.payerUid,
        payment.receiverUid,
        payment.amount,
        payment.currency,
      );
      if (payment.status == EconomicPaymentStatus.cancelled) continue;
      final accumulator = _forPair(
        accumulators,
        payment.payerUid,
        payment.receiverUid,
        payment.currency,
      );
      final fromFirst = payment.payerUid == accumulator.firstUid;
      if (payment.status == EconomicPaymentStatus.confirmed) {
        if (fromFirst) {
          accumulator.confirmedFirstToSecond += payment.amount.cents;
        } else {
          accumulator.confirmedSecondToFirst += payment.amount.cents;
        }
      } else if (fromFirst) {
        accumulator.pendingFirstToSecond += payment.amount.cents;
      } else {
        accumulator.pendingSecondToFirst += payment.amount.cents;
      }
    }

    final keys = accumulators.keys.toList()..sort();
    return [for (final key in keys) accumulators[key]!.build()];
  }

  static _Accumulator _forPair(
    Map<String, _Accumulator> accumulators,
    String first,
    String second,
    String currency,
  ) {
    final ordered = first.compareTo(second) < 0
        ? (first: first, second: second)
        : (first: second, second: first);
    final key = '$currency\u0000${ordered.first}\u0000${ordered.second}';
    return accumulators.putIfAbsent(
      key,
      () => _Accumulator(ordered.first, ordered.second, currency),
    );
  }

  static void _validate(String from, String to, Money amount, String currency) {
    if (from.isEmpty || to.isEmpty || from == to || amount.cents <= 0) {
      throw const DomainException(
        DomainException.invalidEconomicRecord,
        'La relación económica requiere dos UID e importe positivo',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const DomainException(
        DomainException.invalidEconomicRecord,
        'La moneda debe ser un código ISO 4217 de tres letras',
      );
    }
  }
}

class _Accumulator {
  _Accumulator(this.firstUid, this.secondUid, this.currency);

  final String firstUid;
  final String secondUid;
  final String currency;
  var originalFirstToSecond = 0;
  var originalSecondToFirst = 0;
  var confirmedFirstToSecond = 0;
  var confirmedSecondToFirst = 0;
  var pendingFirstToSecond = 0;
  var pendingSecondToFirst = 0;

  BilateralEconomicBalance build() => BilateralEconomicBalance(
    firstUid: firstUid,
    secondUid: secondUid,
    currency: currency,
    originalFirstToSecond: Money(originalFirstToSecond),
    originalSecondToFirst: Money(originalSecondToFirst),
    confirmedFirstToSecond: Money(confirmedFirstToSecond),
    confirmedSecondToFirst: Money(confirmedSecondToFirst),
    pendingFirstToSecond: Money(pendingFirstToSecond),
    pendingSecondToFirst: Money(pendingSecondToFirst),
  );
}
