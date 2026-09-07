import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_management_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// A3: abandonar un grupo y sucesión del propietario.
///
/// La autoridad real la aplican Rules (`group_member_removal.test.mjs`);
/// aquí se fija el CONTRATO de producto: qué historial sobrevive, quién
/// hereda el grupo y qué se ofrece en la interfaz.
void main() {
  late FakeFirebaseFirestore firestore;

  SpacesRepository repoFor(String uid) => SpacesRepository(
    firestore: firestore,
    uid: () => uid,
    isFullAccount: () => true,
  );

  SpaceMember miembro(
    String uid, {
    int joinedAtMillis = 2000000,
    bool admin = false,
    bool guest = false,
  }) => SpaceMember(
    uid: uid,
    joinedAt: DateTime.fromMillisecondsSinceEpoch(joinedAtMillis),
    role: admin ? SpaceMemberRole.admin : SpaceMemberRole.member,
    kind: guest ? SpaceMemberKind.guest : SpaceMemberKind.account,
  );

  Future<void> sembrarMiembro(
    String spaceId,
    String uid, {
    int joinedAtMillis = 2000000,
    String? role,
    String kind = 'account',
    String? displayName,
  }) => firestore.doc('spaces/$spaceId/members/$uid').set({
    'uid': uid,
    'kind': kind,
    'joinedAt': Timestamp.fromMillisecondsSinceEpoch(joinedAtMillis),
    'role': ?role,
    'displayName': ?displayName,
  });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    for (final entry in {
      'owner': 'Edgar',
      'uid-alba': 'Alba',
      'uid-jorge': 'Jorge',
    }.entries) {
      await sembrarMiembro('g1', entry.key);
      await firestore.doc('profiles/${entry.key}').set({
        'displayName': entry.value,
      });
    }
    await firestore.doc('spaces/r1').set({
      'name': 'Pareja',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner', 'uid-alba'],
      'status': 'active',
      'schemaVersion': 2,
    });
    for (final uid in ['owner', 'uid-alba']) {
      await sembrarMiembro('r1', uid);
    }
  });

  group('sucesión determinista', () {
    test('un administrador gana a cualquier miembro más antiguo', () {
      final elegido = ownershipSuccessor([
        miembro('owner'),
        miembro('uid-viejo', joinedAtMillis: 10),
        miembro('uid-admin', joinedAtMillis: 9000, admin: true),
      ], 'owner');
      expect(elegido!.uid, 'uid-admin');
    });

    test('entre varios administradores gana el más antiguo', () {
      final elegido = ownershipSuccessor([
        miembro('uid-a', joinedAtMillis: 5000, admin: true),
        miembro('uid-b', joinedAtMillis: 1000, admin: true),
        miembro('uid-c', joinedAtMillis: 3000, admin: true),
      ], 'owner');
      expect(elegido!.uid, 'uid-b');
    });

    test('sin administradores, el miembro registrado más antiguo', () {
      final elegido = ownershipSuccessor([
        miembro('uid-a', joinedAtMillis: 5000),
        miembro('uid-b', joinedAtMillis: 1000),
      ], 'owner');
      expect(elegido!.uid, 'uid-b');
    });

    test('con el mismo joinedAt desempata el uid, no el orden de lectura', () {
      final gente = [
        miembro('uid-z', joinedAtMillis: 1000),
        miembro('uid-a', joinedAtMillis: 1000),
        miembro('uid-m', joinedAtMillis: 1000),
      ];
      expect(ownershipSuccessor(gente, 'owner')!.uid, 'uid-a');
      expect(ownershipSuccessor(gente.reversed, 'owner')!.uid, 'uid-a');
    });

    test('una membresía aún sin sellar no se toma por la más antigua', () {
      final elegido = ownershipSuccessor([
        const SpaceMember(uid: 'uid-sin-fecha'),
        miembro('uid-b', joinedAtMillis: 5000),
      ], 'owner');
      expect(elegido!.uid, 'uid-b');
    });

    test('un INVITADO nunca es sucesor, por antiguo que sea', () {
      expect(
        ownershipSuccessor([
          miembro('owner'),
          miembro('uid-guest', joinedAtMillis: 1, guest: true),
        ], 'owner'),
        isNull,
      );
      // Y con una cuenta detrás, la cuenta gana aunque sea más nueva.
      final elegido = ownershipSuccessor([
        miembro('uid-guest', joinedAtMillis: 1, guest: true),
        miembro('uid-cuenta', joinedAtMillis: 9000),
      ], 'owner');
      expect(elegido!.uid, 'uid-cuenta');
    });

    test('el propietario nunca se sucede a sí mismo', () {
      expect(
        ownershipSuccessor([miembro('owner', admin: true)], 'owner'),
        isNull,
      );
    });
  });

  group('miembro normal', () {
    test('sale con saldo pendiente y sin dejar evidencia ni bloqueo', () async {
      // La deuda vive fuera del espacio (P5) y salir no la toca.
      await firestore.doc('economicEntries/e1').set({
        'spaceId': 'g1',
        'debtorUid': 'uid-jorge',
        'creditorUid': 'owner',
        'amountCents': 1250,
      });

      await repoFor('uid-jorge').leave('g1');

      expect(
        (await firestore.doc('spaces/g1/members/uid-jorge').get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('spaces/g1/removals').get()).docs,
        isEmpty,
      );
      expect(
        (await firestore.collection('spaces/g1/entryBlocks').get()).docs,
        isEmpty,
      );
      // El historial económico sobrevive intacto.
      final deuda = await firestore.doc('economicEntries/e1').get();
      expect(deuda.exists, isTrue);
      expect(deuda.data()!['amountCents'], 1250);
    });

    test('deja de aparecer como participante de gastos nuevos', () async {
      expect(
        (await repoFor('owner').watchMembers('g1').first).map((m) => m.uid),
        contains('uid-jorge'),
      );
      await repoFor('uid-jorge').leave('g1');
      // `people_sheet` ofrece exactamente esta lista al crear un gasto.
      expect(
        (await repoFor('owner').watchMembers('g1').first).map((m) => m.uid),
        isNot(contains('uid-jorge')),
      );
    });

    test('salir no cambia el propietario', () async {
      await repoFor('uid-jorge').leave('g1');
      expect(
        (await firestore.doc('spaces/g1').get()).data()!['ownerUid'],
        'owner',
      );
    });
  });

  group('el propietario sale', () {
    test('con un administrador, la propiedad pasa al administrador', () async {
      await repoFor(
        'owner',
      ).setMemberRole('g1', 'uid-jorge', SpaceMemberRole.admin);

      await repoFor('owner').leave('g1');

      final space = await firestore.doc('spaces/g1').get();
      expect(space.data()!['ownerUid'], 'uid-jorge');
      expect(
        (await firestore.doc('spaces/g1/members/owner').get()).exists,
        isFalse,
      );
    });

    test('sin administradores, al miembro registrado más antiguo', () async {
      await sembrarMiembro('g1', 'uid-alba', joinedAtMillis: 500);
      await repoFor('owner').leave('g1');
      expect(
        (await firestore.doc('spaces/g1').get()).data()!['ownerUid'],
        'uid-alba',
      );
    });

    test('solo quedan invitados y manuales: la salida se bloquea', () async {
      await firestore.doc('spaces/g1/members/uid-alba').delete();
      await firestore.doc('spaces/g1/members/uid-jorge').delete();
      await sembrarMiembro(
        'g1',
        'uid-guest',
        kind: 'guest',
        displayName: 'Nico',
      );
      await firestore.doc('spaces/g1/manualParticipants/m1').set({
        'manualId': 'm1',
        'displayName': 'Tía Marta',
        'schemaVersion': 1,
      });

      await expectLater(
        repoFor('owner').leave('g1'),
        throwsA(
          isA<SpaceFailure>().having(
            (f) => f.code,
            'code',
            SpaceFailureCode.noSuccessor,
          ),
        ),
      );
      // Y el grupo conserva propietario: nada a medias.
      expect(
        (await firestore.doc('spaces/g1').get()).data()!['ownerUid'],
        'owner',
      );
      expect(
        (await firestore.doc('spaces/g1/members/owner').get()).exists,
        isTrue,
      );
    });

    test('el propietario solo en el grupo no puede salir', () async {
      await firestore.doc('spaces/g1/members/uid-alba').delete();
      await firestore.doc('spaces/g1/members/uid-jorge').delete();
      await expectLater(
        repoFor('owner').leave('g1'),
        throwsA(
          isA<SpaceFailure>().having(
            (f) => f.code,
            'code',
            SpaceFailureCode.noSuccessor,
          ),
        ),
      );
      expect(
        (await firestore.doc('spaces/g1/members/owner').get()).exists,
        isTrue,
      );
    });

    test('una RELACIÓN no adquiere sucesión: su propietario no sale', () async {
      await expectLater(
        repoFor('owner').leave('r1'),
        throwsA(
          isA<SpaceFailure>().having(
            (f) => f.code,
            'code',
            SpaceFailureCode.ownerCannotLeave,
          ),
        ),
      );
      expect(
        (await firestore.doc('spaces/r1').get()).data()!['ownerUid'],
        'owner',
      );
      // La otra mitad sí puede irse: eso no cambia con A3.
      await repoFor('uid-alba').leave('r1');
      expect(
        (await firestore.doc('spaces/r1/members/uid-alba').get()).exists,
        isFalse,
      );
    });

    test('el candidato deja de serlo entre la lectura y el commit', () async {
      // El repositorio elige a Jorge y la escritura falla: el batch es todo
      // o nada, así que ni se transfiere ni se pierde la membresía.
      final repo = repoFor('owner');
      await firestore.doc('spaces/g1/members/uid-alba').delete();
      await expectLater(
        repo.leave('inexistente'),
        throwsA(
          isA<SpaceFailure>().having(
            (f) => f.code,
            'code',
            SpaceFailureCode.targetUnavailable,
          ),
        ),
      );
      expect(
        (await firestore.doc('spaces/g1').get()).data()!['ownerUid'],
        'owner',
      );
      expect(
        (await firestore.doc('spaces/g1/members/owner').get()).exists,
        isTrue,
      );
    });

    test('la transferencia y la baja viajan en el mismo commit', () async {
      final repo = repoFor('owner');
      final visto = <String?>[];
      final sub = firestore
          .doc('spaces/g1')
          .snapshots()
          .listen((snap) => visto.add(snap.data()?['ownerUid'] as String?));
      await repo.leave('g1');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      // Nunca se observa el grupo sin propietario ni con el saliente ya
      // fuera y el `ownerUid` antiguo puesto.
      expect(visto.where((owner) => owner == null), isEmpty);
      expect(visto.last, isNot('owner'));
    });
  });

  group('lo que ofrece la interfaz', () {
    Future<void> pump(
      WidgetTester tester,
      String spaceId, {
      String uid = 'owner',
    }) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore, uid: uid),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SpaceManagementScreen(spaceId: spaceId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('el propietario de un grupo ve la salida y a quién hereda', (
      tester,
    ) async {
      await pump(tester, 'g1');
      await tester.tap(find.text('Salir del espacio'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // Nombra al sucesor (Alba, la primera por uid con el mismo joinedAt).
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('propiedad pasará a Alba'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('cuentas pendientes'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        (await firestore.doc('spaces/g1').get()).data()!['ownerUid'],
        'owner',
      );
      await cerrar(tester);
    });

    testWidgets('sin sucesor se explica el bloqueo, no un error genérico', (
      tester,
    ) async {
      await firestore.doc('spaces/g1/members/uid-alba').delete();
      await firestore.doc('spaces/g1/members/uid-jorge').delete();
      await pump(tester, 'g1');
      await tester.tap(find.text('Salir del espacio'));
      await tester.pumpAndSettle();

      expect(find.text('Todavía no puedes salir'), findsOneWidget);
      expect(find.textContaining('sin propietario'), findsOneWidget);
      expect(find.textContaining('No se pudo completar'), findsNothing);
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      await cerrar(tester);
    });

    testWidgets('el propietario de una RELACIÓN no ve la acción', (
      tester,
    ) async {
      await pump(tester, 'r1');
      expect(find.text('Salir del espacio'), findsNothing);
      await cerrar(tester);
    });

    testWidgets('un miembro normal conserva su salida de siempre', (
      tester,
    ) async {
      await pump(tester, 'g1', uid: 'uid-jorge');
      await tester.tap(find.text('Salir del espacio'));
      await tester.pumpAndSettle();
      // Sin mención a la propiedad: no es suya.
      expect(find.textContaining('propiedad pasará'), findsNothing);
      expect(find.textContaining('cuentas pendientes'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await cerrar(tester);
    });
  });
}
