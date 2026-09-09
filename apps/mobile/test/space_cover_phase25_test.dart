import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_link_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_management_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

class _FailingGuestPolicyRepository extends SpacesRepository {
  _FailingGuestPolicyRepository({required super.firestore})
    : super(uid: () => 'owner', isFullAccount: () => true);

  @override
  Future<void> setGuestsCanCreateExpenses(String spaceId, bool allowed) async {
    throw StateError('write failed');
  }
}

class _HoldingManualGateway implements ManualLinkFunctionsGateway {
  @override
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId = '',
    String viaTicketId = '',
    String viaPid = '',
  }) async {}

  @override
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) async => const ManualLinkRetryResult(
    status: ManualLinkPropagationStatus.processing,
    action: ManualLinkRetryAction.inProgress,
  );
}

class _HoldingApproveRepository extends ManualLinkRepository {
  _HoldingApproveRepository({required super.firestore})
    : super(uid: () => 'owner', functions: _HoldingManualGateway());

  final gate = Completer<void>();
  var approvals = 0;

  @override
  Future<void> approve(String spaceId, ManualLinkRequest req) {
    approvals++;
    return gate.future;
  }
}

/// Deterministic renderer coverage for the five Phase 2.5 context surfaces.
/// The test deliberately uses semantic widget assertions rather than a new
/// golden framework; CI can render these stable trees at its normal DPI.
void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/group').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/group/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/relationship').set({
      'name': 'no se debe mostrar',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner', 'ana'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/relationship/members/owner').set({
      'uid': 'owner',
    });
    await firestore.doc('spaces/relationship/members/ana').set({'uid': 'ana'});
    await firestore.doc('profiles/ana').set({'displayName': 'Ana'});
    await firestore.doc('profiles/bruno').set({'displayName': 'Bruno'});
    await firestore.doc('friendships/bruno_owner').set({
      'memberUids': ['bruno', 'owner'],
      'requesterUid': 'owner',
      'receiverUid': 'bruno',
      'status': 'friends',
      'schemaVersion': 1,
    });
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
    ThemeData? theme,
    List<Override> extraOverrides = const [],
    SpacesRepository? spacesRepository,
    ManualLinkRepository? manualLinkRepository,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      overrides: loggedInOverrides(
        firestore: firestore,
        spacesRepository: spacesRepository,
        manualLinkRepository: manualLinkRepository,
      )..addAll(extraOverrides),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('group cover is ticket-first and keeps admin off the cover', (
    tester,
  ) async {
    await pump(tester, const SpaceDetailScreen(spaceId: 'group'));
    expect(find.text('Piso'), findsOneWidget);
    expect(find.byTooltip('Chat'), findsOneWidget);
    expect(find.byTooltip('Gestionar grupo'), findsOneWidget);
    expect(find.text('Tickets del espacio'), findsOneWidget);
    expect(find.text('Personas'), findsNothing);
    expect(find.text('Actividad'), findsNothing);
    expect(find.text('Acciones'), findsNothing);
  });

  testWidgets(
    'relationship cover resolves the person without group semantics',
    (tester) async {
      await pump(tester, const SpaceDetailScreen(spaceId: 'relationship'));
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('no se debe mostrar'), findsNothing);
      expect(find.byTooltip('Chat'), findsOneWidget);
      expect(find.byTooltip('Gestionar'), findsOneWidget);
      expect(find.text('Relación'), findsNothing);
      expect(find.text('Personas'), findsNothing);
      expect(find.text('Actividad'), findsNothing);
      expect(find.text('Acciones'), findsNothing);
    },
  );

  testWidgets(
    'group cover exposes one all-tickets action for several tickets',
    (tester) async {
      for (var index = 0; index < 4; index++) {
        await firestore.doc('sessions/s$index/accounts/a/tickets/t$index').set({
          'spaceId': 'group',
          'grandTotal': 1000,
          'merchant': {'name': 'Tienda $index'},
        });
      }
      await pump(tester, const SpaceDetailScreen(spaceId: 'group'));

      expect(find.text('Ver todos'), findsOneWidget);
      expect(find.text('Ver todos los tickets'), findsNothing);
    },
  );

  testWidgets('guest cover remains readable without an add-ticket mutation', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: loggedInOverrides(
        firestore: firestore,
        authRepository: FakeAuthRepository(
          user: const AppUser(uid: 'owner', isAnonymous: true),
        ),
      ),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'group'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tickets del espacio'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Chat'), findsNothing);
  });

  testWidgets('guest relationship management does not expose Chat', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: loggedInOverrides(
        firestore: firestore,
        authRepository: FakeAuthRepository(
          user: const AppUser(uid: 'owner', isAnonymous: true),
        ),
      ),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceManagementScreen(spaceId: 'relationship'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsNothing);
  });

  testWidgets('archived management hides rename and link mutations', (
    tester,
  ) async {
    await firestore.doc('spaces/group').update({'status': 'archived'});
    await pump(tester, const SpaceManagementScreen(spaceId: 'group'));

    expect(find.text('Editar nombre'), findsNothing);
    expect(find.text('Enlace para unirse'), findsNothing);
  });

  testWidgets('direct archived link route exposes no link mutation', (
    tester,
  ) async {
    await firestore.doc('spaces/group').update({'status': 'archived'});
    await pump(tester, const SpaceLinkScreen(spaceId: 'group'));

    expect(find.text('Crear enlace'), findsNothing);
    expect(find.text('Rotar enlace'), findsNothing);
    expect(find.text('Revocar enlace'), findsNothing);
  });

  testWidgets('group cover remains usable in dark mode', (tester) async {
    await pump(
      tester,
      const SpaceDetailScreen(spaceId: 'group'),
      theme: AppTheme.dark(),
    );

    expect(find.text('Tickets del espacio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover exposes a recoverable people loading error', (
    tester,
  ) async {
    await pump(
      tester,
      const SpaceDetailScreen(spaceId: 'group'),
      extraOverrides: [
        spaceMembersProvider('group').overrideWithValue(
          AsyncError(StateError('members unavailable'), StackTrace.empty),
        ),
        spaceManualParticipantsProvider(
          'group',
        ).overrideWithValue(const AsyncData(<ManualParticipant>[])),
      ],
    );

    expect(
      find.text('No se pudieron cargar los espacios. Comprueba la conexión.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('management exposes a recoverable members error', (tester) async {
    await pump(
      tester,
      const SpaceManagementScreen(spaceId: 'group'),
      extraOverrides: [
        spaceMembersProvider('group').overrideWithValue(
          AsyncError(StateError('members unavailable'), StackTrace.empty),
        ),
      ],
    );

    expect(
      find.text('No se pudieron cargar los espacios. Comprueba la conexión.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail retries a failed space source', (tester) async {
    await pump(
      tester,
      const SpaceDetailScreen(spaceId: 'group'),
      extraOverrides: [
        spaceProvider('group').overrideWithValue(
          AsyncError(StateError('space unavailable'), StackTrace.empty),
        ),
      ],
    );

    expect(
      find.text('No se pudieron cargar los espacios. Comprueba la conexión.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest policy reports a failed write and restores the switch', (
    tester,
  ) async {
    await pump(
      tester,
      const SpaceManagementScreen(spaceId: 'group'),
      spacesRepository: _FailingGuestPolicyRepository(firestore: firestore),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(
      find.text('No se pudo completar la acción. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('manual link decision ignores a repeated tap while pending', (
    tester,
  ) async {
    await firestore.doc('spaces/group/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Pablo',
      'createdByUid': 'owner',
      'schemaVersion': 1,
    });
    await firestore.doc('spaces/group/manualLinkRequests/m1_alba').set({
      'manualId': 'm1',
      'uid': 'alba',
      'displayName': 'Alba',
      'status': 'pending',
      'attempt': 1,
      'schemaVersion': 1,
    });
    final repository = _HoldingApproveRepository(firestore: firestore);
    await pump(
      tester,
      const SpaceManagementScreen(spaceId: 'group'),
      manualLinkRepository: repository,
    );

    await tester.tap(find.text('Aceptar'));
    await tester.pump();
    await tester.tap(find.text('Aceptar'));
    await tester.pump();
    expect(repository.approvals, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Aceptar'))
          .onPressed,
      isNull,
    );
    repository.gate.complete();
  });

  testWidgets('group invites accepted friends, not relationship identities', (
    tester,
  ) async {
    await pump(tester, const SpaceManagementScreen(spaceId: 'group'));
    await tester.tap(find.text('Invitar'));
    await tester.pumpAndSettle();

    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('relationship invites only its other identity', (tester) async {
    await pump(tester, const SpaceManagementScreen(spaceId: 'relationship'));
    await tester.tap(find.text('Invitar'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsWidgets);
    expect(find.text('Bruno'), findsNothing);
  });

  testWidgets(
    'management is second-level and remains usable at high text scale',
    (tester) async {
      await pump(
        tester,
        const SpaceManagementScreen(spaceId: 'group'),
        textScale: 2.5,
      );
      expect(find.text('Gestionar grupo'), findsOneWidget);
      expect(find.text('Personas'), findsOneWidget);
      expect(find.text('Permisos'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Acciones'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Acciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
