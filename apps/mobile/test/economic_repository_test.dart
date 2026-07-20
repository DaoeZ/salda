import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';

class _FakeFunctions implements EconomicFunctionsGateway {
  final created = <Map<String, Object>>[];
  final resolved = <Map<String, Object>>[];

  @override
  Future<void> rebuildMyRelations() async {}

  @override
  Future<void> createPayment(Map<String, Object> data) async =>
      created.add(data);

  @override
  Future<void> resolvePayment(Map<String, Object> data) async =>
      resolved.add(data);
}

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
      await repository.confirmPayment('p1');
      await repository.rejectPayment('p2');
      await repository.cancelPayment('p3');

      expect(functions.resolved, [
        {'paymentId': 'p1', 'action': 'confirm'},
        {'paymentId': 'p2', 'action': 'reject'},
        {'paymentId': 'p3', 'action': 'cancel'},
      ]);
    },
  );

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
}
