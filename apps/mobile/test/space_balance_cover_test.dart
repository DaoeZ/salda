import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/presentation/space_cover_content.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  void disposeAfterUnmount(WidgetTester tester, ProviderContainer container) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      container.dispose();
    });
  }

  Future<void> pump(
    WidgetTester tester,
    EconomicOverview overview,
    FakeFirebaseFirestore firestore,
    String spaceId, {
    AsyncValue<EconomicOverview>? overviewState,
    bool compact = false,
  }) async {
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore)
        ..addAll([
          guestIdentityRepositoryProvider.overrideWithValue(
            GuestIdentityRepository(firestore: firestore, uid: () => 'owner'),
          ),
          participantEconomicOverviewProvider.overrideWithValue(
            overviewState ?? AsyncData(overview),
          ),
        ]),
    );
    disposeAfterUnmount(tester, container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SpaceBalances(spaceId: spaceId, compact: compact),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  EconomicEntryView entry({
    required String id,
    required String debtor,
    required String creditor,
    required String space,
  }) => EconomicEntryView(
    id: id,
    debtorUid: debtor,
    creditorUid: creditor,
    amount: const Money(1200),
    currency: 'EUR',
    sessionId: 's$id',
    accountId: 'a$id',
    ticketId: 't$id',
    ticketName: 'Ticket $id',
    spaceId: space,
  );

  testWidgets('group preserves owed and owes rows with resolved counterparts', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('profiles/alba').set({'displayName': 'Alba'});
    await firestore.doc('profiles/bruno').set({'displayName': 'Bruno'});
    final overview = EconomicOverview.compute(
      viewerUid: 'owner',
      entries: [
        entry(id: 'one', debtor: 'owner', creditor: 'alba', space: 'group'),
        entry(id: 'two', debtor: 'bruno', creditor: 'owner', space: 'group'),
      ],
      payments: const [],
    );

    await pump(tester, overview, firestore, 'group');

    expect(find.text('Debes a Alba'), findsOneWidget);
    expect(find.text('Bruno te debe'), findsOneWidget);
  });

  testWidgets('group with only my debt keeps its named counterpart', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('profiles/alba').set({'displayName': 'Alba'});
    final overview = EconomicOverview.compute(
      viewerUid: 'owner',
      entries: [
        entry(id: 'one', debtor: 'owner', creditor: 'alba', space: 'group'),
      ],
      payments: const [],
    );

    await pump(tester, overview, firestore, 'group');

    expect(find.text('Debes a Alba'), findsOneWidget);
    expect(find.textContaining('te debe'), findsNothing);
  });

  testWidgets('group with only money owed keeps its named counterpart', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('profiles/bruno').set({'displayName': 'Bruno'});
    final overview = EconomicOverview.compute(
      viewerUid: 'owner',
      entries: [
        entry(id: 'one', debtor: 'bruno', creditor: 'owner', space: 'group'),
      ],
      payments: const [],
    );

    await pump(tester, overview, firestore, 'group');

    expect(find.text('Bruno te debe'), findsOneWidget);
    expect(find.textContaining('Debes a'), findsNothing);
  });

  testWidgets('group zero balance stays scoped and settled', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final overview = EconomicOverview.compute(
      viewerUid: 'owner',
      entries: const [],
      payments: const [],
    );

    await pump(tester, overview, firestore, 'group');

    expect(
      find.textContaining('nadie debe nada en este espacio'),
      findsOneWidget,
    );
  });

  testWidgets('compact balance preview keeps a deterministic small subset', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('profiles/alba').set({'displayName': 'Alba'});
    await firestore.doc('profiles/bruno').set({'displayName': 'Bruno'});
    await firestore.doc('profiles/carla').set({'displayName': 'Carla'});
    final overview = EconomicOverview.compute(
      viewerUid: 'owner',
      entries: [
        entry(id: 'one', debtor: 'owner', creditor: 'alba', space: 'group'),
        entry(id: 'two', debtor: 'owner', creditor: 'bruno', space: 'group'),
        entry(id: 'three', debtor: 'owner', creditor: 'carla', space: 'group'),
      ],
      payments: const [],
    );

    await pump(tester, overview, firestore, 'group', compact: true);

    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('relationship zero balance remains scoped and settled', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final overview = EconomicOverview.compute(
      viewerUid: 'owner',
      entries: const [],
      payments: const [],
    );

    await pump(tester, overview, firestore, 'relationship');

    expect(
      find.textContaining('nadie debe nada en este espacio'),
      findsOneWidget,
    );
  });

  testWidgets('space balances expose retry instead of empty economics', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await pump(
      tester,
      EconomicOverview.compute(
        viewerUid: 'owner',
        entries: const [],
        payments: const [],
      ),
      firestore,
      'group',
      overviewState: AsyncError(
        StateError('economy unavailable'),
        StackTrace.empty,
      ),
    );

    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('space tickets expose retry instead of an empty list', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore)
        ..addAll([
          guestIdentityRepositoryProvider.overrideWithValue(
            GuestIdentityRepository(firestore: firestore, uid: () => 'owner'),
          ),
          spaceTicketsProvider('group').overrideWithValue(
            AsyncError(StateError('tickets unavailable'), StackTrace.empty),
          ),
        ]),
    );
    disposeAfterUnmount(tester, container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SpaceTicketsPreview(spaceId: 'group')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'balance detail keeps its space when the same person is elsewhere',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('profiles/alba').set({'displayName': 'Alba'});
      final overview = EconomicOverview.compute(
        viewerUid: 'owner',
        entries: [
          entry(id: 'group', debtor: 'owner', creditor: 'alba', space: 'group'),
          entry(
            id: 'other',
            debtor: 'owner',
            creditor: 'alba',
            space: 'other-group',
          ),
        ],
        payments: const [],
      );
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore)
          ..addAll([
            guestIdentityRepositoryProvider.overrideWithValue(
              GuestIdentityRepository(firestore: firestore, uid: () => 'owner'),
            ),
            participantEconomicOverviewProvider.overrideWithValue(
              AsyncData(overview),
            ),
          ]),
      );
      disposeAfterUnmount(tester, container);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SpaceBalances(spaceId: 'group')),
          ),
          GoRoute(
            path: '/home/spaces/:sid/balances/:uid',
            builder: (_, state) => Scaffold(
              body: Text(
                '${state.pathParameters['sid']}:${state.pathParameters['uid']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Debes a Alba'), findsOneWidget);
      await tester.tap(find.text('Debes a Alba'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/home/spaces/group/balances/alba');
      expect(find.text('group:alba'), findsOneWidget);
      expect(find.textContaining('other-group'), findsNothing);
    },
  );
}
