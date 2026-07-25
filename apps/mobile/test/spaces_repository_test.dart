import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  SpacesRepository repoFor(String uid) => SpacesRepository(
    firestore: firestore,
    uid: () => uid,
    isFullAccount: () => true,
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('ciclo de vida del espacio', () {
    test('crear escribe espacio + membresía del fundador en batch', () async {
      final id = await repoFor('uid-a').createSpace('Viaje a Lisboa');

      final space = (await firestore.doc('spaces/$id').get()).data()!;
      expect(space['name'], 'Viaje a Lisboa');
      expect(space['ownerUid'], 'uid-a');
      expect(space['status'], 'active');
      expect(space['schemaVersion'], 2);
      expect(space['kind'], 'group');
      expect(
        (await firestore.doc('spaces/$id/members/uid-a').get()).exists,
        true,
      );
    });

    test(
      'relación usa id canónico y reserva exactamente los dos UID',
      () async {
        final id = await repoFor(
          'uid-b',
        ).createRelationship(toUid: 'uid-a', name: 'Ana y Bruno');

        expect(id, relationshipSpaceId('uid-a', 'uid-b'));
        expect(id, relationshipSpaceId('uid-b', 'uid-a'));
        final space = (await firestore.doc('spaces/$id').get()).data()!;
        expect(space['kind'], 'relationship');
        expect(space['relationshipUids'], ['uid-a', 'uid-b']);
        expect(
          (await firestore.doc('spaceInvites/${id}_uid-a').get()).data(),
          containsPair('status', 'pending'),
        );

        expect(
          () => repoFor(
            'uid-a',
          ).createRelationship(toUid: 'uid-b', name: 'Duplicada'),
          throwsA(
            isA<SpaceFailure>().having(
              (failure) => failure.code,
              'code',
              SpaceFailureCode.alreadyMember,
            ),
          ),
        );
      },
    );

    test('espacio histórico sin kind se interpreta como grupo', () async {
      await firestore.doc('spaces/legacy').set({
        'name': 'Histórico',
        'ownerUid': 'uid-a',
        'status': 'active',
      });
      await firestore.doc('spaces/legacy/members/uid-a').set({'uid': 'uid-a'});

      final spaces = await repoFor('uid-a').watchMySpaces().first;
      expect(spaces.single.kind, SpaceKind.group);
    });

    test('watchMySpaces lista los espacios de MIS membresías', () async {
      final repoA = repoFor('uid-a');
      final id1 = await repoA.createSpace('Piso');
      await repoFor('uid-b').createSpace('Ajeno');

      final spaces = await repoA.watchMySpaces().first;
      expect(spaces.map((s) => s.id), [id1]);
      expect(spaces.single.name, 'Piso');
    });

    test('archivar y reactivar', () async {
      final repo = repoFor('uid-a');
      final id = await repo.createSpace('Peña');
      await repo.setStatus(id, SpaceStatus.archived);
      expect((await repo.watchSpace(id).first)!.status, SpaceStatus.archived);
      await repo.setStatus(id, SpaceStatus.active);
      expect((await repo.watchSpace(id).first)!.isActive, true);
    });

    test(
      'transferencia: un solo doc; a no-miembro falla; a mí mismo, no-op',
      () async {
        final repoA = repoFor('uid-a');
        final id = await repoA.createSpace('Familia');
        await firestore.doc('spaces/$id/members/uid-b').set({
          'uid': 'uid-b',
          'joinedAt': DateTime(2026, 7),
        });

        await repoA.transferOwnership(id, 'uid-b');
        expect((await repoA.watchSpace(id).first)!.ownerUid, 'uid-b');

        await expectLater(
          repoFor('uid-b').transferOwnership(id, 'uid-x'),
          throwsA(
            isA<SpaceFailure>().having(
              (f) => f.code,
              'code',
              SpaceFailureCode.targetUnavailable,
            ),
          ),
        );
        // Idempotente: transferirse a sí mismo no cambia nada.
        await repoFor('uid-b').transferOwnership(id, 'uid-b');
        expect((await repoA.watchSpace(id).first)!.ownerUid, 'uid-b');
      },
    );
  });

  group('invitaciones', () {
    test('id determinista, idempotencia y bloqueo a miembros', () async {
      final repoA = repoFor('uid-a');
      final id = await repoA.createSpace('Viaje');

      await repoA.invite(id, 'Viaje', 'uid-b');
      final inviteId = SpaceInvite.idFor(id, 'uid-b');
      expect(
        (await firestore.doc('spaceInvites/$inviteId').get()).data()!['status'],
        'pending',
      );

      // Repetir la invitación pendiente no crea nada nuevo ni falla.
      await repoA.invite(id, 'Viaje', 'uid-b');
      final all = await firestore.collection('spaceInvites').get();
      expect(all.docs, hasLength(1));

      // Invitar a quien ya es miembro: rechazado en el repositorio.
      await firestore.doc('spaces/$id/members/uid-c').set({
        'uid': 'uid-c',
        'joinedAt': DateTime(2026, 7),
      });
      await expectLater(
        repoA.invite(id, 'Viaje', 'uid-c'),
        throwsA(
          isA<SpaceFailure>().having(
            (f) => f.code,
            'code',
            SpaceFailureCode.alreadyMember,
          ),
        ),
      );
    });

    test('aceptar une al receptor y resuelve la invitación en batch', () async {
      final repoA = repoFor('uid-a');
      final repoB = repoFor('uid-b');
      final id = await repoA.createSpace('Viaje');
      await repoA.invite(id, 'Viaje', 'uid-b');

      final invite = (await repoB.watchMyInvites().first).single;
      await repoB.acceptInvite(invite);

      expect(
        (await firestore.doc('spaces/$id/members/uid-b').get()).exists,
        true,
      );
      expect(await repoB.watchMyInvites().first, isEmpty);
      expect((await repoB.watchMySpaces().first).single.id, id);
    });

    test('rechazar y reenviar reutilizan el MISMO documento', () async {
      final repoA = repoFor('uid-a');
      final repoB = repoFor('uid-b');
      final id = await repoA.createSpace('Viaje');
      await repoA.invite(id, 'Viaje', 'uid-b');
      final invite = (await repoB.watchMyInvites().first).single;

      await repoB.rejectInvite(invite.id);
      expect(await repoB.watchMyInvites().first, isEmpty);

      await repoA.invite(id, 'Viaje', 'uid-b'); // reenvío
      final again = await repoB.watchMyInvites().first;
      expect(again.single.id, invite.id);
      expect(again.single.status, SpaceInviteStatus.pending);
      expect(
        (await firestore.collection('spaceInvites').get()).docs,
        hasLength(1),
      );
    });

    test('cancelar deja la invitación fuera de las pendientes', () async {
      final repoA = repoFor('uid-a');
      final id = await repoA.createSpace('Viaje');
      await repoA.invite(id, 'Viaje', 'uid-b');
      await repoA.cancelInvite(SpaceInvite.idFor(id, 'uid-b'));
      expect(await repoFor('uid-b').watchMyInvites().first, isEmpty);
      expect(await repoA.watchSpaceInvites(id).first, isEmpty);
    });
  });

  group('membresía', () {
    test(
      'el owner no puede salir; un miembro sí (solo su doc social)',
      () async {
        final repoA = repoFor('uid-a');
        final id = await repoA.createSpace('Piso');
        await firestore.doc('spaces/$id/members/uid-b').set({
          'uid': 'uid-b',
          'joinedAt': DateTime(2026, 7),
        });

        await expectLater(
          repoA.leave(id),
          throwsA(
            isA<SpaceFailure>().having(
              (f) => f.code,
              'code',
              SpaceFailureCode.ownerCannotLeave,
            ),
          ),
        );

        await repoFor('uid-b').leave(id);
        expect(
          (await firestore.doc('spaces/$id/members/uid-b').get()).exists,
          false,
        );
        // El espacio y su otro miembro siguen intactos.
        expect((await firestore.doc('spaces/$id').get()).exists, true);
      },
    );

    test('expulsar borra SOLO la membresía', () async {
      final repoA = repoFor('uid-a');
      final id = await repoA.createSpace('Piso');
      await firestore.doc('spaces/$id/members/uid-b').set({
        'uid': 'uid-b',
        'joinedAt': DateTime(2026, 7),
      });
      await repoA.removeMember(id, 'uid-b');
      expect(
        (await firestore.doc('spaces/$id/members/uid-b').get()).exists,
        false,
      );
    });
  });

  group('participantes manuales (ADR-033)', () {
    test('alta: identidad opaca y estable, nunca el nombre', () async {
      final repo = repoFor('uid-a');
      final id = await repo.createSpace('Piso');
      final manual = await repo.addManualParticipant(id, '  Lucía  ');

      expect(manual.displayName, 'Lucía');
      expect(manual.id, isNotEmpty);
      expect(manual.id, isNot(contains('Lucía')));
      // El actor económico es lo que viaja a las obligaciones.
      expect(manual.actor, 'manual:${manual.id}');
      expect(manual.linkedUid, isNull); // vinculación: fase futura

      final raw = (await firestore
              .doc('spaces/$id/manualParticipants/${manual.id}')
              .get())
          .data()!;
      expect(raw['manualId'], manual.id);
      expect(raw['linkedUid'], isNull);
      expect(raw['schemaVersion'], 1);
    });

    test('renombrar NO cambia la identidad económica', () async {
      final repo = repoFor('uid-a');
      final id = await repo.createSpace('Piso');
      final manual = await repo.addManualParticipant(id, 'Lucia');

      await repo.renameManualParticipant(id, manual.id, 'Lucía Gómez');

      final listed = await repo.watchManualParticipants(id).first;
      expect(listed.single.id, manual.id); // misma identidad
      expect(listed.single.displayName, 'Lucía Gómez');
      expect(listed.single.actor, manual.actor);
    });

    test('nombre vacío o desmesurado: rechazado', () async {
      final repo = repoFor('uid-a');
      final id = await repo.createSpace('Piso');
      await expectLater(
        repo.addManualParticipant(id, '   '),
        throwsA(isA<SpaceFailure>()),
      );
      await expectLater(
        repo.addManualParticipant(id, 'x' * 41),
        throwsA(isA<SpaceFailure>()),
      );
    });

    test('conviven varios y se listan por antigüedad', () async {
      final repo = repoFor('uid-a');
      final id = await repo.createSpace('Peña');
      final first = await repo.addManualParticipant(id, 'Ana');
      final second = await repo.addManualParticipant(id, 'Bruno');

      final listed = await repo.watchManualParticipants(id).first;
      expect(listed.map((m) => m.id), [first.id, second.id]);
      expect(listed.map((m) => m.actor).toSet().length, 2); // ids únicos
    });

    test('retirar borra la identidad, no el historial economico', () async {
      final repo = repoFor('uid-a');
      final id = await repo.createSpace('Piso');
      final manual = await repo.addManualParticipant(id, 'Lucía');
      // Una obligación ya derivada conserva el actor aunque se retire.
      await firestore.doc('economicEntries/e1').set({
        'memberUids': ['uid-a'],
        'debtorUid': manual.actor,
        'creditorUid': 'uid-a',
        'amount': 500,
        'currency': 'EUR',
      });

      await repo.removeManualParticipant(id, manual.id);

      expect(await repo.watchManualParticipants(id).first, isEmpty);
      final entry = (await firestore.doc('economicEntries/e1').get()).data()!;
      expect(entry['debtorUid'], manual.actor);
      expect(entry['amount'], 500);
    });
  });

  group('tickets', () {
    const ticketPath = 'sessions/s1/accounts/a1/tickets/t1';

    setUp(() async {
      await firestore.doc(ticketPath).set({
        'kind': 'manual',
        'grandTotal': 1200,
        'paidByParticipantId': 'p1',
        'merchant': {'name': 'Casa Paco'},
      });
    });

    test('vincular, sobrescribir (máximo un espacio) y desvincular', () async {
      final repo = repoFor('uid-a');
      await repo.linkTicket(ticketPath, 'sp1');
      expect((await firestore.doc(ticketPath).get()).data()!['spaceId'], 'sp1');

      // Máximo un espacio: vincular a otro sobrescribe, nunca duplica.
      await repo.linkTicket(ticketPath, 'sp2');
      expect((await firestore.doc(ticketPath).get()).data()!['spaceId'], 'sp2');

      await repo.unlinkTicket(ticketPath);
      expect((await firestore.doc(ticketPath).get()).data()!['spaceId'], '');
      // Nada más cambió en el ticket (participantes/importes intactos).
      expect(
        (await firestore.doc(ticketPath).get()).data()!['grandTotal'],
        1200,
      );
    });

    test('watchSpaceTickets lista en vivo los tickets del espacio', () async {
      final repo = repoFor('uid-a');
      await repo.linkTicket(ticketPath, 'sp1');
      await firestore.doc('sessions/s2/accounts/a1/tickets/t9').set({
        'grandTotal': 500,
        'paidByParticipantId': 'p1',
        'merchant': {'name': 'Otro'},
        'spaceId': 'otro-espacio',
      });

      final tickets = await repo.watchSpaceTickets('sp1').first;
      expect(tickets.single.merchantName, 'Casa Paco');
      expect(tickets.single.grandTotalCents, 1200);
      expect(tickets.single.sessionId, 's1');
    });

    test(
      'compatibilidad: un ticket sin spaceId no aparece en ningún espacio',
      () async {
        final tickets = await repoFor('uid-a').watchSpaceTickets('sp1').first;
        expect(tickets, isEmpty);
      },
    );
  });
}
