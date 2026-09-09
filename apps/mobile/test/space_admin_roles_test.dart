import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_management_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// A11a: administradores de GRUPO. La interfaz solo decide qué se ofrece;
/// la autoridad la aplican Rules (backend/firestore/test/rules.test.mjs).
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
      });
      await firestore.doc('profiles/${entry.key}').set({
        'displayName': entry.value,
      });
    }
    // Sin cuenta: participa en los gastos pero no es miembro ni administra.
    await firestore.doc('spaces/g1/manualParticipants/m-tete').set({
      'id': 'm-tete',
      'displayName': 'Tete',
      'createdByUid': 'owner',
      'schemaVersion': 1,
    });
    // Invitado: miembro sin cuenta pública, tampoco administrable.
    await firestore.doc('spaces/g1/members/uid-guest').set({
      'uid': 'uid-guest',
      'kind': 'guest',
      'displayName': 'Vecina',
    });
  });

  testWidgets('la lista distingue propietario, admin, miembro y sin cuenta', (
    tester,
  ) async {
    await repoFor(
      'owner',
    ).setMemberRole('g1', 'uid-alba', SpaceMemberRole.admin);
    await pump(tester, 'g1');

    expect(find.text('Edgar'), findsOneWidget);
    expect(find.text('Propietario'), findsOneWidget);
    expect(find.text('Alba'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    // Jorge es miembro normal: aparece SIN etiqueta.
    expect(find.text('Jorge'), findsOneWidget);
    expect(find.text('Miembro'), findsNothing);
    expect(find.text('Tete'), findsOneWidget);
    expect(find.textContaining('Sin cuenta'), findsOneWidget);
    expect(find.text('Invitado'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('el propietario nombra administrador y el cambio persiste', (
    tester,
  ) async {
    await pump(tester, 'g1');

    final fila = find.ancestor(
      of: find.text('Jorge'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: fila, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombrar administrador').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Nombrar administrador'),
    );
    await tester.pumpAndSettle();

    expect(
      (await firestore.doc('spaces/g1/members/uid-jorge').get())
          .data()!['role'],
      'admin',
    );
    // Y se refleja sin recargar nada a mano.
    expect(find.text('Administrador'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('el propietario retira el rol sin expulsar a nadie', (
    tester,
  ) async {
    await repoFor(
      'owner',
    ).setMemberRole('g1', 'uid-alba', SpaceMemberRole.admin);
    await pump(tester, 'g1');

    final fila = find.ancestor(
      of: find.text('Alba'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: fila, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirar administrador').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Retirar administrador'),
    );
    await tester.pumpAndSettle();

    final member = await firestore.doc('spaces/g1/members/uid-alba').get();
    expect(member.data()!['role'], 'member');
    expect(member.exists, true);
    expect(find.text('Administrador'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('a un INVITADO no se le ofrece administrar', (tester) async {
    await pump(tester, 'g1');
    final fila = find.ancestor(
      of: find.text('Vecina'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: fila, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nombrar administrador'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('una persona SIN cuenta no tiene acción de administrar', (
    tester,
  ) async {
    await pump(tester, 'g1');
    final fila = find.ancestor(
      of: find.text('Tete'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: fila, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nombrar administrador'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('el propietario no puede degradarse a sí mismo', (tester) async {
    await pump(tester, 'g1');
    final fila = find.ancestor(
      of: find.text('Edgar'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: fila, matching: find.byType(PopupMenuButton<String>)),
      findsNothing,
    );
    await cerrar(tester);
  });

  // A11d: un administrador SÍ tiene una acción sobre los miembros normales
  // —expulsarlos—, pero sigue sin poder tocar roles ni la propiedad.
  testWidgets('un administrador expulsa, pero no cambia roles ni transfiere', (
    tester,
  ) async {
    await repoFor(
      'owner',
    ).setMemberRole('g1', 'uid-alba', SpaceMemberRole.admin);
    await pump(tester, 'g1', uid: 'uid-alba');

    expect(find.text('Propietario'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);

    final fila = find.ancestor(
      of: find.text('Jorge'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: fila, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expulsar del grupo'), findsOneWidget);
    expect(find.text('Nombrar administrador'), findsNothing);
    expect(find.text('Transferir propiedad'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('un miembro normal tampoco recibe controles de rol', (
    tester,
  ) async {
    await pump(tester, 'g1', uid: 'uid-jorge');
    expect(find.text('Propietario'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await cerrar(tester);
  });

  group('repositorio', () {
    test('varios administradores conviven en el mismo grupo', () async {
      final repo = repoFor('owner');
      await repo.setMemberRole('g1', 'uid-alba', SpaceMemberRole.admin);
      await repo.setMemberRole('g1', 'uid-jorge', SpaceMemberRole.admin);

      final members = await repo.watchMembers('g1').first;
      expect(members.where((m) => m.isAdmin).map((m) => m.uid).toSet(), {
        'uid-alba',
        'uid-jorge',
      });
    });

    test('nadie se nombra administrador a sí mismo', () async {
      expect(
        () => repoFor(
          'owner',
        ).setMemberRole('g1', 'owner', SpaceMemberRole.admin),
        throwsA(
          isA<SpaceFailure>().having(
            (e) => e.code,
            'code',
            SpaceFailureCode.notAllowed,
          ),
        ),
      );
    });

    test('una relación no expone gestión de roles', () async {
      await firestore.doc('spaces/rel').set({
        'name': 'Ana y yo',
        'ownerUid': 'owner',
        'kind': 'relationship',
        'relationshipUids': ['owner', 'uid-ana'],
        'status': 'active',
        'schemaVersion': 2,
      });
      await firestore.doc('spaces/rel/members/owner').set({'uid': 'owner'});
      await firestore.doc('spaces/rel/members/uid-ana').set({'uid': 'uid-ana'});

      final members = await repoFor('owner').watchMembers('rel').first;
      expect(members.every((m) => m.role == SpaceMemberRole.member), true);
    });
  });

  testWidgets('la gestión de una relación no habla de propietario ni admin', (
    tester,
  ) async {
    await firestore.doc('spaces/rel').set({
      'name': 'Ana y yo',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner', 'uid-ana'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/rel/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/rel/members/uid-ana').set({'uid': 'uid-ana'});
    await firestore.doc('profiles/uid-ana').set({'displayName': 'Ana'});

    await pump(tester, 'rel');
    expect(find.text('Propietario'), findsNothing);
    expect(find.text('Administrador'), findsNothing);
    expect(find.text('Nombrar administrador'), findsNothing);
    await cerrar(tester);
  });
}
