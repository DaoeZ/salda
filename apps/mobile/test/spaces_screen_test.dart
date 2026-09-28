import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/spaces_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

Future<(FakeFirebaseFirestore, ProviderContainer)> _pump(
  WidgetTester tester, {
  FakeFirebaseFirestore? firestore,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = firestore ?? FakeFirebaseFirestore();
  final container = ProviderContainer(
    overrides: [...loggedInOverrides(firestore: fake)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SpacesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, container);
}

/// La lista lee saldos en vivo: hay que desmontar DENTRO de la prueba, antes
/// de que el binding compruebe los temporizadores pendientes.
Future<void> _cerrar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('estado vacío con invitación a crear', (tester) async {
    await _pump(tester);
    expect(find.text('Todavía no tienes espacios'), findsOneWidget);
    // La acción de crear vive SOLO en el botón principal: repetirla dentro
    // del estado vacío era la misma acción dos veces en la misma pantalla.
    expect(find.text('Crear espacio'), findsOneWidget);
    await _cerrar(tester);
  });

  testWidgets('lista activos, archivados aparte y badge de propietario', (
    tester,
  ) async {
    final fake = FakeFirebaseFirestore();
    final repo = SpacesRepository(
      firestore: fake,
      uid: () => 'owner',
      isFullAccount: () => true,
    );
    await repo.createSpace('Viaje a Lisboa');
    final archivedId = await repo.createSpace('Piso antiguo');
    await repo.setStatus(archivedId, SpaceStatus.archived);

    await _pump(tester, firestore: fake);

    expect(find.text('Viaje a Lisboa'), findsOneWidget);
    // El rótulo «Propietario» ya no se repite en cada fila: lo eres en casi
    // todas, así que no distinguía nada y competía con el saldo. La
    // propiedad se gestiona donde importa, en el detalle.
    expect(find.text('Propietario'), findsNothing);
    // Los archivados van en su propia sección, siempre visible: plegarlos
    // escondía espacios que el usuario sí busca.
    expect(find.text('ARCHIVADOS (1)'), findsOneWidget);
    expect(find.text('Piso antiguo'), findsOneWidget);
    await _cerrar(tester);
  });

  testWidgets('una invitación recibida se acepta desde la lista', (
    tester,
  ) async {
    final fake = FakeFirebaseFirestore();
    final inviter = SpacesRepository(
      firestore: fake,
      uid: () => 'uid-otro',
      isFullAccount: () => true,
    );
    final spaceId = await inviter.createSpace('Peña del bar');
    await inviter.invite(spaceId, 'Peña del bar', 'owner');

    final (f, container) = await _pump(tester, firestore: fake);

    expect(find.textContaining('Peña del bar'), findsOneWidget);
    await tester.tap(find.text('Unirme'));
    await tester.pumpAndSettle();

    expect((await f.doc('spaces/$spaceId/members/owner').get()).exists, true);
    // fake_cloud_firestore no re-emite collectionGroup para subcolecciones
    // nuevas (Firestore real sí): forzamos la re-suscripción del provider.
    container.invalidate(mySpacesProvider);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Peña del bar'), findsOneWidget); // ya como espacio
    await _cerrar(tester);
  });
}
