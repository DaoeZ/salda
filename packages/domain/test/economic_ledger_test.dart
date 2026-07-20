import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  EconomicObligation obligation(
    String id,
    String from,
    String to,
    int cents, {
    String currency = 'EUR',
  }) => EconomicObligation(
    id: id,
    debtorUid: from,
    creditorUid: to,
    amount: Money(cents),
    currency: currency,
  );

  test('el neteo es independiente del orden de lectura', () {
    final items = [
      obligation('a', 'edgar', 'alba', 600),
      obligation('b', 'alba', 'edgar', 1000),
      obligation('c', 'alba', 'edgar', 125),
    ];

    final first = EconomicLedger.compute(obligations: items).single;
    final second = EconomicLedger.compute(
      obligations: items.reversed.toList(),
    ).single;

    expect(first.signedOutstandingCents, 525);
    expect(second.signedOutstandingCents, first.signedOutstandingCents);
    expect(first.debtorUid, 'alba');
    expect(first.creditorUid, 'edgar');
  });

  test('un pago pendiente no descuenta y uno confirmado sí', () {
    final result = EconomicLedger.compute(
      obligations: [obligation('ticket', 'pedro', 'alba', 2500)],
      payments: const [
        EconomicPaymentRecord(
          id: 'pending',
          payerUid: 'pedro',
          receiverUid: 'alba',
          amount: Money(500),
          currency: 'EUR',
          status: EconomicPaymentStatus.pending,
        ),
        EconomicPaymentRecord(
          id: 'confirmed',
          payerUid: 'pedro',
          receiverUid: 'alba',
          amount: Money(1000),
          currency: 'EUR',
          status: EconomicPaymentStatus.confirmed,
        ),
      ],
    ).single;

    expect(result.outstanding, Money(1500));
    expect(result.pendingSecondToFirst, Money(500));
  });

  test('rechaza auto-pago, cero, negativo y moneda inválida', () {
    for (final bad in [
      obligation('self', 'a', 'a', 1),
      obligation('zero', 'a', 'b', 0),
      obligation('negative', 'a', 'b', -1),
      obligation('currency', 'a', 'b', 1, currency: 'eur'),
    ]) {
      expect(
        () => EconomicLedger.compute(obligations: [bad]),
        throwsA(
          isA<DomainException>().having(
            (error) => error.code,
            'code',
            DomainException.invalidEconomicRecord,
          ),
        ),
      );
    }
  });
}
