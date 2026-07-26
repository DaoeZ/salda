import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// BUG-4: «añadir participante manual» es una acción de GRUPOS. En una
/// relación las dos identidades ya están decididas —la invitación reserva la
/// segunda en v2, y el manual la ocupa en v3—, así que ofrecerla solo podía
/// terminar en un error de Rules.
void main() {
  late FakeFirebaseFirestore firestore;

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

  /// El detalle monta secciones (chat, actividad) con temporizadores propios.
  /// Hay que desmontar el árbol DENTRO de la prueba: el binding comprueba los
  /// temporizadores pendientes antes de ejecutar los `addTearDown`.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// El propietario de los overrides estándar es 'owner'.
  setUp(() async {
    firestore = FakeFirebaseFirestore();

    // Relación v2 PENDIENTE: solo el creador, con invitación reservando la
    // segunda plaza.
    await firestore.doc('spaces/rel2').set({
      'name': 'Ana y yo', 'ownerUid': 'owner', 'kind': 'relationship',
      'relationshipUids': ['owner', 'uid-ana'], 'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/rel2/members/owner').set({'uid': 'owner'});
    await firestore.doc('profiles/uid-ana').set({'displayName': 'Ana'});

    // Relación v3: su segunda identidad es un manual.
    await firestore.doc('spaces/rel3').set({
      'name': 'Pablo', 'ownerUid': 'owner', 'kind': 'relationship',
      'relationshipUids': ['owner'], 'relationshipManualId': 'm-pablo',
      'status': 'active', 'schemaVersion': 3,
    });
    await firestore.doc('spaces/rel3/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/rel3/manualParticipants/m-pablo').set({
      'manualId': 'm-pablo', 'displayName': 'Pablo', 'linkedUid': null,
      'createdByUid': 'owner', 'schemaVersion': 1,
    });

    // Grupo: conserva sus acciones.
    await firestore.doc('spaces/grupo').set({
      'name': 'Piso', 'ownerUid': 'owner', 'kind': 'group',
      'status': 'active', 'schemaVersion': 2,
    });
    await firestore.doc('spaces/grupo/members/owner').set({'uid': 'owner'});
  });

  testWidgets('relación v2 pendiente: NO ofrece añadir manual', (
    tester,
  ) async {
    await pump(tester, 'rel2');
    // El título es la otra persona, no el nombre persistido (BUG-5).
    expect(find.text('Ana'), findsWidgets);
    // La sección entera desaparece: no hay manuales ni forma de añadirlos.
    expect(find.text('Añadir'), findsNothing);
    expect(find.text('Personas sin cuenta'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('relación v3: muestra su manual pero NO ofrece añadir otro', (
    tester,
  ) async {
    await pump(tester, 'rel3');
    // La persona sin cuenta se ve: es la segunda identidad de la relación.
    expect(find.text('Pablo'), findsWidgets);
    // La sección se muestra, pero sin acción de añadir.
    expect(find.text('Personas sin cuenta'), findsOneWidget);
    expect(find.text('Añadir'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('grupo: conserva la acción de añadir manual', (tester) async {
    await pump(tester, 'grupo');
    expect(find.text('Añadir'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('mientras carga no se enseña ninguna acción de grupo', (
    tester,
  ) async {
    // Antes de resolver el espacio no puede saberse su tipo, así que la
    // pantalla no debe pintar acciones que luego retiraría.
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
          home: const SpaceDetailScreen(spaceId: 'rel3'),
        ),
      ),
    );
    await tester.pump(); // primer fotograma, aún sin datos
    expect(find.text('Añadir'), findsNothing);
    await tester.pumpAndSettle();
    await cerrar(tester);
  });
}
