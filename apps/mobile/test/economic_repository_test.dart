import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';

import 'fakes.dart';

class _FakeFunctions implements EconomicFunctionsGateway {
  final created = <Map<String, Object>>[];
  final resolved = <Map<String, Object>>[];
  var rebuilds = 0;

  @override
  Future<void> rebuildMyRelations() async => rebuilds++;

  @override
  Future<void> createPayment(Map<String, Object> data) async =>
      created.add(data);

  final settled = <Map<String, Object>>[];

  @override
  Future<void> resolvePayment(Map<String, Object> data) async =>
      resolved.add(data);

  @override
  Future<void> settleEntries(Map<String, Object> data) async =>
      settled.add(data);
}

EconomicPaymentView _payment(String id, {String source = 'user'}) =>
    EconomicPaymentView(
      id: id,
      payerUid: 'test',
      receiverUid: 'edgar',
      amount: const Money(675),
      currency: 'EUR',
      status: EconomicPaymentStatus.pending,
      source: source,
      sourceSessionId: source == 'user' ? null : 's1',
      settlementId: source == 'user' ? null : 'st1',
    );

void main() {
  late FakeFirebaseFirestore firestore;
  late _FakeFunctions functions;
  late EconomicRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    functions = _FakeFunctions();
    repository = EconomicRepository(
      firestore: firestore,
      functions: functions,
      uid: () => 'edgar',
      isFullAccount: () => true,
      idempotencyKey: () => '1234567890abcdef',
    );
  });

  test('lee obligaciones y pagos en tiempo real', () async {
    await firestore.doc('economicEntries/e1').set({
      'memberUids': ['alba', 'edgar'],
      'debtorUid': 'alba',
      'creditorUid': 'edgar',
      'amount': 1000,
      'currency': 'EUR',
      'sessionId': 's1',
      'accountId': 'a1',
      'ticketId': 't1',
      'ticketName': 'Cena',
      'spaceId': 'space1',
      'createdAt': DateTime(2026),
    });
    await firestore.doc('economicPayments/p1').set({
      'memberUids': ['alba', 'edgar'],
      'payerUid': 'alba',
      'receiverUid': 'edgar',
      'amount': 400,
      'currency': 'EUR',
      'status': 'confirmed',
      'source': 'user',
      'createdAt': DateTime(2026),
    });

    final entries = await repository.watchEntries().first;
    final payments = await repository.watchPayments().first;
    final overview = EconomicOverview.compute(
      viewerUid: 'edgar',
      entries: entries,
      payments: payments,
    );

    expect(entries.single.ticketName, 'Cena');
    expect(entries.single.spaceId, 'space1');
    expect(overview.balances.single.outstanding, Money(600));
    expect(overview.summaries.single.owedToMe, Money(600));
  });

  test('la proyección participante de cuenta conserva el warmup', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: const AppUser(uid: 'edgar')),
        ),
        economicRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    container.read(participantEconomicOverviewProvider);
    await container.read(economicProjectionWarmupProvider.future);
    expect(functions.rebuilds, 1);
  });

  test('marca pago parcial con idempotencia y céntimos enteros', () async {
    await repository.markPaid(
      receiverUid: 'alba',
      amount: Money(725),
      currency: 'EUR',
    );

    expect(functions.created.single, {
      'receiverUid': 'alba',
      'amount': 725,
      'currency': 'EUR',
      'idempotencyKey': '1234567890abcdef',
    });
  });

  test(
    'confirmar, rechazar y cancelar delegan en la Function autoritativa',
    () async {
      await repository.confirmPayment(_payment('p1'));
      await repository.rejectPayment('p2');
      await repository.cancelPayment('p3');

      expect(functions.resolved, [
        {'paymentId': 'p1', 'action': 'confirm'},
        {'paymentId': 'p2', 'action': 'reject'},
        {'paymentId': 'p3', 'action': 'cancel'},
      ]);
    },
  );

  test('liquidar obligaciones viaja POR DEUDA, nunca por el agregado', () async {
    await repository.settleEntries([
      const EntrySettlementRequest('e_familycash'),
      const EntrySettlementRequest('e_tfamilycash', amount: Money(500)),
    ]);

    expect(functions.settled.single, {
      'entries': [
        {'entryId': 'e_familycash'},
        {'entryId': 'e_tfamilycash', 'amount': 500},
      ],
      'idempotencyKey': '1234567890abcdef',
    });
    // El camino normal no manda importe: lo resuelve el servidor con el
    // pendiente REAL de esa deuda.
    expect(
      (functions.settled.single['entries']! as List).first,
      isNot(contains('amount')),
    );
  });

  test('confirmar un pago LEGADO escribe su liquidación de sesión', () async {
    // La callable de P5 rechaza los pagos legado por diseño: antes Economía
    // ofrecía el botón igualmente y la acción moría con un error genérico.
    await firestore.doc('sessions/s1/settlements/st1').set({
      'from': 'p2',
      'to': 'p1',
      'amount': 675,
      'state': 'marked',
    });

    await repository.confirmPayment(
      _payment('legacy_st1', source: 'legacySettlement'),
    );

    final settlement = await firestore.doc('sessions/s1/settlements/st1').get();
    expect(settlement.data()!['state'], 'confirmed');
    expect(functions.resolved, isEmpty);
  });

  test(
    'bloquea auto-pago, cero e invitado antes de llamar al servidor',
    () async {
      await expectLater(
        repository.markPaid(
          receiverUid: 'edgar',
          amount: Money(1),
          currency: 'EUR',
        ),
        throwsA(isA<EconomicFailure>()),
      );
      await expectLater(
        repository.markPaid(
          receiverUid: 'alba',
          amount: Money.zero,
          currency: 'EUR',
        ),
        throwsA(isA<EconomicFailure>()),
      );
      final guest = EconomicRepository(
        firestore: firestore,
        functions: functions,
        uid: () => 'guest',
        isFullAccount: () => false,
      );
      expect(guest.watchEntries, throwsA(isA<EconomicFailure>()));
      expect(functions.created, isEmpty);
    },
  );

  test(
    'lectura participativa permite invitado y puede limitarse a un espacio',
    () async {
      await firestore.doc('economicEntries/e1').set({
        'memberUids': ['guest', 'alba'],
        'debtorUid': 'alba',
        'creditorUid': 'guest',
        'amount': 1000,
        'currency': 'EUR',
        'sessionId': 's1',
        'accountId': 'a1',
        'ticketId': 't1',
        'ticketName': 'Cena',
        'spaceId': 'space-a',
      });
      await firestore.doc('economicEntries/e2').set({
        'memberUids': ['guest', 'alba'],
        'debtorUid': 'guest',
        'creditorUid': 'alba',
        'amount': 500,
        'currency': 'USD',
        'sessionId': 's2',
        'accountId': 'a2',
        'ticketId': 't2',
        'ticketName': 'Taxi',
        'spaceId': 'space-b',
      });
      final guest = EconomicRepository(
        firestore: firestore,
        functions: functions,
        uid: () => 'guest',
        isFullAccount: () => false,
      );

      final readable = await guest.watchReadableEntries().first;
      expect(readable, hasLength(2));
      expect(
        EconomicOverview.compute(
          viewerUid: 'guest',
          entries: readable,
          payments: const [],
        ).withinSpace('space-a').entries.single.ticketId,
        't1',
      );
      expect(guest.watchEntries, throwsA(isA<EconomicFailure>()));
      await expectLater(
        guest.markPaid(receiverUid: 'alba', amount: Money(1), currency: 'EUR'),
        throwsA(isA<EconomicFailure>()),
      );
    },
  );
}
