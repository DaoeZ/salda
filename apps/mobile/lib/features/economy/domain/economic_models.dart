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

  EconomicPaymentRecord toDomain() => EconomicPaymentRecord(
    id: id,
    payerUid: payerUid,
    receiverUid: receiverUid,
    amount: amount,
    currency: currency,
    status: status,
  );
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
