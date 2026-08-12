import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/home/home_screen.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/spaces_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// BUG 1: los avisos de invitación y de reclamación de identidad desbordaban.
///
/// El patron culpable era siempre el mismo: texto y botones en la MISMA fila
/// rigida. Con 320 px, escala 1,5 o un nombre largo, los botones no caben y
/// `RenderFlex` desborda — o peor, en un `ListTile.trailing` (restricciones
/// laxas) el segundo boton se va fuera de la pantalla sin avisar.
///
/// Estas pruebas no miran pixeles: comprueban que (a) no hay excepcion de
/// layout y (b) TODAS las acciones siguen dentro de la pantalla y son
/// pulsables. Un banner que no desborda pero deja el boton de aceptar fuera
/// del viewport sigue estando roto.
void main() {
  /// Pinta la pantalla y devuelve los desbordamientos ocurridos.
  ///
  /// El desvio de `FlutterError.onError` se DESHACE antes de volver: si se
  /// deja puesto mientras corre un `expect`, el binding aborta con «a test
  /// overrode FlutterError.onError» y oculta el fallo real.
  Future<List<String>> pantalla(
    WidgetTester tester,
    Widget home, {
    required FakeFirebaseFirestore firestore,
    double ancho = 320,
    double escala = 1.0,
    SpacesRepository? spacesRepository,
  }) async {
    // Ancho de movil pequeno; el alto es holgado a proposito para que la
    // lista perezosa construya el aviso y se pueda medir de verdad.
    tester.view.physicalSize = Size(ancho, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed by')) {
        overflows.add(text.split('\n').first);
      } else {
        previous?.call(details);
      }
    };
    final container = ProviderContainer(
      overrides: loggedInOverrides(
        firestore: firestore,
        spacesRepository: spacesRepository,
      ),
    );
    addTearDown(container.dispose);
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(escala)),
              child: child!,
            ),
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = previous;
    }
    return overflows;
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// Un boton que existe en el arbol pero cae fuera del viewport es un boton
  /// perdido. Esto es lo que las pruebas de overflow por si solas no ven.
  void dentroDePantalla(WidgetTester tester, Finder finder, String que) {
    expect(finder, findsWidgets, reason: '$que deberia estar presente');
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final element in finder.evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(
        rect.left >= -0.5 && rect.right <= size.width + 0.5,
        isTrue,
        reason:
            '$que se sale horizontalmente: $rect en pantalla de ${size.width}',
      );
    }
  }

  // ── Invitacion a un GRUPO ───────────────────────────────────────────────

  Future<FakeFirebaseFirestore> conInvitacion({
    String grupo = 'Piso',
    String quien = 'Ana',
  }) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('profiles/uid-ana').set({
      'uid': 'uid-ana',
      'displayName': quien,
      'username': 'ana',
    });
    await firestore.doc('spaceInvites/sp1_owner').set({
      'spaceId': 'sp1',
      'spaceName': grupo,
      'fromUid': 'uid-ana',
      'toUid': 'owner',
      'status': 'pending',
      'createdAt': DateTime.now(),
      'schemaVersion': 1,
    });
    await firestore.doc('spaces/sp1').set({
      'name': grupo,
      'ownerUid': 'uid-ana',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    return firestore;
  }

  for (final escala in [1.0, 1.3, 1.5]) {
    testWidgets('invitacion de grupo en 320 px con escala $escala', (
      tester,
    ) async {
      final overflows = await pantalla(
        tester,
        const HomeScreen(),
        firestore: await conInvitacion(),
        escala: escala,
      );
      expect(overflows, isEmpty);
      dentroDePantalla(
        tester,
        find.widgetWithText(FilledButton, 'Unirme'),
        'el boton de unirse',
      );
      await cerrar(tester);
    });
  }

  testWidgets('invitacion con nombre de grupo largo CON espacios', (
    tester,
  ) async {
    final overflows = await pantalla(
      tester,
      const HomeScreen(),
      firestore: await conInvitacion(
        grupo: 'Piso compartido de la calle Mayor numero cuarenta y dos',
        quien: 'Ana Maria de las Mercedes Fernandez',
      ),
      escala: 1.3,
    );
    expect(overflows, isEmpty);
    dentroDePantalla(
      tester,
      find.widgetWithText(FilledButton, 'Unirme'),
      'el boton de unirse',
    );
    await cerrar(tester);
  });

  testWidgets('invitacion con nombre largo SIN espacios no rompe la fila', (
    tester,
  ) async {
    // Un nombre sin espacios no puede partirse por palabras: es el peor caso
    // para cualquier `Text` dentro de una fila.
    final overflows = await pantalla(
      tester,
      const HomeScreen(),
      firestore: await conInvitacion(
        grupo: 'PisoCompartidoDeLaCalleMayorNumeroCuarentaYDosBajoDerecha',
        quien: 'AnaMariaDeLasMercedesFernandezDeLaTorreYCastro',
      ),
      escala: 1.5,
    );
    expect(overflows, isEmpty);
    dentroDePantalla(
      tester,
      find.widgetWithText(FilledButton, 'Unirme'),
      'el boton de unirse',
    );
    await cerrar(tester);
  });

  testWidgets('la tarjeta de la lista de espacios tampoco desborda', (
    tester,
  ) async {
    final overflows = await pantalla(
      tester,
      const SpacesScreen(),
      firestore: await conInvitacion(
        grupo: 'Piso compartido de la calle Mayor numero cuarenta y dos',
        quien: 'Ana Maria de las Mercedes Fernandez',
      ),
      escala: 1.5,
    );
    expect(overflows, isEmpty);
    // Accion principal Y secundaria, ambas alcanzables.
    dentroDePantalla(
      tester,
      find.widgetWithText(FilledButton, 'Unirme'),
      'el boton de unirse',
    );
    dentroDePantalla(
      tester,
      find.widgetWithText(TextButton, 'Rechazar'),
      'el boton de rechazar',
    );
    await cerrar(tester);
  });

  // ── Reclamacion de identidad MANUAL (ADR-037) ───────────────────────────

  Future<FakeFirebaseFirestore> conReclamacion({
    String manual = 'Pablo',
    String quien = 'Pablo Ruiz',
  }) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/g1/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/g1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': manual,
      'linkedUid': null,
      'createdByUid': 'owner',
      'schemaVersion': 1,
    });
    await firestore.doc('spaces/g1/manualLinkRequests/m1_uid-pablo').set({
      'manualId': 'm1',
      'uid': 'uid-pablo',
      'displayName': quien,
      'spaceOwnerUid': 'owner',
      'status': 'pending',
      'attempt': 1,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
    });
    return firestore;
  }

  for (final escala in [1.0, 1.3, 1.5]) {
    testWidgets('reclamacion de identidad en 320 px con escala $escala', (
      tester,
    ) async {
      final overflows = await pantalla(
        tester,
        const SpaceDetailScreen(spaceId: 'g1'),
        firestore: await conReclamacion(),
        escala: escala,
      );
      expect(overflows, isEmpty);
      dentroDePantalla(
        tester,
        find.widgetWithText(FilledButton, 'Aceptar'),
        'el boton de aceptar la identidad',
      );
      dentroDePantalla(
        tester,
        find.widgetWithText(TextButton, 'Rechazar'),
        'el boton de rechazar',
      );
      await cerrar(tester);
    });
  }

  testWidgets('reclamacion con nombres largos conserva ambas acciones', (
    tester,
  ) async {
    final overflows = await pantalla(
      tester,
      const SpaceDetailScreen(spaceId: 'g1'),
      firestore: await conReclamacion(
        manual: 'Pablo Alberto de la Fuente Iglesias',
        quien: 'Pablo Alberto de la Fuente Iglesias y Manrique',
      ),
      escala: 1.5,
    );
    expect(overflows, isEmpty);
    dentroDePantalla(
      tester,
      find.widgetWithText(FilledButton, 'Aceptar'),
      'el boton de aceptar la identidad',
    );
    await cerrar(tester);
  });

  // ── Estados del aviso ───────────────────────────────────────────────────

  testWidgets('estado de CARGA: el aviso no aparece a medias', (tester) async {
    // Sin datos todavia, el aviso no debe pintarse con huecos ni desbordar.
    final overflows = await pantalla(
      tester,
      const HomeScreen(),
      firestore: FakeFirebaseFirestore(),
      escala: 1.5,
    );
    expect(overflows, isEmpty);
    expect(find.widgetWithText(FilledButton, 'Unirme'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('estado de ERROR: fallar al responder conserva el aviso', (
    tester,
  ) async {
    final firestore = await conInvitacion();
    final overflows = await pantalla(
      tester,
      const SpacesScreen(),
      firestore: firestore,
      escala: 1.3,
      spacesRepository: _RepoQueFalla(
        firestore: firestore,
        uid: () => 'owner',
        isFullAccount: () => true,
      ),
    );
    expect(overflows, isEmpty);
    // Aceptar falla en el servidor: se avisa y el aviso sigue completo y
    // pulsable, sin quedarse a medias ni desbordar por el mensaje de error.
    await tester.tap(find.widgetWithText(FilledButton, 'Unirme'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo completar'), findsOneWidget);
    dentroDePantalla(
      tester,
      find.widgetWithText(TextButton, 'Rechazar'),
      'el boton de rechazar tras el error',
    );
    await cerrar(tester);
  });

  testWidgets('fallo de invitación en Inicio conserva el aviso y lo explica', (
    tester,
  ) async {
    final firestore = await conInvitacion();
    final overflows = await pantalla(
      tester,
      const HomeScreen(),
      firestore: firestore,
      escala: 1.3,
      spacesRepository: _RepoQueFalla(
        firestore: firestore,
        uid: () => 'owner',
        isFullAccount: () => true,
      ),
    );
    expect(overflows, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Unirme'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo completar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Unirme'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Rechazar'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('invitacion YA ACEPTADA: el aviso desaparece', (tester) async {
    final firestore = await conInvitacion();
    await firestore.doc('spaceInvites/sp1_owner').update({
      'status': 'accepted',
    });
    final overflows = await pantalla(
      tester,
      const HomeScreen(),
      firestore: firestore,
      escala: 1.5,
    );
    expect(overflows, isEmpty);
    expect(find.widgetWithText(FilledButton, 'Unirme'), findsNothing);
    await cerrar(tester);
  });
}

/// Sirve para provocar el ESTADO DE ERROR sin depender de Rules.
class _RepoQueFalla extends SpacesRepository {
  _RepoQueFalla({
    required super.firestore,
    required super.uid,
    required super.isFullAccount,
  });

  @override
  Future<void> acceptInvite(SpaceInvite invite) async =>
      throw StateError('servidor caido');
}
