import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreSessionRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FirestoreSessionRepository(
      firestore: firestore,
      uid: () => 'owner',
      shareCodeFactory: () => 'CODE-1234567890123456',
    );
  });

  NewSessionInput input() => const NewSessionInput(
        name: 'Cena Casa Paco',
        splitModeDefault: SplitMode.byItem,
        participantNames: ['Edgar', 'Alba', 'Lucía'],
        payerIndex: 1,
        ticket: NewTicketInput(
          kind: 'scanned',
          merchantName: 'Casa Paco',
          category: 'restaurante',
          date: '2026-07-10',
          engine: 'mlkit',
          confidence: 0.9,
          grandTotal: Money(5190),
          lines: [
            NewLineInput(name: 'Cerveza', quantityMilli: 3000, totalPrice: Money(750)),
            NewLineInput(name: 'Solomillo', totalPrice: Money(4440)),
          ],
        ),
      );

  test('createSession escribe el árbol completo según el modelo (spec §7)',
      () async {
    final sid = await repo.createSession(input());

    final session =
        (await firestore.doc('sessions/$sid').get()).data()!;
    expect(session['ownerUid'], 'owner');
    expect(session['kind'], 'single');
    expect(session['status'], 'open');
    expect(session['splitModeDefault'], 'byItem');
    expect(session['shareCode'], 'CODE-1234567890123456');
    expect(session['ownerParticipantId'], 'p0');
    expect(session['computeVersion'], 0);
    expect(session['schemaVersion'], 1);

    final participants = await firestore
        .collection('sessions/$sid/participants')
        .orderBy('order')
        .get();
    expect(participants.docs.length, 3);
    expect(participants.docs.first.id, 'p0');
    expect(participants.docs.first.data()['isOwner'], true);
    expect(participants.docs.last.data()['name'], 'Lucía');

    final tickets = await firestore
        .collection('sessions/$sid/accounts/a0/tickets')
        .get();
    final ticket = tickets.docs.single.data();
    expect(ticket['paidByParticipantId'], 'p1'); // multi-pagador
    expect(ticket['grandTotal'], 5190);

    final lines = await firestore
        .collection(
            'sessions/$sid/accounts/a0/tickets/${tickets.docs.single.id}/lines')
        .orderBy('order')
        .get();
    expect(lines.docs.length, 2);
    expect(lines.docs.first.data()['assignment'],
        {'type': 'unassigned', 'participants': <String, Object?>{}});
    expect(lines.docs.first.data()['quantityMilli'], 3000);
  });

  test('watchSessions mapea agregados y el outstanding del anfitrión',
      () async {
    final sid = await repo.createSession(input());
    // Simula lo que escribiría la function recompute.
    await firestore.doc('sessions/$sid').update({
      'totals': {
        'grandTotal': 5190,
        'settledConfirmed': 1000,
        'settledMarked': 500,
      },
      'balances': {
        'p0': {'paid': 0, 'consumed': 1730, 'net': -1730, 'outstanding': -730},
      },
      'pendingSettlements': 2,
    });

    final summaries = await repo.watchSessions().first;
    final summary = summaries.single;
    expect(summary.grandTotal, const Money(5190));
    expect(summary.myOutstanding, const Money(-730));
    expect(summary.pendingSettlements, 2);
    expect(summary.settledFraction, closeTo(1000 / 5190, 0.0001));
  });

  test('updateSettlementState cambia estado y apunta la auditoría', () async {
    final sid = await repo.createSession(input());
    await firestore.doc('sessions/$sid/settlements/st1').set({
      'from': 'p0',
      'to': 'p1',
      'amount': 500,
      'state': 'pending',
      'stateHistory': <Object?>[],
    });

    await repo.updateSettlementState(sid, 'st1', SettlementState.confirmed);

    final settlement =
        (await firestore.doc('sessions/$sid/settlements/st1').get()).data()!;
    expect(settlement['state'], 'confirmed');
    expect((settlement['stateHistory'] as List).single,
        containsPair('state', 'confirmed'));
  });

  test('regenerateShareCode rota el código y revoca los guestAccess',
      () async {
    final sid = await repo.createSession(input());
    await firestore
        .doc('sessions/$sid/guestAccess/guest1')
        .set({'shareCode': 'CODE-1234567890123456'});

    var calls = 0;
    repo = FirestoreSessionRepository(
      firestore: firestore,
      uid: () => 'owner',
      shareCodeFactory: () => 'NEW-CODE-${calls++}-567890123456',
    );
    final code = await repo.regenerateShareCode(sid);

    expect(code, startsWith('NEW-CODE-'));
    expect(
        (await firestore.doc('sessions/$sid').get()).data()!['shareCode'],
        code);
    final guests =
        await firestore.collection('sessions/$sid/guestAccess').get();
    expect(guests.docs, isEmpty);
  });

  test('cerrar la sesión marca closedAt; el detalle refleja el estado',
      () async {
    final sid = await repo.createSession(input());
    await repo.setStatus(sid, SessionStatus.closed);

    final detail = await repo.watchSession(sid).first;
    expect(detail!.summary.status, SessionStatus.closed);
    expect((await firestore.doc('sessions/$sid').get()).data()!['closedAt'],
        isNotNull);
  });
}
