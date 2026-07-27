import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_identities.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/create_relationship_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// «Nueva relación → alguien sin cuenta», de punta a punta desde la UI.
///
/// El fallo del dispositivo se veía como un mensaje genérico, así que estas
/// pruebas cubren tanto el camino feliz como que cada causa real llegue al
/// usuario con algo que pueda hacer.
void main() {
  const yo = 'owner';
  late FakeFirebaseFirestore firestore;
  late String? navegadoA;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    navegadoA = null;
  });

  /// Monta la pantalla de creación con una ruta real al detalle, para poder
  /// comprobar la navegación posterior y lo que se ve al llegar.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    SpacesRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: loggedInOverrides(
        firestore: firestore,
        spacesRepository: repository,
      ),
    );
    addTearDown(container.dispose);
    // La pantalla navega con go_router: sin un router de verdad, `context.go`
    // lanza y el fallo se confundiría con el que se está probando.
    final router = GoRouter(
      initialLocation: '/nueva',
      routes: [
        GoRoute(
          path: '/nueva',
          builder: (_, _) => const CreateRelationshipScreen(),
        ),
        GoRoute(
          path: '/home/spaces/:sid',
          builder: (_, state) {
            navegadoA = state.uri.path;
            return SpaceDetailScreen(spaceId: state.pathParameters['sid']!);
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// Abre el diálogo, escribe [nombre] y confirma.
  Future<void> crearConNombre(WidgetTester tester, String nombre) async {
    await tester.tap(find.text('Añadir a alguien sin cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, nombre);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
  }

  testWidgets('crear con «Pablo»: escribe la relación v3 completa', (
    tester,
  ) async {
    await pump(tester);
    await crearConNombre(tester, 'Pablo');

    final spaces = await firestore.collection('spaces').get();
    expect(spaces.docs.length, 1);
    final space = spaces.docs.single;
    final data = space.data();

    // Contrato v3, punto por punto.
    expect(data['kind'], 'relationship');
    expect(data['schemaVersion'], 3);
    expect(data['ownerUid'], yo);
    expect(data['relationshipUids'], [yo]);
    expect(
      space.id.startsWith('relationship_'),
      isFalse,
      reason: 'id generado',
    );
    final manualId = data['relationshipManualId'] as String;
    expect(manualId, isNotEmpty);

    final manual = await firestore
        .doc('spaces/${space.id}/manualParticipants/$manualId')
        .get();
    expect(manual.exists, isTrue);
    expect(manual.data()!['displayName'], 'Pablo');
    expect(manual.data()!['linkedUid'], isNull);

    // UNA sola membresía, la del propietario.
    final members = await firestore
        .collection('spaces/${space.id}/members')
        .get();
    expect(members.docs.length, 1);
    expect(members.docs.single.id, yo);
    await cerrar(tester);
  });

  testWidgets('navega al detalle, con «Pablo» de título y dos personas', (
    tester,
  ) async {
    await pump(tester);
    await crearConNombre(tester, 'Pablo');

    final space = (await firestore.collection('spaces').get()).docs.single;
    expect(navegadoA, '/home/spaces/${space.id}');
    // Ya en el detalle: el título es la otra identidad, no el nombre guardado.
    expect(find.text('Pablo'), findsWidgets);
    expect(find.text('2 personas'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('el contexto queda operativo para añadir un ticket', (
    tester,
  ) async {
    final container = await pump(tester);
    await crearConNombre(tester, 'Pablo');
    final space = (await firestore.collection('spaces').get()).docs.single;

    // Dos identidades económicas efectivas: la cuenta y `manual:{id}`.
    final members = container.read(spaceMembersProvider(space.id)).value!;
    final manuals = container
        .read(spaceManualParticipantsProvider(space.id))
        .value!;
    final ids = spaceEconomicIdentities(members: members, manuals: manuals);
    expect(ids.length, 2);
    expect(ids.where((i) => i.startsWith('manual:')).length, 1);
    expect(contextReadyForExpenses(SpaceKind.relationship, ids.length), isTrue);

    // Y el botón de gasto del detalle está habilitado.
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.onPressed, isNotNull);
    await cerrar(tester);
  });

  testWidgets('persiste al reconstruir los providers', (tester) async {
    await pump(tester);
    await crearConNombre(tester, 'Pablo');
    final space = (await firestore.collection('spaces').get()).docs.single;

    // Un contenedor NUEVO sobre el mismo Firestore: lo que se ve depende de
    // lo escrito, no de estado en memoria.
    final otro = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore),
    );
    addTearDown(otro.dispose);
    final leido = await otro
        .read(spacesRepositoryProvider)
        .watchMySpaces()
        .first;
    expect(leido.map((s) => s.id), contains(space.id));
    expect(leido.single.relationshipManualId, isNotEmpty);
    await cerrar(tester);
  });

  testWidgets('doble pulsación no crea dos relaciones', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Añadir a alguien sin cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Pablo');
    // Dos toques seguidos sin dejar que se asiente el primero.
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.tap(
      find.widgetWithText(FilledButton, 'Guardar'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect((await firestore.collection('spaces').get()).docs.length, 1);
    await cerrar(tester);
  });

  testWidgets('nombre vacío: no se crea nada', (tester) async {
    await pump(tester);
    await crearConNombre(tester, '');
    expect((await firestore.collection('spaces').get()).docs, isEmpty);
    await cerrar(tester);
  });

  testWidgets('los espacios sobrantes se recortan', (tester) async {
    await pump(tester);
    await crearConNombre(tester, '   Pablo   ');
    final space = (await firestore.collection('spaces').get()).docs.single;
    final manualId = space.data()['relationshipManualId'] as String;
    final manual = await firestore
        .doc('spaces/${space.id}/manualParticipants/$manualId')
        .get();
    expect(manual.data()!['displayName'], 'Pablo');
    await cerrar(tester);
  });

  testWidgets('cuenta de Google SIN perfil público: se repara y se crea', (
    tester,
  ) async {
    // El caso real: nombre y correo verificados vienen de Google, pero
    // `profiles/{uid}` no existe porque nadie pasó por la pantalla de
    // perfil. Antes esto moría en «Tu sesión aún no está lista».
    expect((await firestore.collection('profiles').get()).docs, isEmpty);
    await pump(tester);
    await crearConNombre(tester, 'Pablo');

    // El perfil se creó solo…
    final perfil = await firestore.doc('profiles/owner').get();
    expect(perfil.exists, isTrue);
    // …y la relación también, sin pedirle nada al usuario.
    expect((await firestore.collection('spaces').get()).docs.length, 1);
    expect(find.textContaining('Tu sesión aún no está lista'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('con el perfil ya creado no se repara nada', (tester) async {
    await firestore.doc('profiles/owner').set({
      'displayName': 'Edgar',
      'username': 'edgar',
      'schemaVersion': 1,
    });
    await pump(tester);
    await crearConNombre(tester, 'Pablo');
    // Sigue habiendo UN solo perfil: la reparación no duplica documentos.
    expect((await firestore.collection('profiles').get()).docs.length, 1);
    expect((await firestore.collection('spaces').get()).docs.length, 1);
    await cerrar(tester);
  });

  testWidgets('si el servidor deniega, el mensaje dice qué hacer', (
    tester,
  ) async {
    await pump(tester, repository: _RepositorioDenegado(firestore));
    await crearConNombre(tester, 'Pablo');
    // Ni rastro del mensaje genérico ni de nada técnico.
    expect(find.textContaining('No se pudo completar'), findsNothing);
    expect(find.textContaining('permission'), findsNothing);
    expect(find.textContaining('Tu sesión aún no está lista'), findsOneWidget);
    // Y no queda ningún documento a medias.
    expect((await firestore.collection('spaces').get()).docs, isEmpty);
    await cerrar(tester);
  });
}

/// Repositorio que reproduce la denegación del servidor sin necesitar Rules.
class _RepositorioDenegado extends SpacesRepository {
  _RepositorioDenegado(FakeFirebaseFirestore firestore)
    : super(
        firestore: firestore,
        uid: () => 'owner',
        isFullAccount: () => true,
      );

  @override
  Future<RelationshipResult> createRelationshipWithManual({
    required String name,
    required String manualName,
    String flow = '-',
  }) async => throw const SpaceFailure(SpaceFailureCode.permissionDenied);
}
