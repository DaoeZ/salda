import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/application/session_providers.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_access_revoked.dart';
import 'package:salda_mobile/features/spaces/presentation/space_management_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// A11d: expulsión administrativa, readmisión y derecho histórico, en la app.
/// La autoridad real la aplican Rules (`group_member_removal.test.mjs`);
/// aquí se fija el CONTRATO del repositorio y lo que ofrece la interfaz.
void main() {
  late FakeFirebaseFirestore firestore;

  SpacesRepository repoFor(String uid) => SpacesRepository(
    firestore: firestore,
    uid: () => uid,
    isFullAccount: () => true,
  );

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
      await firestore.doc('spaces/g1/members/${entry.key}').set({
        'uid': entry.key,
        'kind': 'account',
        'joinedAt': Timestamp.fromMillisecondsSinceEpoch(2000000),
      });
      await firestore.doc('profiles/${entry.key}').set({
        'displayName': entry.value,
      });
    }
    // Relación: nunca tiene expulsión administrativa.
    await firestore.doc('spaces/r1').set({
      'name': 'Pareja',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner', 'uid-alba'],
      'status': 'active',
      'schemaVersion': 2,
    });
    for (final uid in ['owner', 'uid-alba']) {
      await firestore.doc('spaces/r1/members/$uid').set({
        'uid': uid,
        'kind': 'account',
        'joinedAt': Timestamp.fromMillisecondsSinceEpoch(2000000),
      });
    }
  });

  group('expulsión atómica', () {
    test('escribe evidencia del ciclo, bloqueo y borra la membresía', () async {
      await repoFor('owner').removeMember('g1', 'uid-jorge');

      final ciclo = membershipCycleId(
        'uid-jorge',
        Timestamp.fromMillisecondsSinceEpoch(2000000),
      );
      final evidencia = await firestore.doc('spaces/g1/removals/$ciclo').get();
      final bloqueo = await firestore
          .doc('spaces/g1/entryBlocks/uid-jorge')
          .get();
      final miembro = await firestore.doc('spaces/g1/members/uid-jorge').get();

      expect(evidencia.exists, isTrue);
      expect(evidencia.data()!['uid'], 'uid-jorge');
      expect(evidencia.data()!['removedBy'], 'owner');
      expect(
        (evidencia.data()!['membershipJoinedAt'] as Timestamp)
            .millisecondsSinceEpoch,
        2000000,
      );
      expect(bloqueo.exists, isTrue);
      expect(miembro.exists, isFalse);
    });

    test('la evidencia identifica el CICLO, no solo a la persona', () async {
      final ciclo = membershipCycleId(
        'uid-jorge',
        Timestamp.fromMillisecondsSinceEpoch(2000000),
      );
      expect(ciclo, 'uid-jorge_2000000');
      expect(
        membershipCycleId(
          'uid-jorge',
          Timestamp.fromMillisecondsSinceEpoch(9000000),
        ),
        isNot(ciclo),
      );
    });

    test('no deja marcador `removedBy` sobre la membresía', () async {
      await repoFor('owner').removeMember('g1', 'uid-jorge');
      // El protocolo antiguo escribía en el doc que iba a borrar; el trigger
      // recibía el cambio NETO y toda expulsión salía como salida voluntaria.
      final miembro = await firestore.doc('spaces/g1/members/uid-jorge').get();
      expect(miembro.exists, isFalse);
    });

    test('expulsar a quien ya no está no inventa evidencia', () async {
      await repoFor('owner').removeMember('g1', 'uid-jorge');
      await expectLater(
        repoFor('owner').removeMember('g1', 'uid-jorge'),
        throwsA(isA<SpaceFailure>()),
      );
    });

    test('salir NO deja evidencia ni bloqueo', () async {
      await repoFor('uid-jorge').leave('g1');
      final bloqueo = await firestore.collection('spaces/g1/entryBlocks').get();
      final evidencias = await firestore.collection('spaces/g1/removals').get();
      expect(bloqueo.docs, isEmpty);
      expect(evidencias.docs, isEmpty);
    });
  });

  group('readmisión', () {
    test(
      'vuelve con joinedAt nuevo, sin rol y levantando el bloqueo',
      () async {
        final owner = repoFor('owner');
        await owner.setMemberRole('g1', 'uid-jorge', SpaceMemberRole.admin);
        await owner.removeMember('g1', 'uid-jorge');

        await owner.invite('g1', 'Piso', 'uid-jorge');
        final invitacion = await repoFor('uid-jorge').watchMyInvites().first;
        await repoFor('uid-jorge').acceptInvite(invitacion.single);

        final miembro = await firestore
            .doc('spaces/g1/members/uid-jorge')
            .get();
        expect(miembro.exists, isTrue);
        // Un antiguo administrador NO recupera su rol por volver.
        expect(miembro.data()!['role'], isNull);
        expect(
          (miembro.data()!['joinedAt'] as Timestamp).millisecondsSinceEpoch,
          greaterThan(2000000),
        );
        // El bloqueo se levanta…
        expect(
          (await firestore.doc('spaces/g1/entryBlocks/uid-jorge').get()).exists,
          isFalse,
        );
        // …y la evidencia histórica de la expulsión permanece.
        final evidencias = await firestore
            .collection('spaces/g1/removals')
            .get();
        expect(evidencias.docs, hasLength(1));
      },
    );

    test('reinvitar a un expulsado renueva la fecha de la decisión', () async {
      final owner = repoFor('owner');
      await owner.invite('g1', 'Piso', 'uid-nuevo');
      final primera = await firestore.doc('spaceInvites/g1_uid-nuevo').get();
      final antes = primera.data()!['createdAt'] as Timestamp;

      // Se acepta, se expulsa y se vuelve a invitar sobre el mismo doc.
      await firestore.doc('spaceInvites/g1_uid-nuevo').update({
        'status': 'accepted',
      });
      await owner.invite('g1', 'Piso', 'uid-nuevo');

      final segunda = await firestore.doc('spaceInvites/g1_uid-nuevo').get();
      expect(segunda.data()!['status'], 'pending');
      expect(
        (segunda.data()!['createdAt'] as Timestamp).compareTo(antes),
        greaterThanOrEqualTo(0),
      );
    });

    test('desaparece de Mis contextos y vuelve al readmitir', () async {
      final jorge = repoFor('uid-jorge');
      expect(
        (await jorge.watchMySpaces().first).map((s) => s.id),
        contains('g1'),
      );

      await repoFor('owner').removeMember('g1', 'uid-jorge');
      expect(
        (await jorge.watchMySpaces().first).map((s) => s.id),
        isNot(contains('g1')),
      );

      await repoFor('owner').invite('g1', 'Piso', 'uid-jorge');
      await jorge.acceptInvite((await jorge.watchMyInvites().first).single);
      expect(
        (await jorge.watchMySpaces().first).map((s) => s.id),
        contains('g1'),
      );
    });
  });

  group('autoridad ofrecida por la interfaz', () {
    testWidgets('el propietario puede expulsar a un miembro', (tester) async {
      await pump(tester, 'g1');
      final fila = find.ancestor(
        of: find.text('Jorge'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: fila,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expulsar del grupo'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('la confirmación explica que las deudas no desaparecen', (
      tester,
    ) async {
      await pump(tester, 'g1');
      final fila = find.ancestor(
        of: find.text('Jorge'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: fila,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expulsar del grupo').last);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('deudas y pagos'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      // Cancelar no expulsa a nadie.
      expect(
        (await firestore.doc('spaces/g1/members/uid-jorge').get()).exists,
        isTrue,
      );
      await cerrar(tester);
    });

    testWidgets('un miembro normal no recibe la acción', (tester) async {
      await pump(tester, 'g1', uid: 'uid-jorge');
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await cerrar(tester);
    });

    testWidgets('una RELACIÓN no ofrece expulsión administrativa', (
      tester,
    ) async {
      await pump(tester, 'r1');
      expect(find.text('Expulsar del grupo'), findsNothing);
      await cerrar(tester);
    });

    test('el provider de autoridad refleja la matriz de Rules', () async {
      await repoFor(
        'owner',
      ).setMemberRole('g1', 'uid-alba', SpaceMemberRole.admin);

      Future<bool> puede(String actor, String objetivo, String spaceId) async {
        final container = ProviderContainer(
          overrides: loggedInOverrides(firestore: firestore, uid: actor),
        );
        addTearDown(container.dispose);
        // Los providers son autoDispose y de stream: hay que mantenerlos
        // suscritos mientras se resuelven, o se tiran entre lectura y lectura.
        final vivos = [
          container.listen(spaceProvider(spaceId), (_, _) {}),
          container.listen(spaceMembersProvider(spaceId), (_, _) {}),
        ];
        await container.read(spaceProvider(spaceId).future);
        await container.read(spaceMembersProvider(spaceId).future);
        final resultado = container.read(
          canRemoveMemberProvider((spaceId: spaceId, memberUid: objetivo)),
        );
        for (final suscripcion in vivos) {
          suscripcion.close();
        }
        return resultado;
      }

      expect(await puede('owner', 'uid-jorge', 'g1'), isTrue);
      expect(await puede('owner', 'uid-alba', 'g1'), isTrue); // admin
      expect(await puede('uid-alba', 'uid-jorge', 'g1'), isTrue);
      expect(await puede('uid-alba', 'owner', 'g1'), isFalse);
      expect(await puede('uid-alba', 'uid-alba', 'g1'), isFalse);
      expect(await puede('uid-jorge', 'uid-alba', 'g1'), isFalse);
      expect(await puede('owner', 'owner', 'g1'), isFalse);
      // Relación: nadie, ni el propietario.
      expect(await puede('owner', 'uid-alba', 'r1'), isFalse);
    });

    test('un administrador no puede expulsar a otro administrador', () async {
      final owner = repoFor('owner');
      await owner.setMemberRole('g1', 'uid-alba', SpaceMemberRole.admin);
      await owner.setMemberRole('g1', 'uid-jorge', SpaceMemberRole.admin);

      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore, uid: 'uid-alba'),
      );
      addTearDown(container.dispose);
      final vivos = [
        container.listen(spaceProvider('g1'), (_, _) {}),
        container.listen(spaceMembersProvider('g1'), (_, _) {}),
      ];
      await container.read(spaceProvider('g1').future);
      await container.read(spaceMembersProvider('g1').future);
      expect(
        container.read(
          canRemoveMemberProvider((spaceId: 'g1', memberUid: 'uid-jorge')),
        ),
        isFalse,
      );
      for (final suscripcion in vivos) {
        suscripcion.close();
      }
    });
  });

  group('perder el acceso con la pantalla abierta', () {
    test('un permission-denied se reconoce como acceso revocado', () {
      expect(
        isSpaceAccessRevoked(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        isTrue,
      );
      // Un fallo de red NO: ese sí se reintenta.
      expect(
        isSpaceAccessRevoked(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
      expect(isSpaceAccessRevoked(Exception('otra cosa')), isFalse);
    });

    testWidgets('la gestión muestra el estado, no un error reintentable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          ...loggedInOverrides(firestore: firestore, uid: 'uid-jorge'),
          spaceProvider('g1').overrideWith(
            (ref) => Stream<Space?>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SpaceManagementScreen(spaceId: 'g1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SpaceAccessRevokedScreen), findsOneWidget);
      expect(find.text('Ya no tienes acceso a este grupo'), findsOneWidget);
      expect(find.textContaining('deudas y pagos'), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('navegación económica histórica', () {
    setUp(() async {
      await firestore.doc('sessions/s1').set({
        'ownerUid': 'uid-alba',
        'kind': 'single',
        'status': 'open',
        'spaceId': 'g1',
        'contextModelVersion': 1,
        'shareCode': 'SECRET-CODE-16CH',
      });
      await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
        'kind': 'manual',
        'grandTotal': 3000,
        'paidByParticipantId': 'p1',
        'merchant': {'name': 'Súper'},
        'spaceId': 'g1',
        'contextModelVersion': 1,
      });
      await firestore.doc('sessions/s1/ticketEntitlements/t1_uid-jorge').set({
        'uid': 'uid-jorge',
        'ticketId': 't1',
        'accountId': 'a1',
        'participantNames': {'p1': 'Alba', 'p2': 'Jorge'},
        'schemaVersion': 1,
      });
    });

    test('abre el ticket por GET determinista, sin listar cuentas', () async {
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore, uid: 'uid-jorge'),
      );
      addTearDown(container.dispose);

      final historico = await container.read(
        historicTicketProvider((sid: 's1', tid: 't1')).future,
      );
      expect(historico, isNotNull);
      expect(historico!.ticket.id, 't1');
      expect(historico.ticket.merchantName, 'Súper');
      // Los nombres del reparto viajan con el derecho: no hace falta leer
      // los participantes de la sesión.
      expect(historico.participantNames['p2'], 'Jorge');
    });

    test('sin derecho no resuelve nada por esa vía', () async {
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore, uid: 'uid-ajeno'),
      );
      addTearDown(container.dispose);
      expect(
        await container.read(
          historicTicketProvider((sid: 's1', tid: 't1')).future,
        ),
        isNull,
      );
    });
  });
}
