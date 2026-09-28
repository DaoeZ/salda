import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';

/// Vinculación de identidad (Sprint 6, ADR-037) — contrato del repositorio.
///
/// Que nadie pueda saltarse la aprobación lo demuestran las Rules contra el
/// emulador (bloque «vinculación de identidad»). Aquí se fija QUÉ escribe la
/// app en cada paso y, sobre todo, qué NO toca.
void main() {
  late FakeFirebaseFirestore firestore;

  ManualLinkRepository repoFor(String uid) => ManualLinkRepository(
    firestore: firestore,
    uid: () => uid,
    functions: _CallableBackedManualLinkGateway(firestore, uid),
  );

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
      await repoFor('uid-marta').request('sp1', 'm1', displayName: 'Marta');

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
    await repoFor('uid-marta').request('sp1', 'm1', displayName: 'Marta');

    final pending = await repoFor('owner').watchPending('sp1').first;
    expect(pending, hasLength(1));
    expect(pending.single.manualId, 'm1');
    expect(pending.single.displayName, 'Marta');
    expect(pending.single.isPending, isTrue);
  });

  test(
    'aceptar escribe el vínculo y resuelve la solicitud, a la vez',
    () async {
      await repoFor('uid-marta').request('sp1', 'm1', displayName: 'Marta');
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
      expect(
        manual['linkStatus'],
        isNull,
        reason: 'accepted no equivale a active',
      );
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
    await repoFor('uid-marta').request('sp1', 'm1', displayName: 'Marta');
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

  test('FakeFirestore solo comprueba la mecánica de una solicitud', () async {
    await repoFor('uid-alba').request('sp1', 'm1', displayName: 'Alba');
    final owner = repoFor('owner');
    await owner.approve('sp1', (await owner.watchPending('sp1').first).single);

    expect(
      (await firestore.doc('spaces/sp1/manualParticipants/m1').get())
          .data()!['linkedUid'],
      'uid-alba',
    );
  });

  test('quien pide ve el estado de SU solicitud', () async {
    final marta = repoFor('uid-marta');
    expect(await marta.watchMine('sp1', 'm1').first, isNull);

    await marta.request('sp1', 'm1', displayName: 'Marta');
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
      await marta.request('sp1', 'm1', displayName: 'Marta');
      await marta.request('sp1', 'm1', displayName: 'Marta');

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

  test('el manual expone el estado real y el fallback conservador', () async {
    final spaces = SpacesRepository(
      firestore: firestore,
      uid: () => 'uid-marta',
      isFullAccount: () => true,
    );

    await firestore.doc('spaces/sp1/manualParticipants/m1').update({
      'linkedUid': 'uid-marta',
    });
    var manual = await spaces.watchManualParticipant('sp1', 'm1').first;
    expect(manual?.effectiveLinkStatus, ManualLinkPropagationStatus.processing);

    for (final (raw, expected) in [
      ('processing', ManualLinkPropagationStatus.processing),
      ('active', ManualLinkPropagationStatus.active),
      ('failed', ManualLinkPropagationStatus.failed),
    ]) {
      await firestore.doc('spaces/sp1/manualParticipants/m1').update({
        'linkStatus': raw,
      });
      manual = await spaces.watchManualParticipant('sp1', 'm1').first;
      expect(manual?.effectiveLinkStatus, expected);
    }
  });

  test('un manual antiguo sin metadatos no se considera vinculado', () async {
    final spaces = SpacesRepository(
      firestore: firestore,
      uid: () => 'uid-marta',
      isFullAccount: () => true,
    );
    final manual = await spaces.watchManualParticipant('sp1', 'm1').first;
    expect(manual?.linkStatus, isNull);
    expect(manual?.effectiveLinkStatus, isNull);
  });

  test('pedir vinculación delega el callable sin UID ni propietario', () async {
    final gateway = _RecordingManualLinkGateway();
    final repo = ManualLinkRepository(
      firestore: firestore,
      uid: () => 'uid-marta',
      functions: gateway,
    );

    await repo.request(
      'sp1',
      'm1',
      displayName: 'Marta',
      viaSessionId: 's1',
      viaTicketId: 't1',
      viaPid: 'p2',
    );

    expect(gateway.spaceId, 'sp1');
    expect(gateway.manualId, 'm1');
    expect(gateway.displayName, 'Marta');
    expect(gateway.viaSessionId, 's1');
    expect(gateway.viaTicketId, 't1');
    expect(gateway.viaPid, 'p2');
  });

  test(
    'retryPropagation delega solo la ruta al gateway de Functions',
    () async {
      final gateway = _RecordingManualLinkGateway();
      final repo = ManualLinkRepository(
        firestore: firestore,
        uid: () => 'uid-marta',
        functions: gateway,
      );

      final result = await repo.retryPropagation('sp1', 'm1');

      expect(gateway.spaceId, 'sp1');
      expect(gateway.manualId, 'm1');
      expect(result.action, ManualLinkRetryAction.claimed);
      expect(result.status, ManualLinkPropagationStatus.active);
    },
  );
}

class _RecordingManualLinkGateway implements ManualLinkFunctionsGateway {
  String? spaceId;
  String? manualId;
  String? displayName;
  String? viaSessionId;
  String? viaTicketId;
  String? viaPid;

  @override
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId = '',
    String viaTicketId = '',
    String viaPid = '',
  }) async {
    this.spaceId = spaceId;
    this.manualId = manualId;
    this.displayName = displayName;
    this.viaSessionId = viaSessionId;
    this.viaTicketId = viaTicketId;
    this.viaPid = viaPid;
  }

  @override
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) async {
    this.spaceId = spaceId;
    this.manualId = manualId;
    return const ManualLinkRetryResult(
      status: ManualLinkPropagationStatus.active,
      action: ManualLinkRetryAction.claimed,
    );
  }
}

class _CallableBackedManualLinkGateway implements ManualLinkFunctionsGateway {
  _CallableBackedManualLinkGateway(this.firestore, this.uid);

  final FakeFirebaseFirestore firestore;
  final String uid;

  @override
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId = '',
    String viaTicketId = '',
    String viaPid = '',
  }) async {
    final ref = firestore.doc(
      'spaces/$spaceId/manualLinkRequests/${manualId}_$uid',
    );
    if ((await ref.get()).exists) return;
    final owner = (await firestore.doc('spaces/$spaceId').get())
        .data()?['ownerUid'];
    await ref.set({
      'manualId': manualId,
      'uid': uid,
      'displayName': displayName,
      'spaceOwnerUid': owner,
      'status': 'pending',
      'attempt': 1,
      'schemaVersion': 1,
    });
  }

  @override
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) async => const ManualLinkRetryResult(
    status: ManualLinkPropagationStatus.processing,
    action: ManualLinkRetryAction.inProgress,
  );
}
