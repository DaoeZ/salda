import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  GuestIdentityRepository guestRepo(String uid) =>
      GuestIdentityRepository(firestore: firestore, uid: () => uid);

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('identidad de invitado (ADR-034)', () {
    test('elegir nombre crea la identidad sin cuenta ni perfil', () async {
      final repo = guestRepo('guest-uid');
      await repo.setDisplayName('  Alba  ');

      final identity = await repo.watchMine().first;
      expect(identity!.uid, 'guest-uid');
      expect(identity.displayName, 'Alba');

      final raw = (await firestore.doc('guestIdentities/guest-uid').get())
          .data()!;
      expect(raw['schemaVersion'], 1);
      // NO es un perfil público: sin username ni campos de búsqueda.
      expect(raw.containsKey('username'), isFalse);
      expect(raw.containsKey('displayNameLower'), isFalse);
      expect((await firestore.doc('profiles/guest-uid').get()).exists, isFalse);
    });

    test(
      'renombrarse conserva la identidad (y con ella el historial)',
      () async {
        final repo = guestRepo('guest-uid');
        await repo.setDisplayName('Alba');
        final createdAt =
            (await firestore.doc('guestIdentities/guest-uid').get())
                .data()!['createdAt'];

        await repo.setDisplayName('Alba G.');

        final raw = (await firestore.doc('guestIdentities/guest-uid').get())
            .data()!;
        expect(raw['uid'], 'guest-uid'); // MISMA identidad
        expect(raw['displayName'], 'Alba G.');
        expect(raw['createdAt'], createdAt); // el alta no se reescribe
      },
    );

    test('la identidad persiste: el mismo UID recupera su nombre', () async {
      await guestRepo('guest-uid').setDisplayName('Alba');
      // Un "reinicio" es un repositorio nuevo sobre el mismo UID: la sesión
      // anónima de Firebase sobrevive en el dispositivo.
      final afterRestart = await guestRepo('guest-uid').watchMine().first;
      expect(afterRestart!.displayName, 'Alba');
    });

    test('nombre vacío o desmesurado: rechazado', () async {
      final repo = guestRepo('guest-uid');
      await expectLater(repo.setDisplayName('   '), throwsArgumentError);
      await expectLater(repo.setDisplayName('x' * 41), throwsArgumentError);
    });

    test('otro invitado se lee por UID, nunca por búsqueda', () async {
      await guestRepo('otro-guest').setDisplayName('Lucía');
      final seen = await guestRepo('guest-uid').watch('otro-guest').first;
      expect(seen!.displayName, 'Lucía');
    });
  });

  group('participación del invitado en un contexto', () {
    test('al aceptar, su membresía congela nombre y tipo guest', () async {
      final host = SpacesRepository(
        firestore: firestore,
        uid: () => 'host-uid',
        isFullAccount: () => true,
      );
      final spaceId = await host.createSpace('Piso');
      await host.invite(spaceId, 'Piso', 'guest-uid');

      // El invitado NO es cuenta completa, pero SÍ puede aceptar.
      final guest = SpacesRepository(
        firestore: firestore,
        uid: () => 'guest-uid',
        isFullAccount: () => false,
        guestDisplayName: () => 'Alba invitada',
      );
      final invite = (await guest.watchMyInvites().first).single;
      await guest.acceptInvite(invite);

      final member =
          (await firestore.doc('spaces/$spaceId/members/guest-uid').get())
              .data()!;
      expect(member['kind'], 'guest');
      expect(member['displayName'], 'Alba invitada'); // snapshot propio
      final members = await host.watchMembers(spaceId).first;
      final joined = members.firstWhere((m) => m.uid == 'guest-uid');
      expect(joined.isGuest, isTrue);
      expect(joined.displayName, 'Alba invitada');
    });

    test('un invitado NO crea contextos ni invita ni administra', () async {
      final guest = SpacesRepository(
        firestore: firestore,
        uid: () => 'guest-uid',
        isFullAccount: () => false,
        guestDisplayName: () => 'Alba invitada',
      );
      await expectLater(
        guest.createSpace('Mío'),
        throwsA(
          isA<SpaceFailure>().having(
            (f) => f.code,
            'code',
            SpaceFailureCode.accountRequired,
          ),
        ),
      );
      await expectLater(
        guest.createRelationship(toUid: 'x', name: 'Nosotros'),
        throwsA(isA<SpaceFailure>()),
      );
      await expectLater(
        guest.invite('sp1', 'Piso', 'otro'),
        throwsA(isA<SpaceFailure>()),
      );
      // Lanza de forma síncrona: hay que pasar la llamada, no su Future.
      expect(
        () => guest.setGuestsCanCreateExpenses('sp1', true),
        throwsA(isA<SpaceFailure>()),
      );
    });

    test('la política de gastos del anfitrión se lee en el contexto', () async {
      final host = SpacesRepository(
        firestore: firestore,
        uid: () => 'host-uid',
        isFullAccount: () => true,
      );
      final spaceId = await host.createSpace('Piso');

      // Por defecto los invitados NO crean gastos.
      expect(
        (await host.watchSpace(spaceId).first)!.guestsCanCreateExpenses,
        isFalse,
      );
      await host.setGuestsCanCreateExpenses(spaceId, true);
      expect(
        (await host.watchSpace(spaceId).first)!.guestsCanCreateExpenses,
        isTrue,
      );
    });
  });
}
