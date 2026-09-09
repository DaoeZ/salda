import 'package:domain/domain.dart';

class EconomicEntryView {
  const EconomicEntryView({
    required this.id,
    required this.debtorUid,
    required this.creditorUid,
    required this.amount,
    required this.currency,
    required this.sessionId,
    required this.accountId,
    required this.ticketId,
    required this.ticketName,
    this.ticketDate,
    this.spaceId,
    this.createdAt,
  });

  final String id;
  final String debtorUid;
  final String creditorUid;
  final Money amount;
  final String currency;
  final String sessionId;
  final String accountId;
  final String ticketId;
  final String ticketName;
  final String? ticketDate;
  final String? spaceId;
  final DateTime? createdAt;

  EconomicObligation toDomain() => EconomicObligation(
    id: id,
    debtorUid: debtorUid,
    creditorUid: creditorUid,
    amount: amount,
    currency: currency,
  );
}

class EconomicPaymentView {
  const EconomicPaymentView({
    required this.id,
    required this.payerUid,
    required this.receiverUid,
    required this.amount,
    required this.currency,
    required this.status,
    required this.source,
    this.allocations = const {},
    this.createdAt,
    this.confirmedAt,
    this.sourceSessionId,
    this.settlementId,
    this.spaceId,
    this.onBehalfOfManualId,
  });

  final String id;
  final String payerUid;
  final String receiverUid;
  final Money amount;
  final String currency;
  final EconomicPaymentStatus status;
  final String source;
  final Map<String, Money> allocations;
  final DateTime? createdAt;
  final DateTime? confirmedAt;

  /// Liquidación de sesión de la que procede este pago, si es legado. Sin
  /// ella, "Confirmar recepción" en Economía no tendría dónde escribir: la
  /// callable de P5 rechaza los pagos legado por diseño.
  final String? sourceSessionId;
  final String? settlementId;
  final String? spaceId;

  /// Identidad SIN cuenta en cuyo nombre se registró (ADR-038).
  final String? onBehalfOfManualId;

  /// Un pago legado vive en la liquidación de su sesión, no en P5.
  bool get isLegacy => source == 'legacySettlement';

  /// Declaración del pagador pendiente de que el receptor la confirme.
  bool get isDeclaration => status == EconomicPaymentStatus.pending;

  EconomicPaymentRecord toDomain() => EconomicPaymentRecord(
    id: id,
    payerUid: payerUid,
    receiverUid: receiverUid,
    amount: amount,
    currency: currency,
    status: status,
  );
}

/// Una deuda concreta, viva, con su ticket de origen (ADR-038).
///
/// El saldo agregado ("Test te debe 14,73") es un RESUMEN de estas: nunca una
/// obligación nueva. Cada una conserva su importe pendiente, su declaración
/// del pagador si la hay, y el ticket que la explica.
class EconomicObligationView {
  const EconomicObligationView({
    required this.entry,
    required this.remaining,
    this.declaration,
  });

  final EconomicEntryView entry;

  /// Lo que queda por cobrar de ESTA deuda (importe − ya asignado).
  final Money remaining;

  /// Declaración «ya he pagado» del deudor sobre esta deuda, si existe. Que
  /// no la haya NO impide confirmar el cobro: es opcional (ADR-038).
  final EconomicPaymentView? declaration;

  String get id => entry.id;
  bool get isSettled => remaining.cents <= 0;
}

class CurrencyEconomicSummary {
  const CurrencyEconomicSummary({
    required this.currency,
    required this.owedToMe,
    required this.iOwe,
  });

  final String currency;
  final Money owedToMe;
  final Money iOwe;
  Money get net => owedToMe - iOwe;
}

class EconomicOverview {
  const EconomicOverview({
    required this.viewerUid,
    required this.entries,
    required this.payments,
    required this.balances,
  });

  factory EconomicOverview.compute({
    required String viewerUid,
    required List<EconomicEntryView> entries,
    required List<EconomicPaymentView> payments,
  }) => EconomicOverview(
    viewerUid: viewerUid,
    entries: entries,
    payments: payments,
    balances: EconomicLedger.compute(
      obligations: [for (final entry in entries) entry.toDomain()],
      payments: [for (final payment in payments) payment.toDomain()],
    ),
  );

  final String viewerUid;
  final List<EconomicEntryView> entries;
  final List<EconomicPaymentView> payments;
  final List<BilateralEconomicBalance> balances;

  List<CurrencyEconomicSummary> get summaries {
    final owed = <String, int>{};
    final owe = <String, int>{};
    for (final balance in balances) {
      final debtor = balance.debtorUid;
      if (debtor == null) continue;
      if (debtor == viewerUid) {
        owe[balance.currency] =
            (owe[balance.currency] ?? 0) + balance.outstanding.cents;
      } else {
        owed[balance.currency] =
            (owed[balance.currency] ?? 0) + balance.outstanding.cents;
      }
    }
    final currencies = {...owed.keys, ...owe.keys}.toList()..sort();
    return [
      for (final currency in currencies)
        CurrencyEconomicSummary(
          currency: currency,
          owedToMe: Money(owed[currency] ?? 0),
          iOwe: Money(owe[currency] ?? 0),
        ),
    ];
  }

  List<BilateralEconomicBalance> withUser(String otherUid) => [
    for (final balance in balances)
      if (balance.firstUid == otherUid || balance.secondUid == otherUid)
        balance,
  ];

  List<EconomicEntryView> entriesWith(String otherUid, {String? currency}) => [
    for (final entry in entries)
      if ((entry.debtorUid == otherUid || entry.creditorUid == otherUid) &&
          (currency == null || entry.currency == currency))
        entry,
  ];

  List<EconomicPaymentView> paymentsWith(
    String otherUid, {
    String? currency,
  }) => [
    for (final payment in payments)
      if ((payment.payerUid == otherUid || payment.receiverUid == otherUid) &&
          (currency == null || payment.currency == currency))
        payment,
  ];

  /// Céntimos ya comprometidos sobre cada obligación por pagos NO cancelados.
  /// Una declaración pendiente también reserva: si no, confirmar el cobro y
  /// confirmar la declaración cobrarían dos veces la misma deuda.
  Map<String, int> get _allocatedByEntry {
    final allocated = <String, int>{};
    for (final payment in payments) {
      if (payment.status == EconomicPaymentStatus.cancelled) continue;
      for (final entry in payment.allocations.entries) {
        allocated[entry.key] = (allocated[entry.key] ?? 0) + entry.value.cents;
      }
    }
    return allocated;
  }

  /// Deudas VIVAS que [debtorActor] tiene con [creditorActor], cada una con
  /// su pendiente y su declaración. Ordenadas por fecha de ticket para que la
  /// lista no baile entre recargas.
  List<EconomicObligationView> openObligations({
    required String debtorActor,
    required String creditorActor,
    String? currency,
  }) {
    final allocated = _allocatedByEntry;
    final declarations = <String, EconomicPaymentView>{};
    for (final payment in payments) {
      if (payment.status != EconomicPaymentStatus.pending) continue;
      for (final entryId in payment.allocations.keys) {
        declarations.putIfAbsent(entryId, () => payment);
      }
    }
    final result = <EconomicObligationView>[];
    for (final entry in entries) {
      if (entry.debtorUid != debtorActor) continue;
      if (entry.creditorUid != creditorActor) continue;
      if (currency != null && entry.currency != currency) continue;
      final remaining = entry.amount.cents - (allocated[entry.id] ?? 0);
      if (remaining <= 0) continue;
      result.add(
        EconomicObligationView(
          entry: entry,
          remaining: Money(remaining),
          declaration: declarations[entry.id],
        ),
      );
    }
    result.sort((a, b) {
      final byDate = (b.entry.ticketDate ?? '').compareTo(
        a.entry.ticketDate ?? '',
      );
      return byDate != 0 ? byDate : a.entry.id.compareTo(b.entry.id);
    });
    return result;
  }

  /// Deudas que [otherUid] tiene conmigo y que puedo cobrar.
  List<EconomicObligationView> obligationsOwedToMe(
    String otherUid, {
    String? currency,
  }) => openObligations(
    debtorActor: otherUid,
    creditorActor: viewerUid,
    currency: currency,
  );

  /// Balance del espacio usando solo obligaciones vinculadas y la porción
  /// de cada pago que la Function congeló contra esos tickets.
  EconomicOverview withinSpace(String spaceId) {
    final scopedEntries = [
      for (final entry in entries)
        if (entry.spaceId == spaceId) entry,
    ];
    final entryIds = {for (final entry in scopedEntries) entry.id};
    final scopedPayments = <EconomicPaymentView>[];
    for (final payment in payments) {
      final allocated = payment.allocations.entries
          .where((entry) => entryIds.contains(entry.key))
          .fold(0, (total, entry) => total + entry.value.cents);
      if (allocated == 0) continue;
      scopedPayments.add(
        EconomicPaymentView(
          id: payment.id,
          payerUid: payment.payerUid,
          receiverUid: payment.receiverUid,
          amount: Money(allocated),
          currency: payment.currency,
          status: payment.status,
          source: payment.source,
          allocations: payment.allocations,
          createdAt: payment.createdAt,
          confirmedAt: payment.confirmedAt,
        ),
      );
    }
    return EconomicOverview.compute(
      viewerUid: viewerUid,
      entries: scopedEntries,
      payments: scopedPayments,
    );
  }
}
