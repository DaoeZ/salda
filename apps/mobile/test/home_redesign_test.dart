import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/core/ui/states.dart';
import 'package:salda_mobile/features/home/home_screen.dart';
import 'package:salda_mobile/features/home/presentation/home_balance_preview.dart';
import 'package:salda_mobile/features/spaces/presentation/space_row.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
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
    SpacesRepository? spacesRepository,
    List<ManualLinkRequest>? pendingManualLinks,
  }) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides:
          loggedInOverrides(
            firestore: firestore,
            spacesRepository: spacesRepository,
          )..addAll(
            pendingManualLinks == null
                ? const []
                : [
                    myPendingManualLinksProvider.overrideWithValue(
                      AsyncData(pendingManualLinks),
                    ),
                  ],
          ),
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

  testWidgets('fallo de espacios no borra el balance independiente', (
    tester,
  ) async {
    await seedRelacion(deudaCents: 2500);
    await pump(
      tester,
      spacesRepository: _SpacesLoadFail(firestore: firestore, uid: () => yo),
    );
    expect(
      find.text('No se pudieron cargar los espacios. Comprueba la conexión.'),
      findsOneWidget,
    );
    expect(find.text('Te deben'), findsWidgets);
    expect(find.text('Ver mis 1 balances'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('saldo a favor: importe, rótulo y desglose', (tester) async {
    await seedRelacion(deudaCents: 2500);
    await pump(tester);
    expect(find.text('Tu saldo'), findsOneWidget);
    // El signo no se transmite solo por color.
    expect(find.text('Te deben'), findsAtLeastNWidgets(2));
    expect(find.text('Debes'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('saldo en contra: cambia el rótulo, no solo el color', (
    tester,
  ) async {
    await seedRelacion(deudaCents: 2500, aFavor: false);
    await pump(tester);
    expect(find.text('Debes'), findsWidgets);
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
    expect(find.text('Pedro'), findsAtLeastNWidgets(2));
    expect(find.text('Te deben'), findsWidgets);
    await cerrar(tester);
  });

  testWidgets('con el texto al 175 % nada desborda', (tester) async {
    await seedRelacion(deudaCents: 123456789);
    await pump(tester, textScale: 1.75);
    expect(tester.takeException(), isNull);
    await cerrar(tester);
  });

  testWidgets('con el texto al 250 % las secciones siguen siendo utilizables', (
    tester,
  ) async {
    await seedRelacion(deudaCents: 123456789);
    await pump(tester, textScale: 2.5);
    expect(tester.takeException(), isNull);
    await cerrar(tester);
  });

  testWidgets(
    'Añadir de cuenta completa muestra los cuatro flujos permitidos',
    (tester) async {
      await seedRelacion();
      await pump(tester);
      await tester.tap(find.text('Añadir'));
      await tester.pumpAndSettle();
      expect(find.text('Gasto o ticket'), findsOneWidget);
      expect(find.text('Relación'), findsOneWidget);
      expect(find.text('Grupo'), findsOneWidget);
      expect(find.text('Unirme con un enlace'), findsOneWidget);
      await cerrar(tester);
    },
  );

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
      findsOneWidget,
    );
    await cerrar(tester);
  });

  testWidgets('atención agrupa cuatro solicitudes manuales y revela todas', (
    tester,
  ) async {
    final requests = <ManualLinkRequest>[];
    for (var index = 0; index < 4; index++) {
      await firestore.doc('spaces/g$index').set({
        'name': 'Grupo $index',
        'ownerUid': yo,
        'kind': 'group',
        'status': 'active',
        'schemaVersion': 2,
      });
      await firestore.doc('spaces/g$index/members/$yo').set({'uid': yo});
      requests.add(
        ManualLinkRequest(
          id: 'm$index',
          manualId: 'm$index',
          uid: 'uid-$index',
          displayName: 'Persona $index',
          status: ManualLinkStatus.pending,
          spaceId: 'g$index',
        ),
      );
    }
    await pump(tester, pendingManualLinks: requests);
    expect(find.text('Ver las 4 pendientes'), findsOneWidget);
    expect(find.byIcon(Icons.assignment_ind_outlined), findsNWidgets(3));
    await tester.tap(find.text('Ver las 4 pendientes'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.assignment_ind_outlined), findsNWidgets(7));
    expect(tester.takeException(), isNull);
    await cerrar(tester);
  });

  testWidgets('solo espacios archivados mantienen acceso al directorio', (
    tester,
  ) async {
    await firestore.doc('spaces/archivado').set({
      'name': 'Viaje pasado',
      'ownerUid': yo,
      'kind': 'group',
      'status': 'archived',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/archivado/members/$yo').set({'uid': yo});
    await pump(tester);

    expect(find.text('Archivados (1)'), findsOneWidget);
    expect(find.text('Todavía no compartes gastos con nadie'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('30 balances se resumen en cinco con CTA completa', (
    tester,
  ) async {
    await seedRelacion();
    for (var index = 0; index < 30; index++) {
      final uid = 'person-$index';
      await firestore.doc('profiles/$uid').set({
        'displayName': 'Persona $index',
      });
      await firestore.collection('economicEntries').add({
        'spaceId': 'rel1',
        'debtorUid': uid,
        'creditorUid': yo,
        'amount': index + 1,
        'currency': index.isEven ? 'EUR' : 'USD',
        'memberUids': [yo, uid],
        'sessionId': 's$index',
        'accountId': 'a$index',
        'ticketId': 't$index',
        'ticketName': 'Ticket $index',
        'schemaVersion': 1,
      });
    }
    await pump(tester);
    final preview = find.byType(HomeBalancePreviewSection);
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.byType(ListTile)),
      findsNWidgets(5),
    );
    expect(find.text('Ver mis 30 balances'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('un espacio con EUR y USD muestra monedas separadas', (
    tester,
  ) async {
    await seedRelacion(deudaCents: 1234);
    await firestore.collection('economicEntries').add({
      'spaceId': 'rel1',
      'debtorUid': 'uid-pedro',
      'creditorUid': yo,
      'amount': 5678,
      'currency': 'USD',
      'memberUids': [yo, 'uid-pedro'],
      'sessionId': 's-usd',
      'accountId': 'a-usd',
      'ticketId': 't-usd',
      'ticketName': 'Cena USD',
      'schemaVersion': 1,
    });
    await pump(tester);

    final row = find.byType(SpaceRow);
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Varias monedas')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('69,12')),
      findsNothing,
    );
    await cerrar(tester);
  });

  testWidgets('el balance de un manual usa su nombre custodiado', (
    tester,
  ) async {
    await seedGrupoConManual();
    await firestore.doc('spaces/g1/manualParticipants/m1').update({
      'displayName': 'Pablo Manual',
    });
    await firestore.collection('economicEntries').add({
      'spaceId': 'g1',
      'debtorUid': 'manual:m1',
      'creditorUid': yo,
      'amount': 2500,
      'currency': 'EUR',
      'memberUids': [yo],
      'sessionId': 's-manual',
      'accountId': 'a-manual',
      'ticketId': 't-manual',
      'ticketName': 'Cena manual',
      'schemaVersion': 1,
    });
    await pump(tester);

    final preview = find.byType(HomeBalancePreviewSection);
    expect(
      find.descendant(of: preview, matching: find.text('Pablo Manual')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.textContaining('manual:')),
      findsNothing,
    );
    expect(
      find.descendant(of: preview, matching: find.text('Alguien')),
      findsNothing,
    );
    await cerrar(tester);
  });
}

class _SpacesLoadFail extends SpacesRepository {
  _SpacesLoadFail({required super.firestore, required super.uid})
    : super(isFullAccount: () => true);

  @override
  Stream<List<Space>> watchMySpaces() =>
      Stream.error(StateError('spaces down'));
}
