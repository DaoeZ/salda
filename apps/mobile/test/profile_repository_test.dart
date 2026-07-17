import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProfileRepository repo;

  ProfileRepository repoFor(String uid) => ProfileRepository(
    firestore: firestore,
    uid: () => uid,
    random: Random(7), // propuestas reproducibles
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = repoFor('uid-edgar');
  });

  group('createProfile', () {
    test('escribe perfil + claim consistentes y normaliza el username', () async {
      await repo.createProfile(
        displayName: '  Édgar Cantera ',
        username: 'Edgar',
      );

      final profile = await repo.fetchProfile('uid-edgar');
      expect(profile!.displayName, 'Édgar Cantera');
      expect(profile.username, 'edgar');

      final raw =
          (await firestore.doc('profiles/uid-edgar').get()).data()!;
      // displayNameLower alimenta la búsqueda: sin tildes ni mayúsculas.
      expect(raw['displayNameLower'], 'edgar cantera');
      expect(raw['schemaVersion'], 1);

      final claim = (await firestore.doc('usernames/edgar').get()).data()!;
      expect(claim['uid'], 'uid-edgar');
    });

    test('rechaza un username inválido antes de escribir nada', () async {
      await expectLater(
        repo.createProfile(displayName: 'Edgar', username: 'ad'),
        throwsArgumentError,
      );
      expect((await firestore.doc('profiles/uid-edgar').get()).exists, false);
    });
  });

  group('checkUsername', () {
    test('separa inválido, ocupado y disponible', () async {
      await repoFor('uid-alba').createProfile(
        displayName: 'Alba',
        username: 'alba',
      );

      expect(await repo.checkUsername('ab'), isA<UsernameInvalid>());
      expect(await repo.checkUsername('alba'), isA<UsernameTaken>());
      expect(await repo.checkUsername('edgar'), isA<UsernameOk>());
    });

    test('es insensible a mayúsculas: ALBA está ocupado', () async {
      await repoFor('uid-alba').createProfile(
        displayName: 'Alba',
        username: 'alba',
      );
      expect(await repo.checkUsername('ALBA'), isA<UsernameTaken>());
    });

    test('el username propio cuenta como disponible (editar sin cambiarlo)',
        () async {
      await repo.createProfile(displayName: 'Edgar', username: 'edgar');
      expect(await repo.checkUsername('edgar'), isA<UsernameOk>());
    });
  });

  group('suggestUsername', () {
    test('propone la base si está libre', () async {
      expect(await repo.suggestUsername('Edgar Cantera'), 'edgar');
    });

    test('salta a la siguiente propuesta natural si está ocupada', () async {
      await repoFor('uid-otro').createProfile(
        displayName: 'Otro Edgar',
        username: 'edgar',
      );
      final suggested = await repo.suggestUsername('Edgar Cantera');
      expect(suggested, isNot('edgar'));
      // Naturales: edgarNN o edgar_cantera, nunca cadenas aleatorias largas.
      expect(
        suggested,
        anyOf(matches(r'^edgar\d{2,4}$'), 'edgar_cantera', 'edgarcantera'),
      );
    });
  });

  group('updateProfile', () {
    test('cambiar el username libera el claim anterior y reclama el nuevo',
        () async {
      await repo.createProfile(displayName: 'Edgar', username: 'edgar');
      await repo.updateProfile(
        displayName: 'Edgar C.',
        username: 'edgar_cantera',
      );

      final profile = await repo.fetchProfile('uid-edgar');
      expect(profile!.username, 'edgar_cantera');
      expect(profile.displayName, 'Edgar C.');
      expect((await firestore.doc('usernames/edgar').get()).exists, false);
      expect(
        (await firestore.doc('usernames/edgar_cantera').get())
            .data()!['uid'],
        'uid-edgar',
      );
    });

    test('editar solo el nombre visible conserva el claim', () async {
      await repo.createProfile(displayName: 'Edgar', username: 'edgar');
      await repo.updateProfile(displayName: 'Édgar', username: 'edgar');

      expect((await firestore.doc('usernames/edgar').get()).exists, true);
      final raw = (await firestore.doc('profiles/uid-edgar').get()).data()!;
      expect(raw['displayName'], 'Édgar');
      expect(raw['displayNameLower'], 'edgar');
    });
  });

  group('search', () {
    setUp(() async {
      await repoFor('uid-alba').createProfile(
        displayName: 'Alba García',
        username: 'alba',
      );
      await repoFor('uid-albert').createProfile(
        displayName: 'Albert Pla',
        username: 'albert_pla',
      );
      await repoFor('uid-paula').createProfile(
        displayName: 'Paula Alba',
        username: 'paula98',
      );
    });

    test('por prefijo de username', () async {
      final results = await repo.search('alb');
      expect(results.map((p) => p.username), contains('alba'));
      expect(results.map((p) => p.username), contains('albert_pla'));
      expect(results.map((p) => p.username), isNot(contains('paula98')));
    });

    test('por prefijo de nombre visible, sin tildes ni mayúsculas', () async {
      final results = await repo.search('GARCÍA');
      expect(results, isEmpty); // prefijo, no contiene

      final byName = await repo.search('Alba G');
      expect(byName.single.username, 'alba');
    });

    test('acepta @username y quita el arroba', () async {
      final results = await repo.search('@alba');
      expect(results.map((p) => p.username), contains('alba'));
    });

    test('fusiona ambas queries sin duplicar perfiles', () async {
      // 'alba' aparece por username Y por displayNameLower.
      final results = await repo.search('alba');
      expect(
        results.where((p) => p.uid == 'uid-alba').length,
        1,
      );
    });

    test('consulta vacía o solo espacios: sin resultados', () async {
      expect(await repo.search('  '), isEmpty);
      expect(await repo.search('@'), isEmpty);
    });
  });
}
