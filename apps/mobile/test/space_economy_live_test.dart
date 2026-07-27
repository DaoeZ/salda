import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/core/ui/states.dart';
import 'package:salda_mobile/features/economy/presentation/space_economic_summary.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// La portada de un espacio debe reflejar su estado económico REAL y
/// mantenerse viva mientras está montada.
///
/// Se monta el mismo widget de producción sobre los mismos providers y
/// repositorios; lo único simulado es Firestore, que es lo que permite
/// escribir «desde otro cliente» mientras la pantalla sigue abierta.
void main() {
  const yo = 'owner';
  const otro = 'uid-pedro';
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> seedEspacio({String id = 'rel1'}) async {
    await firestore.doc('spaces/$id').set({
      'name': 'Pedro',
      'ownerUid': yo,
      'kind': 'relationship',
      'relationshipUids': [yo, otro],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/$id/members/$yo').set({'uid': yo});
    await firestore.doc('spaces/$id/members/$otro').set({'uid': otro});
    await firestore.doc('profiles/$otro').set({'displayName': 'Pedro'});
  }

  /// Sesión con un ticket dentro del espacio. Sin obligaciones todavía.
  Future<void> seedTicket({
    String spaceId = 'rel1',
    String sessionId = 's1',
    int total = 3000,
  }) async {
    await firestore.doc('sessions/$sessionId').set({
      'ownerUid': yo,
      'kind': 'single',
      'status': 'open',
      'splitModeDefault': 'byItem',
      'currency': 'EUR',
      'spaceId': spaceId,
      'name': 'Cena',
      'computeVersion': 1,
      'totals': {'grandTotal': total, 'settlementRequired': 0},
      'balances': {
        'p0': {'paid': total, 'consumed': total, 'net': 0, 'outstanding': 0},
        'p1': {'paid': 0, 'consumed': 0, 'net': 0, 'outstanding': 0},
      },
    });
    await firestore.doc('sessions/$sessionId/accounts/a1').set({
      'name': 'Cena',
      'totals': {},
    });
    await firestore.doc('sessions/$sessionId/accounts/a1/tickets/t1').set({
      'kind': 'manual',
      'grandTotal': total,
      'paidByParticipantId': 'p0',
      'merchant': {'name': 'BAR CONTINENTAL'},
      'spaceId': spaceId,
    });
  }

  /// Obligación tal y como la escribe `recompute` (Admin SDK en producción).
  Future<void> seedObligacion({
    String id = 'e1',
    String spaceId = 'rel1',
    String debtor = otro,
    String creditor = yo,
    int amount = 1500,
  }) => firestore.collection('economicEntries').doc(id).set({
    'spaceId': spaceId,
    'debtorUid': debtor,
    'creditorUid': creditor,
    'amount': amount,
    'currency': 'EUR',
    'memberUids': [yo, otro],
    'sessionId': 's1',
    'accountId': 'a1',
    'ticketId': 't1',
    'ticketName': 'BAR CONTINENTAL',
    'schemaVersion': 1,
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String spaceId = 'rel1',
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
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpaceEconomicSummary(spaceId: spaceId),
            ),
          ),
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

  testWidgets('con una obligación abierta muestra el saldo', (tester) async {
    await seedEspacio();
    await seedTicket();
    await seedObligacion();
    await pump(tester);
    expect(find.textContaining('15,00'), findsOneWidget);
    expect(find.textContaining('Todavía no tienes movimientos'), findsNothing);
    await cerrar(tester);
  });

  testWidgets(
    'SE ACTUALIZA SOLA cuando llega la obligación con la pantalla abierta',
    (tester) async {
      // Es el caso real: se asignan artículos, recompute escribe la
      // obligación unos milisegundos después y la portada está montada.
      await seedEspacio();
      await seedTicket();
      await pump(tester);
      expect(find.textContaining('15,00'), findsNothing);

      await seedObligacion();
      await tester.pumpAndSettle();

      expect(find.textContaining('15,00'), findsOneWidget);
      await cerrar(tester);
    },
  );

  testWidgets('un cambio de importe posterior también se refleja', (
    tester,
  ) async {
    await seedEspacio();
    await seedTicket();
    await seedObligacion();
    await pump(tester);
    expect(find.textContaining('15,00'), findsOneWidget);

    // Editar el ticket hace que recompute reescriba la MISMA obligación.
    await seedObligacion(amount: 2200);
    await tester.pumpAndSettle();
    expect(find.textContaining('22,00'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('borrar la obligación devuelve la portada a saldo cero', (
    tester,
  ) async {
    await seedEspacio();
    await seedTicket();
    await seedObligacion();
    await pump(tester);
    expect(find.textContaining('15,00'), findsOneWidget);

    await firestore.doc('economicEntries/e1').delete();
    await tester.pumpAndSettle();
    expect(find.textContaining('15,00'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('dos obligaciones se acumulan', (tester) async {
    await seedEspacio();
    await seedTicket();
    await seedObligacion(amount: 1500);
    await pump(tester);
    await seedObligacion(id: 'e2', amount: 500);
    await tester.pumpAndSettle();
    // 15,00 + 5,00 consolidados en la misma pareja.
    expect(find.textContaining('20,00'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('lo que yo debo y lo que me deben se distinguen', (tester) async {
    await seedEspacio();
    await seedTicket();
    // Ahora el deudor soy yo.
    await seedObligacion(debtor: yo, creditor: otro, amount: 800);
    await pump(tester);
    expect(find.textContaining('8,00'), findsOneWidget);
    expect(find.textContaining('Debes'), findsWidgets);
    await cerrar(tester);
  });

  testWidgets('HAY TICKETS PERO SALDO CERO: no dice «sin movimientos»', (
    tester,
  ) async {
    // El caso que se veía en el dispositivo: un ticket de 30 € con las
    // líneas repartidas de modo que nadie debe nada. Económicamente el
    // espacio SÍ tiene movimiento; el saldo es lo que está a cero.
    await seedEspacio();
    await seedTicket();
    await pump(tester);
    expect(
      find.textContaining('Todavía no tienes movimientos'),
      findsNothing,
      reason: 'hay un ticket: no es un espacio sin movimientos',
    );
    await cerrar(tester);
  });

  testWidgets('sin tickets NI saldos sí dice que no hay movimientos', (
    tester,
  ) async {
    await seedEspacio();
    await pump(tester);
    expect(find.byType(EmptyState), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('mientras carga NO se muestra el estado vacío', (tester) async {
    await seedEspacio();
    await seedTicket();
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
          home: const Scaffold(body: SpaceEconomicSummary(spaceId: 'rel1')),
        ),
      ),
    );
    await tester.pump(); // primer fotograma: aún sin datos
    expect(find.textContaining('Todavía no tienes movimientos'), findsNothing);
    expect(find.byType(Skeleton), findsWidgets);
    await tester.pumpAndSettle();
    await cerrar(tester);
  });
}
