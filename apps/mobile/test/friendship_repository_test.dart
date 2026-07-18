import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/friends/data/friendship_repository.dart';
import 'package:salda_mobile/features/friends/domain/friendship.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  FriendshipRepository repoFor(String uid, {bool fullAccount = true}) =>
      FriendshipRepository(
        firestore: firestore,
        uid: () => uid,
        isFullAccount: () => fullAccount,
      );

  Future<void> seedProfile(String uid, String username) =>
      firestore.doc('profiles/$uid').set({
        'displayName': username,
        'displayNameLower': username,
        'username': username,
        'createdAt': DateTime(2026),
        'updatedAt': DateTime(2026),
        'schemaVersion': 1,
      });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await seedProfile('uid-a', 'alba');
    await seedProfile('uid-b', 'bea');
    await seedProfile('uid-c', 'carla');
  });

  group('identidad canónica', () {
    test('A/B y B/A producen el mismo ID canónico y miembros ordenados', () {
      final first = canonicalFriendshipId('uid-b', 'uid-a');
      final second = canonicalFriendshipId('uid-a', 'uid-b');
      expect(first, second);
      expect(first, matches(RegExp(r'^[0-9a-f]+$')));
      expect(canonicalFriendshipMembers('uid-b', 'uid-a'), ['uid-a', 'uid-b']);
    });

    test('rechaza relación consigo mismo, UID vacío o demasiado largo', () {
      expect(
        () => canonicalFriendshipId('uid-a', 'uid-a'),
        throwsArgumentError,
      );
      expect(() => canonicalFriendshipId('', 'uid-a'), throwsArgumentError);
      expect(
        () => canonicalFriendshipId(List.filled(129, 'x').join(), 'uid-a'),
        throwsArgumentError,
      );
    });

    test('relationFor y otherUid dependen solo de UID y estado', () {
      const pending = Friendship(
        id: 'id',
        memberUids: ['uid-a', 'uid-b'],
        requesterUid: 'uid-a',
        receiverUid: 'uid-b',
        status: FriendshipStatus.pending,
      );
      expect(pending.relationFor('uid-a'), FriendshipRelationState.outgoing);
      expect(pending.relationFor('uid-b'), FriendshipRelationState.incoming);
      expect(pending.relationFor('uid-c'), FriendshipRelationState.none);
      expect(pending.otherUid('uid-a'), 'uid-b');
      expect(() => pending.otherUid('uid-c'), throwsArgumentError);
    });
  });

  group('transacciones de amistad', () {
    test('envía una solicitud y repetirla es idempotente', () async {
      final repo = repoFor('uid-a');
      await repo.sendRequest('uid-b');
      await repo.sendRequest('uid-b');

      final all = await firestore.collection('friendships').get();
      expect(all.docs, hasLength(1));
      expect(all.docs.single.data()['status'], 'pending');
      expect(all.docs.single.data()['requesterUid'], 'uid-a');
    });

    test('solicitudes cruzadas convergen en una amistad', () async {
      await repoFor('uid-a').sendRequest('uid-b');
      await repoFor('uid-b').sendRequest('uid-a');

      final all = await firestore.collection('friendships').get();
      expect(all.docs, hasLength(1));
      expect(all.docs.single.data()['status'], 'friends');
      expect(all.docs.single.data()['acceptedAt'], isNotNull);
    });

    test('dos envíos simultáneos dejan como máximo un documento', () async {
      await Future.wait([
        repoFor('uid-a').sendRequest('uid-b'),
        repoFor('uid-a').sendRequest('uid-b'),
      ]);
      final all = await firestore.collection('friendships').get();
      expect(all.docs, hasLength(1));
    });

    test('solo receptor acepta o rechaza y solo emisor cancela', () async {
      final sender = repoFor('uid-a');
      final receiver = repoFor('uid-b');
      await sender.sendRequest('uid-b');
      await expectLater(
        sender.acceptRequest('uid-b'),
        throwsA(isA<FriendshipFailure>()),
      );
      await expectLater(
        receiver.cancelRequest('uid-a'),
        throwsA(isA<FriendshipFailure>()),
      );
      await receiver.rejectRequest('uid-a');
      expect((await firestore.collection('friendships').get()).docs, isEmpty);

      await sender.sendRequest('uid-b');
      await sender.cancelRequest('uid-b');
      expect((await firestore.collection('friendships').get()).docs, isEmpty);
    });

    test(
      'aceptar y eliminar son idempotentes; después se puede reenviar',
      () async {
        final sender = repoFor('uid-a');
        final receiver = repoFor('uid-b');
        await sender.sendRequest('uid-b');
        await receiver.acceptRequest('uid-a');
        await receiver.acceptRequest('uid-a');
        await sender.removeFriend('uid-b');
        await sender.removeFriend('uid-b');
        await receiver.sendRequest('uid-a');

        final all = await firestore.collection('friendships').get();
        expect(all.docs, hasLength(1));
        expect(all.docs.single.data()['status'], 'pending');
        expect(all.docs.single.data()['requesterUid'], 'uid-b');
      },
    );

    test('cambiar username no altera la relación basada en UID', () async {
      await repoFor('uid-a').sendRequest('uid-b');
      await firestore.doc('profiles/uid-b').update({'username': 'bea_nueva'});
      final relationship = (await repoFor('uid-a').watchAll().first).single;
      expect(relationship.otherUid('uid-a'), 'uid-b');
    });

    test(
      'watchAll refleja recibidas, enviadas y amigos en tiempo real',
      () async {
        final repoA = repoFor('uid-a');
        final emissions = <List<Friendship>>[];
        final subscription = repoA.watchAll().listen(emissions.add);
        addTearDown(subscription.cancel);
        await repoA.sendRequest('uid-b');
        await repoFor('uid-c').sendRequest('uid-a');
        await repoFor('uid-a').sendRequest('uid-c'); // cruzada → friends
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final latest = emissions.last;
        expect(latest, hasLength(2));
        expect(latest.map((item) => item.relationFor('uid-a')).toSet(), {
          FriendshipRelationState.outgoing,
          FriendshipRelationState.friends,
        });
      },
    );

    test(
      'cuenta no completa, auto-solicitud y perfiles ausentes se rechazan',
      () async {
        await expectLater(
          repoFor('uid-a', fullAccount: false).sendRequest('uid-b'),
          throwsA(isA<FriendshipFailure>()),
        );
        await expectLater(
          repoFor('uid-a').sendRequest('uid-a'),
          throwsA(isA<FriendshipFailure>()),
        );
        await expectLater(
          repoFor('uid-a').sendRequest('missing'),
          throwsA(isA<FriendshipFailure>()),
        );
      },
    );
  });
  group('errores operativos', () {
    test('refresca el token antes de crear una solicitud', () async {
      var refreshes = 0;
      final repository = FriendshipRepository(
        firestore: firestore,
        uid: () => 'uid-a',
        isFullAccount: () => true,
        refreshAccount: () async {
          refreshes++;
          return true;
        },
      );

      await repository.sendRequest('uid-b');

      expect(refreshes, 1);
    });

    test('bloquea una escritura si el token sigue sin verificar', () async {
      final repository = FriendshipRepository(
        firestore: firestore,
        uid: () => 'uid-a',
        isFullAccount: () => true,
        refreshAccount: () async => false,
      );

      await expectLater(
        repository.sendRequest('uid-b'),
        throwsA(
          isA<FriendshipFailure>().having(
            (failure) => failure.code,
            'code',
            FriendshipFailureCode.unverifiedAccount,
          ),
        ),
      );
    });

    test('permission-denied conserva el diagnóstico real', () {
      final failure = mapFriendshipFirebaseFailure(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      expect(failure.code, FriendshipFailureCode.permissionDenied);
      expect(failure.technicalCode, 'permission-denied');
    });

    test('unavailable se presenta como red y no como permisos', () {
      final failure = mapFriendshipFirebaseFailure(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );

      expect(failure.code, FriendshipFailureCode.network);
    });
  });
}
