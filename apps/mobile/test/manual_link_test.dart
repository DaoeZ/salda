import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';

/// Vinculación de identidad (Sprint 6, ADR-037) — contrato del repositorio.
///
/// Que nadie pueda saltarse la aprobación lo demuestran las Rules contra el
/// emulador (bloque «vinculación de identidad»). Aquí se fija QUÉ escribe la
/// app en cada paso y, sobre todo, qué NO toca.
void main() {
  late FakeFirebaseFirestore firestore;

  ManualLinkRepository repoFor(String uid) =>
      ManualLinkRepository(firestore: firestore, uid: () => uid);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': null,
      'createdByUid': 'owner',
      'schemaVersion': 1,
    });
  });

  test(
    'pedir la vinculación crea una solicitud PENDIENTE para uno mismo',
    () async {
      await repoFor(
        'uid-marta',
      ).request('sp1', 'm1', displayName: 'Marta', spaceOwnerUid: 'owner');

      final raw =
          (await firestore
                  .doc('spaces/sp1/manualLinkRequests/m1_uid-marta')
                  .get())
              .data()!;
      expect(raw['manualId'], 'm1');
      expect(raw['uid'], 'uid-marta');
      expect(raw['status'], 'pending');
      // Pedirla NO vincula nada por sí sola.
      final manual =
          (await firestore.doc('spaces/sp1/manualParticipants/m1').get())
              .data()!;
      expect(manual['linkedUid'], isNull);
    },
  );

  test('el anfitrión ve las pendientes de su espacio', () async {
    await repoFor(
      'uid-marta',
    ).request('sp1', 'm1', displayName: 'Marta', spaceOwnerUid: 'owner');

    final pending = await repoFor('owner').watchPending('sp1').first;
    expect(pending, hasLength(1));
    expect(pending.single.manualId, 'm1');
    expect(pending.single.displayName, 'Marta');
    expect(pending.single.isPending, isTrue);
  });

  test(
    'aceptar escribe el vínculo y resuelve la solicitud, a la vez',
    () async {
      await repoFor(
        'uid-marta',
      ).request('sp1', 'm1', displayName: 'Marta', spaceOwnerUid: 'owner');
      final owner = repoFor('owner');
      await owner.approve(
        'sp1',
        (await owner.watchPending('sp1').first).single,
      );

      final manual =
          (await firestore.doc('spaces/sp1/manualParticipants/m1').get())
              .data()!;
      // Lo ÚNICO que cambia: se añade la identidad.
      expect(manual['linkedUid'], 'uid-marta');
      // El identificador manual —el actor económico— no se toca.
      expect(manual['manualId'], 'm1');
      expect(manual['displayName'], 'Marta');

      final request =
          (await firestore
                  .doc('spaces/sp1/manualLinkRequests/m1_uid-marta')
                  .get())
              .data()!;
      expect(request['status'], 'accepted');
      // A3: la reserva uid → manual se escribe en el MISMO batch. Sin ella,
      // la misma persona podria vincularse a dos manuales y acabar
      // debiendose dinero a si misma.
      final reserva =
          (await firestore.doc('spaces/sp1/linkedIdentities/uid-marta').get())
              .data()!;
      expect(reserva['manualId'], 'm1');
      expect(reserva['uid'], 'uid-marta');
      // Y deja de estar pendiente en la bandeja.
      expect(await owner.watchPending('sp1').first, isEmpty);
    },
  );

  test('rechazar NO vincula y conserva el rastro', () async {
    await repoFor(
      'uid-marta',
    ).request('sp1', 'm1', displayName: 'Marta', spaceOwnerUid: 'owner');
    await repoFor('owner').reject('sp1', 'm1_uid-marta');

    final manual =
        (await firestore.doc('spaces/sp1/manualParticipants/m1').get()).data()!;
    expect(manual['linkedUid'], isNull);
    // La solicitud sigue existiendo: es la prueba de que se decidió.
    final request =
        (await firestore
                .doc('spaces/sp1/manualLinkRequests/m1_uid-marta')
                .get())
            .data()!;
    expect(request['status'], 'rejected');
  });

  test('un INVITADO puede pedirlo igual que una cuenta', () async {
    await repoFor(
      'guest-1',
    ).request('sp1', 'm1', displayName: 'Alba', spaceOwnerUid: 'owner');
    final owner = repoFor('owner');
    await owner.approve('sp1', (await owner.watchPending('sp1').first).single);

    expect(
      (await firestore.doc('spaces/sp1/manualParticipants/m1').get())
          .data()!['linkedUid'],
      'guest-1',
    );
  });

  test('quien pide ve el estado de SU solicitud', () async {
    final marta = repoFor('uid-marta');
    expect(await marta.watchMine('sp1', 'm1').first, isNull);

    await marta.request(
      'sp1',
      'm1',
      displayName: 'Marta',
      spaceOwnerUid: 'owner',
    );
    expect((await marta.watchMine('sp1', 'm1').first)!.isPending, isTrue);

    final owner = repoFor('owner');
    await owner.approve('sp1', (await owner.watchPending('sp1').first).single);
    expect(
      (await marta.watchMine('sp1', 'm1').first)!.status,
      ManualLinkStatus.accepted,
    );
  });

  test(
    'el id de la solicitud es determinista: reintentar no duplica',
    () async {
      final marta = repoFor('uid-marta');
      await marta.request(
        'sp1',
        'm1',
        displayName: 'Marta',
        spaceOwnerUid: 'owner',
      );
      await marta.request(
        'sp1',
        'm1',
        displayName: 'Marta',
        spaceOwnerUid: 'owner',
      );

      final all = await firestore
          .collection('spaces/sp1/manualLinkRequests')
          .get();
      expect(all.docs, hasLength(1));
      expect(
        all.docs.single.id,
        ManualLinkRepository.requestId('m1', 'uid-marta'),
      );
    },
  );

  test('M4: la solicitud lleva el propietario denormalizado', () async {
    await repoFor(
      'uid-marta',
    ).request('sp1', 'm1', displayName: 'Marta', spaceOwnerUid: 'owner');
    final raw =
        (await firestore
                .doc('spaces/sp1/manualLinkRequests/m1_uid-marta')
                .get())
            .data()!;
    // Es lo que permite la bandeja global sin un get() por documento. Rules
    // lo valida contra el propietario real, asi que no es una afirmacion.
    expect(raw['spaceOwnerUid'], 'owner');
  });
}
