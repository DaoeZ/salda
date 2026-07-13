import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/settings/data/backup_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BackupService service;
  var codeCounter = 0;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    codeCounter = 0;
    service = BackupService(
      firestore: firestore,
      uid: () => 'owner',
      shareCodeFactory: () => 'REGEN-CODE-${codeCounter++}-4567890',
    );
  });

  Future<String> seedSession() async {
    final repo = FirestoreSessionRepository(
      firestore: firestore,
      uid: () => 'owner',
      shareCodeFactory: () => 'ORIGINAL-CODE-123456',
    );
    final sid = await repo.createSession(const NewSessionInput(
      name: 'Viaje',
      splitModeDefault: SplitMode.byItem,
      participantNames: ['Edgar', 'Alba'],
      ticket: NewTicketInput(
        kind: 'scanned',
        merchantName: 'Hotel',
        engine: 'mlkit',
        confidence: 0.9,
        grandTotal: Money(10000),
        lines: [NewLineInput(name: 'Noche', totalPrice: Money(10000))],
      ),
    ));
    await firestore.doc('sessions/$sid/settlements/st1').set({
      'from': 'p1', 'to': 'p0', 'amount': 5000, 'state': 'confirmed',
    });
    await firestore
        .doc('users/owner')
        .set({'displayName': 'Edgar', 'paymentMethods': {'bizumPhone': '6'}});
    return sid;
  }

  test('export → import restaura todo con shareCode regenerado', () async {
    final sid = await seedSession();
    final backup = await service.exportAll();

    expect(backup['format'], 'appcuentas-backup');
    expect(service.summarize(backup),
        (sessions: 1, tickets: 1, lines: 1));

    // Importa en una cuenta NUEVA (migración de dispositivo/cuenta).
    final fresh = FakeFirebaseFirestore();
    final importer = BackupService(
      firestore: fresh,
      uid: () => 'nueva-cuenta',
      shareCodeFactory: () => 'NEW-SHARE-CODE-9999',
    );
    await importer.import(backup, replace: false);

    final session = (await fresh.doc('sessions/$sid').get()).data()!;
    expect(session['name'], 'Viaje');
    expect(session['ownerUid'], 'nueva-cuenta'); // forzado al importador
    expect(session['shareCode'], 'NEW-SHARE-CODE-9999'); // quemado el viejo

    final lines = await fresh
        .collection('sessions/$sid/accounts/a0/tickets')
        .get()
        .then((t) => fresh
            .collection(
                'sessions/$sid/accounts/a0/tickets/${t.docs.single.id}/lines')
            .get());
    expect(lines.docs.single.data()['totalPrice'], 10000);

    final settlement =
        (await fresh.doc('sessions/$sid/settlements/st1').get()).data()!;
    expect(settlement['state'], 'confirmed'); // las congeladas sobreviven

    final user = (await fresh.doc('users/nueva-cuenta').get()).data()!;
    expect((user['paymentMethods'] as Map)['bizumPhone'], '6');
  });

  test('replace borra las sesiones propias que no están en la copia',
      () async {
    await seedSession();
    final backup = await service.exportAll();

    // Sesión posterior que NO está en el backup.
    await firestore.doc('sessions/extra').set({
      'ownerUid': 'owner', 'name': 'Posterior', 'status': 'open',
    });

    await service.import(backup, replace: true);
    expect((await firestore.doc('sessions/extra').get()).exists, isFalse);

    await service.import(backup, replace: false);
    // En modo fusionar no se borra nada ajeno a la copia.
    await firestore.doc('sessions/extra2').set({
      'ownerUid': 'owner', 'name': 'Otra', 'status': 'open',
    });
    await service.import(backup, replace: false);
    expect((await firestore.doc('sessions/extra2').get()).exists, isTrue);
  });

  test('formato desconocido: rechazado', () async {
    expect(
      () => service.import({'format': 'otra-cosa'}, replace: false),
      throwsA(isA<DomainException>()),
    );
  });
}
