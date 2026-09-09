import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';

/// Caso real de la prueba en dispositivo: Test debe a Edgar 14,73 € que salen
/// de DOS tickets (Familycash 6,75 y «t familycash» 7,98). El agregado es un
/// resumen; las obligaciones son las de verdad (ADR-038).
EconomicEntryView entry(String id, int cents, String name, {String? date}) =>
    EconomicEntryView(
      id: id,
      debtorUid: 'test',
      creditorUid: 'edgar',
      amount: Money(cents),
      currency: 'EUR',
      sessionId: 's1',
      accountId: 'a1',
      ticketId: 't$id',
      ticketName: name,
      ticketDate: date,
    );

EconomicPaymentView payment(
  String id, {
  required Map<String, int> allocations,
  EconomicPaymentStatus status = EconomicPaymentStatus.pending,
  String payer = 'test',
  String receiver = 'edgar',
}) => EconomicPaymentView(
  id: id,
  payerUid: payer,
  receiverUid: receiver,
  amount: Money(allocations.values.fold(0, (a, b) => a + b)),
  currency: 'EUR',
  status: status,
  source: 'user',
  allocations: {
    for (final e in allocations.entries) e.key: Money(e.value),
  },
);

EconomicOverview overviewOf({
  List<EconomicEntryView> entries = const [],
  List<EconomicPaymentView> payments = const [],
}) => EconomicOverview.compute(
  viewerUid: 'edgar',
  entries: entries,
  payments: payments,
);

void main() {
  final familycash = entry('e1', 675, 'Familycash', date: '2026-08-10');
  final tFamilycash = entry('e2', 798, 't familycash', date: '2026-08-12');

  test('el saldo agregado NO sustituye a las deudas que lo forman', () {
    final overview = overviewOf(entries: [familycash, tFamilycash]);

    // El resumen existe...
    expect(overview.balances.single.outstanding, const Money(1473));
    // ...pero cada deuda conserva su importe y su ticket.
    final obligations = overview.obligationsOwedToMe('test');
    expect(obligations.length, 2);
    expect(
      obligations.map((o) => o.remaining.cents).toList()..sort(),
      [675, 798],
    );
    expect(
      obligations.map((o) => o.entry.ticketName).toSet(),
      {'Familycash', 't familycash'},
    );
    // Y ninguna es el agregado.
    expect(obligations.any((o) => o.remaining.cents == 1473), isFalse);
  });

  test('confirmar una deuda deja viva la otra y recalcula el agregado', () {
    final overview = overviewOf(
      entries: [familycash, tFamilycash],
      payments: [
        payment(
          'p1',
          allocations: {'e1': 675},
          status: EconomicPaymentStatus.confirmed,
        ),
      ],
    );

    final obligations = overview.obligationsOwedToMe('test');
    expect(obligations.single.entry.ticketName, 't familycash');
    expect(obligations.single.remaining, const Money(798));
    expect(overview.balances.single.outstanding, const Money(798));
  });

  test('un pago parcial pertenece a SU deuda y no al saldo global', () {
    final overview = overviewOf(
      entries: [familycash, tFamilycash],
      payments: [
        payment(
          'p1',
          allocations: {'e1': 500},
          status: EconomicPaymentStatus.confirmed,
        ),
      ],
    );

    final byId = {
      for (final o in overview.obligationsOwedToMe('test')) o.id: o,
    };
    expect(byId['e1']!.remaining, const Money(175));
    expect(byId['e2']!.remaining, const Money(798));
  });

  test('una declaración pendiente reserva su deuda, no todas', () {
    final overview = overviewOf(
      entries: [familycash, tFamilycash],
      payments: [payment('p1', allocations: {'e1': 675})],
    );

    final byId = {
      for (final o in overview.obligationsOwedToMe('test')) o.id: o,
    };
    // La declarada ya no queda pendiente de cobro por otra vía...
    expect(byId.containsKey('e1'), isFalse);
    // ...y la que nadie declaró sigue viva y es confirmable igualmente.
    expect(byId['e2']!.remaining, const Money(798));
    expect(byId['e2']!.declaration, isNull);
  });

  test('«pagos por confirmar» son DECLARACIONES, no todas las deudas', () {
    final overview = overviewOf(
      entries: [familycash, tFamilycash],
      payments: [payment('p1', allocations: {'e1': 675})],
    );

    final declarations = overview.payments.where(
      (p) => p.isDeclaration && p.receiverUid == 'edgar',
    );
    expect(declarations.length, 1);
    expect(declarations.single.amount, const Money(675));
    // Los 7,98 restantes NO son una declaración pendiente, pero siguen
    // siendo deuda viva y cobrable.
    expect(overview.obligationsOwedToMe('test').single.id, 'e2');
  });

  test('lo mío no se confunde con lo que debo', () {
    final mine = EconomicEntryView(
      id: 'e3',
      debtorUid: 'edgar',
      creditorUid: 'test',
      amount: const Money(300),
      currency: 'EUR',
      sessionId: 's1',
      accountId: 'a1',
      ticketId: 't3',
      ticketName: 'Mi deuda',
    );
    final overview = overviewOf(entries: [familycash, mine]);
    expect(overview.obligationsOwedToMe('test').single.id, 'e1');
  });

  test('un pago cancelado no reserva nada', () {
    final overview = overviewOf(
      entries: [familycash],
      payments: [
        payment(
          'p1',
          allocations: {'e1': 675},
          status: EconomicPaymentStatus.cancelled,
        ),
      ],
    );
    expect(overview.obligationsOwedToMe('test').single.remaining,
        const Money(675));
  });

  test('las deudas con una identidad sin cuenta se listan igual', () {
    final manual = EconomicEntryView(
      id: 'e4',
      debtorUid: 'test',
      creditorUid: 'manual:javi',
      amount: const Money(1000),
      currency: 'EUR',
      sessionId: 's1',
      accountId: 'a1',
      ticketId: 't4',
      ticketName: 'Cena',
      spaceId: 'sp1',
    );
    final overview = EconomicOverview.compute(
      viewerUid: 'edgar',
      entries: [manual],
      payments: const [],
    );
    // Quien representa a Javi cobra POR él: el acreedor es el manual.
    final obligations = overview.openObligations(
      debtorActor: 'test',
      creditorActor: 'manual:javi',
    );
    expect(obligations.single.remaining, const Money(1000));
  });
}
