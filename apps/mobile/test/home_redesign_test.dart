import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/core/ui/states.dart';
import 'package:salda_mobile/features/home/home_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_row.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// Inicio rediseñado: el balance manda, los contextos se distinguen y los
/// resolvers centrales de BUG-5 (título) y BUG-6 (personas) siguen siendo
/// los que mandan en pantalla.
void main() {
  const yo = 'owner';
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> seedRelacion({int deudaCents = 0, bool aFavor = true}) async {
    await firestore.doc('spaces/rel1').set({
      'name': 'legado que no vale',
      'ownerUid': yo,
      'kind': 'relationship',
      'relationshipUids': [yo, 'uid-pedro'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/rel1/members/$yo').set({'uid': yo});
    await firestore.doc('spaces/rel1/members/uid-pedro').set({
      'uid': 'uid-pedro',
    });
    await firestore.doc('profiles/uid-pedro').set({'displayName': 'Pedro'});
    if (deudaCents > 0) {
      await firestore.collection('economicEntries').add({
        'spaceId': 'rel1',
        'debtorUid': aFavor ? 'uid-pedro' : yo,
        'creditorUid': aFavor ? yo : 'uid-pedro',
        'amount': deudaCents,
        'currency': 'EUR',
        'memberUids': [yo, 'uid-pedro'],
        'sessionId': 's1',
        'accountId': 'a1',
        'ticketId': 't1',
        'ticketName': 'Cena',
        'schemaVersion': 1,
      });
    }
  }

  Future<void> seedGrupoConManual() async {
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': yo,
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/g1/members/$yo').set({'uid': yo});
    await firestore.doc('spaces/g1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Pablo',
      'linkedUid': null,
      'createdByUid': yo,
      'schemaVersion': 1,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(420, 2000);
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
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Inicio lee balances en vivo: hay que desmontar dentro de la prueba.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('sin espacios: un estado vacío que explica el paso siguiente', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Todavía no compartes gastos con nadie'), findsOneWidget);
    // No se pintan secciones vacías con su título.
    expect(find.text('RELACIONES'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('saldo a favor: importe, rótulo y desglose', (tester) async {
    await seedRelacion(deudaCents: 2500);
    await pump(tester);
    expect(find.text('Tu saldo'), findsOneWidget);
    // El signo no se transmite solo por color.
    expect(find.text('A tu favor'), findsOneWidget);
    expect(find.text('Te deben'), findsOneWidget);
    expect(find.text('Debes'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('saldo en contra: cambia el rótulo, no solo el color', (
    tester,
  ) async {
    await seedRelacion(deudaCents: 2500, aFavor: false);
    await pump(tester);
    expect(find.text('En tu contra'), findsOneWidget);
    expect(find.text('A tu favor'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('sin deudas: se dice que estás en paz', (tester) async {
    await seedRelacion();
    await pump(tester);
    expect(find.text('Estás en paz'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('la tarjeta de relación enseña a la otra persona (BUG-5)', (
    tester,
  ) async {
    await seedRelacion();
    await pump(tester);
    expect(find.byType(SpaceRow), findsOneWidget);
    expect(find.text('Pedro'), findsOneWidget);
    expect(find.text('legado que no vale'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('el grupo conserva su nombre y cuenta PERSONAS (BUG-6)', (
    tester,
  ) async {
    await seedGrupoConManual();
    await pump(tester);
    expect(find.text('Piso'), findsOneWidget);
    // Una cuenta + un MANUAL son DOS personas, no «1 miembro».
    expect(find.text('2 personas'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('relación pendiente: se marca como tal', (tester) async {
    await firestore.doc('spaces/rel2').set({
      'name': 'Ana',
      'ownerUid': yo,
      'kind': 'relationship',
      'relationshipUids': [yo, 'uid-ana'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/rel2/members/$yo').set({'uid': yo});
    await pump(tester);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('1 persona'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('modo oscuro: la misma pantalla, sin excepciones', (
    tester,
  ) async {
    await seedRelacion(deudaCents: 1500);
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('Pedro'), findsOneWidget);
    expect(find.text('A tu favor'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('con el texto al 175 % nada desborda', (tester) async {
    await seedRelacion(deudaCents: 123456789);
    await pump(tester, textScale: 1.75);
    expect(tester.takeException(), isNull);
    await cerrar(tester);
  });

  testWidgets('mientras carga se enseña estructura, no un aro girando', (
    tester,
  ) async {
    await seedRelacion();
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore),
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    await cerrar(tester);
  });

  testWidgets('la barra superior deja de ser una fila de iconos', (
    tester,
  ) async {
    await seedRelacion();
    await pump(tester);
    // Eran ocho; ahora quedan el enlace de entrada y el menú.
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.byType(IconButton)),
      findsNWidgets(2),
    );
    await cerrar(tester);
  });
}
