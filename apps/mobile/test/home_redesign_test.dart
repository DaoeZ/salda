import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/home/balance_hero.dart';
import 'package:salda_mobile/features/home/home_screen.dart';
import 'package:salda_mobile/features/home/presentation/home_space_row.dart';
import 'package:salda_mobile/features/review/application/draft_store.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  const uid = 'owner';
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> seedSpaces(int count, {int archived = 0}) async {
    for (var index = 0; index < count; index++) {
      await firestore.doc('spaces/s$index').set({
        'name': 'Espacio $index',
        'ownerUid': uid,
        'kind': 'group',
        'status': index < archived ? 'archived' : 'active',
        'updatedAt': DateTime(2026, 1, 1).add(Duration(minutes: index)),
      });
      await firestore.doc('spaces/s$index/members/$uid').set({'uid': uid});
    }
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    List<ManualLinkRequest>? links,
    EconomicOverview? economy,
    AppUser? user,
    GuestIdentity? guestIdentity,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides =
        loggedInOverrides(
            firestore: firestore,
            authRepository: FakeAuthRepository(
              user: user ?? const AppUser(uid: uid),
            ),
          )
          ..addAll([
            // Inicio solo necesita estas fuentes para presentar datos. Hacerlas
            // deterministas evita reintentos reales ajenos al escenario probado.
            mySpaceInvitesProvider.overrideWithValue(const AsyncData([])),
            myPendingManualLinksProvider.overrideWithValue(
              AsyncData(links ?? const []),
            ),
            savedDraftProvider.overrideWithValue(const AsyncData(null)),
            participantEconomicOverviewProvider.overrideWithValue(
              AsyncData(
                economy ??
                    EconomicOverview.compute(
                      viewerUid: user?.uid ?? uid,
                      entries: const [],
                      payments: const [],
                    ),
              ),
            ),
            if (guestIdentity != null)
              myGuestIdentityProvider.overrideWithValue(
                AsyncData(guestIdentity),
              ),
          ])
          ..addAll(extraOverrides);
    final container = ProviderContainer(overrides: overrides);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/home/economy',
          builder: (_, _) => const Scaffold(body: Text('Economía destino')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      router.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('0 espacios muestra el balance una vez y el estado vacío', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byType(BalanceHero), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(find.byType(HomeSpaceRow), findsNothing);
  });

  testWidgets('retry del balance reconstruye su fuente económica real', (
    tester,
  ) async {
    var generations = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppUserProvider.overrideWithValue(const AppUser(uid: uid)),
          participantEconomicOverviewProvider.overrideWith((ref) {
            generations++;
            return generations == 1
                ? AsyncError(StateError('offline'), StackTrace.empty)
                : AsyncData(
                    EconomicOverview.compute(
                      viewerUid: uid,
                      entries: const [],
                      payments: const [],
                    ),
                  );
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BalanceHero()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(generations, greaterThanOrEqualTo(2));
    expect(find.text('Estás en paz'), findsOneWidget);
  });

  testWidgets('retry de espacios reconstruye el stream de espacios', (
    tester,
  ) async {
    var generations = 0;
    await pumpHome(
      tester,
      extraOverrides: [
        mySpacesProvider.overrideWith((ref) {
          generations++;
          return generations == 1
              ? Stream<List<Space>>.error(StateError('offline'))
              : Stream.value(const <Space>[]);
        }),
      ],
    );
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(generations, greaterThanOrEqualTo(2));
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('un espacio se representa directamente en Inicio', (
    tester,
  ) async {
    await seedSpaces(1);
    await pumpHome(tester);
    expect(find.byType(HomeSpaceRow), findsOneWidget);
    expect(find.text('Espacio 0'), findsOneWidget);
  });

  testWidgets('55 espacios usan lista perezosa y búsqueda local', (
    tester,
  ) async {
    await seedSpaces(55);
    await pumpHome(tester);
    expect(find.byType(SliverList), findsWidgets);
    expect(find.byType(HomeSpaceRow), isNot(findsNWidgets(55)));
    await tester.enterText(find.byType(TextField), 'Espacio 54');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HomeSpaceRow),
        matching: find.text('Espacio 54'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('la búsqueda resuelve el título de una relación para invitado', (
    tester,
  ) async {
    await seedSpaces(9);
    await firestore.doc('spaces/rel').set({
      'name': 'Nombre guardado que no debe buscarse',
      'ownerUid': uid,
      'kind': 'relationship',
      'relationshipUids': [uid, 'lucia'],
      'status': 'active',
      'updatedAt': DateTime(2026, 2),
    });
    await firestore.doc('spaces/rel/members/$uid').set({'uid': uid});
    await firestore.doc('spaces/rel/members/lucia').set({'uid': 'lucia'});
    await firestore.doc('profiles/lucia').set({
      'displayName': 'Lucía',
      'username': 'lucia',
    });

    await pumpHome(tester);
    await tester.enterText(find.byType(TextField), 'Lucía');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HomeSpaceRow),
        matching: find.text('Lucía'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('la búsqueda persiste al bajar de diez espacios activos', (
    tester,
  ) async {
    await seedSpaces(10);
    await pumpHome(tester);
    await tester.enterText(find.byType(TextField), 'Espacio');
    await tester.pumpAndSettle();

    await firestore.doc('spaces/s9').update({'status': 'archived'});
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Espacio 8'), findsOneWidget);
    expect(find.text('Espacio 9'), findsNothing);
  });

  testWidgets('las monedas se muestran separadas, sin resumen ambiguo', (
    tester,
  ) async {
    await seedSpaces(1);
    for (final currency in ['EUR', 'USD']) {
      await firestore.collection('economicEntries').add({
        'spaceId': 's0',
        'debtorUid': 'other',
        'creditorUid': uid,
        'amount': 1200,
        'currency': currency,
        'memberUids': [uid, 'other'],
        'sessionId': 'session',
        'accountId': 'account',
        'ticketId': currency,
        'ticketName': 'Ticket',
      });
    }
    final overview = EconomicOverview.compute(
      viewerUid: uid,
      entries: [
        for (final currency in ['EUR', 'USD'])
          EconomicEntryView(
            id: currency,
            debtorUid: 'other',
            creditorUid: uid,
            amount: Money(1200),
            currency: currency,
            sessionId: 'session',
            accountId: 'account',
            ticketId: currency,
            ticketName: 'Ticket',
            spaceId: 's0',
          ),
      ],
      payments: const [],
    );
    await pumpHome(tester, economy: overview);
    final hero = find.byType(BalanceHero);
    final row = find.byType(HomeSpaceRow);
    expect(
      find.descendant(of: hero, matching: find.textContaining('12,00')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('12,00')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: hero, matching: find.textContaining('€')),
      findsWidgets,
    );
    expect(
      find.descendant(of: hero, matching: find.textContaining(r'$')),
      findsWidgets,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('€')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining(r'$')),
      findsOneWidget,
    );
    expect(find.text('Varias monedas'), findsNothing);
  });

  testWidgets(
    'modo oscuro y texto 250 % conservan el hero y fila multimoneda',
    (tester) async {
      await seedSpaces(1);
      final overview = EconomicOverview.compute(
        viewerUid: uid,
        entries: [
          for (final currency in ['EUR', 'USD'])
            EconomicEntryView(
              id: currency,
              debtorUid: 'other',
              creditorUid: uid,
              amount: Money(123456789),
              currency: currency,
              sessionId: 's',
              accountId: 'a',
              ticketId: currency,
              ticketName: 'Ticket',
              spaceId: 's0',
            ),
        ],
        payments: const [],
      );
      await pumpHome(
        tester,
        economy: overview,
        brightness: Brightness.dark,
        textScale: 2.5,
      );
      expect(find.byType(BalanceHero), findsOneWidget);
      expect(find.byType(HomeSpaceRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('atención solo procede de solicitudes manuales pendientes', (
    tester,
  ) async {
    await seedSpaces(1);
    await pumpHome(
      tester,
      links: const [
        ManualLinkRequest(
          id: 'request',
          manualId: 'manual',
          uid: uid,
          spaceId: 's0',
          status: ManualLinkStatus.pending,
        ),
      ],
    );
    expect(find.text('1 solicitud'), findsOneWidget);
    expect(find.byIcon(Icons.assignment_ind_outlined), findsOneWidget);
  });

  testWidgets('archivados quedan como acceso secundario', (tester) async {
    await seedSpaces(1, archived: 1);
    await pumpHome(tester);
    expect(find.text('Archivados (1)'), findsOneWidget);
    expect(find.byType(HomeSpaceRow), findsNothing);
  });

  testWidgets('el resumen de saldo abre economía', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Estás en paz'));
    await tester.pumpAndSettle();
    expect(find.text('Economía destino'), findsOneWidget);
  });

  testWidgets('el FAB abre las acciones de Añadir', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto o ticket'), findsOneWidget);
    expect(find.text('Grupo'), findsOneWidget);
  });

  testWidgets('un invitado operativo ve contextos sin flujos de creación', (
    tester,
  ) async {
    await seedSpaces(1);
    const guest = AppUser(uid: uid, isAnonymous: true);
    await pumpHome(
      tester,
      user: guest,
      guestIdentity: GuestIdentity(uid: uid, displayName: 'Invitada'),
    );
    expect(find.byType(HomeSpaceRow), findsOneWidget);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Unirme con un enlace'), findsOneWidget);
    expect(find.text('Grupo'), findsNothing);
  });
}
