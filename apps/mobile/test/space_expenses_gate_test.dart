import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// BUG-6 en pantalla: el botón de crear un gasto depende de cuántas PERSONAS
/// hay, no de cuántas cuentas. Un grupo de Edgar + Pablo (sin app) reparte.
void main() {
  late FakeFirebaseFirestore firestore;

  Future<void> grupo(String id, {int manuales = 0, int cuentas = 1}) async {
    await firestore.doc('spaces/$id').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/$id/members/owner').set({'uid': 'owner'});
    for (var i = 1; i < cuentas; i++) {
      await firestore.doc('spaces/$id/members/uid-$i').set({'uid': 'uid-$i'});
    }
    for (var i = 0; i < manuales; i++) {
      await firestore.doc('spaces/$id/manualParticipants/m$i').set({
        'manualId': 'm$i',
        'displayName': 'Pablo$i',
        'linkedUid': null,
        'createdByUid': 'owner',
        'schemaVersion': 1,
      });
    }
  }

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> pump(WidgetTester tester, String spaceId) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SpaceDetailScreen(spaceId: spaceId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// El detalle deja temporizadores vivos (chat, actividad) y el binding los
  /// revisa antes de los `addTearDown`.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  bool habilitado(WidgetTester tester) =>
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed !=
      null;

  final falta = find.textContaining('antes de crear tickets');

  testWidgets('grupo con solo el propietario: botón bloqueado y explicación', (
    tester,
  ) async {
    await grupo('g1');
    await pump(tester, 'g1');
    expect(habilitado(tester), isFalse);
    expect(falta, findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('grupo ACCOUNT + MANUAL: botón habilitado, sin aviso', (
    tester,
  ) async {
    await grupo('g2', manuales: 1);
    await pump(tester, 'g2');
    expect(habilitado(tester), isTrue);
    expect(falta, findsNothing);
    // Y la persona sin cuenta se ve como parte del grupo.
    expect(find.text('Pablo0'), findsWidgets);
    await cerrar(tester);
  });

  testWidgets('grupo con dos cuentas: sigue funcionando (sin regresión)', (
    tester,
  ) async {
    await grupo('g3', cuentas: 2);
    await pump(tester, 'g3');
    expect(habilitado(tester), isTrue);
    await cerrar(tester);
  });

  testWidgets('quitar el MANUAL vuelve a bloquear el botón', (tester) async {
    await grupo('g4', manuales: 1);
    await pump(tester, 'g4');
    expect(habilitado(tester), isTrue);
    // El estado sigue a los datos en vivo: no hace falta reabrir la pantalla.
    await firestore.doc('spaces/g4/manualParticipants/m0').delete();
    await tester.pumpAndSettle();
    expect(habilitado(tester), isFalse);
    expect(falta, findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('MANUAL vinculado a un miembro no cuenta dos veces', (
    tester,
  ) async {
    // Pablo se registró y entró: Edgar + Pablo son DOS personas. El grupo
    // opera, pero la identidad no se ha partido en dos.
    await grupo('g5', manuales: 1, cuentas: 2);
    await firestore.doc('spaces/g5/manualParticipants/m0').update({
      'linkedUid': 'uid-1',
    });
    await pump(tester, 'g5');
    expect(habilitado(tester), isTrue);
    await cerrar(tester);
  });

  testWidgets('mientras se cuenta la gente no se afirma que falte', (
    tester,
  ) async {
    // Con las listas aún vacías el resultado sería "no operativo": pintarlo
    // haría parpadear un aviso falso.
    await grupo('g6', manuales: 1);
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'g6'),
        ),
      ),
    );
    await tester.pump();
    expect(falta, findsNothing);
    await tester.pumpAndSettle();
    expect(falta, findsNothing);
    await cerrar(tester);
  });

  testWidgets('relación v2 pendiente sigue bloqueada', (tester) async {
    await firestore.doc('spaces/rel2').set({
      'name': 'Ana',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner', 'uid-ana'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/rel2/members/owner').set({'uid': 'owner'});
    await pump(tester, 'rel2');
    expect(habilitado(tester), isFalse);
    await cerrar(tester);
  });

  testWidgets('relación v3 ACCOUNT + MANUAL opera', (tester) async {
    await firestore.doc('spaces/rel3').set({
      'name': 'Pablo',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner'],
      'relationshipManualId': 'm-pablo',
      'status': 'active',
      'schemaVersion': 3,
    });
    await firestore.doc('spaces/rel3/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/rel3/manualParticipants/m-pablo').set({
      'manualId': 'm-pablo',
      'displayName': 'Pablo',
      'linkedUid': null,
      'createdByUid': 'owner',
      'schemaVersion': 1,
    });
    await pump(tester, 'rel3');
    expect(habilitado(tester), isTrue);
    await cerrar(tester);
  });
}
