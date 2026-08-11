import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/auth/application/social_account.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';
import 'package:salda_mobile/features/sessions/data/ticket_links_repository.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/sessions/presentation/linked_ticket_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

class _RetryGateway implements ManualLinkFunctionsGateway {
  _RetryGateway({this.failure});

  final Object? failure;
  var calls = 0;
  var requestCalls = 0;

  @override
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId = '',
    String viaTicketId = '',
    String viaPid = '',
  }) async {
    requestCalls++;
  }

  @override
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) async {
    calls++;
    if (failure != null) throw failure!;
    return const ManualLinkRetryResult(
      status: ManualLinkPropagationStatus.active,
      action: ManualLinkRetryAction.claimed,
    );
  }
}

class _RecordingSocialAccountService extends SocialAccountService {
  _RecordingSocialAccountService(this.status)
    : super(
        auth: FakeAuthRepository(),
        profiles: ProfileRepository(
          firestore: FakeFirebaseFirestore(),
          uid: () => 'unused',
        ),
      );

  final SocialAccountStatus status;
  final flows = <String>[];

  @override
  Future<SocialAccountStatus> prepare({String flow = '-'}) async {
    flows.add(flow);
    return status;
  }
}

void main() {
  const uid = 'uid-marta';

  Future<FakeFirebaseFirestore> seedTicket({
    String? requestStatus = 'accepted',
    String? linkedUid = uid,
    String? linkStatus,
    String? linkError,
    String createdByUid = 'owner',
  }) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': linkedUid,
      'createdByUid': 'owner',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
      'linkStatus': ?linkStatus,
      'linkError': ?linkError,
    });
    if (requestStatus != null) {
      await firestore.doc('spaces/sp1/manualLinkRequests/m1_$uid').set({
        'manualId': 'm1',
        'uid': uid,
        'displayName': 'Marta',
        'status': requestStatus,
        'attempt': 1,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'schemaVersion': 1,
      });
    }
    await firestore.doc('ticketLinks/TOKEN').set({
      'sessionId': 's1',
      'accountId': 'a1',
      'ticketId': 't1',
      'merchantName': 'Cena',
      'spaceId': 'sp1',
      'targetPid': 'p2',
      'targetManualId': 'm1',
      'targetName': 'Marta',
      'createdByUid': createdByUid,
      'status': 'active',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 2,
    });
    await firestore.doc('sessions/s1/ticketAccess/t1_$uid').set({
      'uid': uid,
      'token': 'TOKEN',
      'ticketId': 't1',
      'pid': 'p2',
      'manualId': 'm1',
      'createdAt': Timestamp.now(),
    });
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
      'merchant': {'name': 'Cena'},
      'grandTotal': 1000,
    });
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1/lines/l1').set({
      'name': 'Cena',
      'totalPrice': 1000,
      'order': 0,
      'assignment': {
        'type': 'one',
        'participants': {'p2': 1},
      },
    });
    return firestore;
  }

  Future<void> pumpTicket(
    WidgetTester tester,
    FakeFirebaseFirestore firestore, {
    ManualLinkFunctionsGateway? gateway,
    AuthRepository? auth,
    SocialAccountService? socialAccount,
  }) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final links = TicketLinksRepository(firestore: firestore, uid: () => uid);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...loggedInOverrides(
            firestore: firestore,
            uid: uid,
            manualLinkFunctionsGateway: gateway,
            authRepository: auth,
          ),
          if (socialAccount != null)
            socialAccountServiceProvider.overrideWithValue(socialAccount),
          ticketLinksRepositoryProvider.overrideWithValue(links),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LinkedTicketScreen(token: 'TOKEN'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<ProviderContainer> pumpTicketWithAuthNavigation(
    WidgetTester tester,
    FakeFirebaseFirestore firestore, {
    required FakeAuthRepository auth,
    required SocialAccountService socialAccount,
    ManualLinkFunctionsGateway? gateway,
  }) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final links = TicketLinksRepository(firestore: firestore, uid: () => uid);
    final container = ProviderContainer(
      overrides: [
        ...loggedInOverrides(
          firestore: firestore,
          uid: uid,
          authRepository: auth,
          manualLinkFunctionsGateway: gateway,
        ),
        socialAccountServiceProvider.overrideWithValue(socialAccount),
        ticketLinksRepositoryProvider.overrideWithValue(links),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/ticket/TOKEN',
      routes: [
        GoRoute(
          path: '/ticket/:token',
          builder: (_, state) =>
              LinkedTicketScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/register',
          builder: (_, _) => const Scaffold(body: Text('Registro')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Acceso')),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (_, _) => const Scaffold(body: Text('Verificar')),
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

  testWidgets('sin sesión no escucha solicitudes ni llama al callable', (
    tester,
  ) async {
    final firestore = await seedTicket(requestStatus: null, linkedUid: null);
    final gateway = _RetryGateway();
    await pumpTicket(
      tester,
      firestore,
      gateway: gateway,
      auth: FakeAuthRepository(user: null),
    );

    expect(
      find.text('Identifícate para unirte. No hace falta crear una cuenta.'),
      findsOneWidget,
    );
    expect(find.text('Soy yo'), findsNothing);
    expect(gateway.requestCalls, 0);
    await close(tester);
  });

  testWidgets('invitado y correo sin verificar paran antes del callable', (
    tester,
  ) async {
    final anonymous = await seedTicket(requestStatus: null, linkedUid: null);
    final gateway = _RetryGateway();
    await pumpTicket(
      tester,
      anonymous,
      gateway: gateway,
      auth: FakeAuthRepository(
        user: const AppUser(uid: uid, isAnonymous: true),
      ),
    );
    expect(find.text('Protege tus cuentas'), findsOneWidget);
    expect(gateway.requestCalls, 0);
    await close(tester);

    final unverified = await seedTicket(requestStatus: null, linkedUid: null);
    await pumpTicket(
      tester,
      unverified,
      gateway: gateway,
      auth: FakeAuthRepository(
        user: const AppUser(
          uid: uid,
          email: 'marta@salda.test',
          emailVerified: false,
        ),
      ),
    );
    expect(find.text('Verificar mi correo'), findsOneWidget);
    expect(gateway.requestCalls, 0);
    await close(tester);
  });

  testWidgets(
    'un invitado guarda el enlace pendiente y navega a registro sin llamar al callable',
    (tester) async {
      final firestore = await seedTicket(requestStatus: null, linkedUid: null);
      final auth = FakeAuthRepository(
        user: const AppUser(uid: uid, isAnonymous: true),
      );
      final social = _RecordingSocialAccountService(
        const SocialAccountStatus(SocialReadiness.ready),
      );
      final gateway = _RetryGateway();
      final container = await pumpTicketWithAuthNavigation(
        tester,
        firestore,
        auth: auth,
        socialAccount: social,
        gateway: gateway,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, 'Crear cuenta y conservar datos'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Registro'), findsOneWidget);
      expect(container.read(pendingTicketLinkProvider), 'TOKEN');
      expect(gateway.requestCalls, 0);
      expect(social.flows, isEmpty);
      await close(tester);
    },
  );

  testWidgets(
    'tras convertir el mismo UID prepara la vista y la escritura antes de pedir',
    (tester) async {
      final firestore = await seedTicket(
        requestStatus: null,
        linkedUid: null,
        createdByUid: 'session-owner',
      );
      final auth = FakeAuthRepository(
        user: const AppUser(uid: uid, isAnonymous: true),
      );
      final social = _RecordingSocialAccountService(
        const SocialAccountStatus(SocialReadiness.ready),
      );
      final gateway = _RetryGateway();
      await pumpTicketWithAuthNavigation(
        tester,
        firestore,
        auth: auth,
        socialAccount: social,
        gateway: gateway,
      );

      auth.setUser(
        const AppUser(
          uid: uid,
          email: 'marta@salda.test',
          displayName: 'Marta',
          emailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Soy yo'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Soy yo'));
      await tester.pumpAndSettle();

      expect(social.flows, ['manualLink:sp1:m1:view', 'manualLink:sp1:m1']);
      expect(gateway.requestCalls, 1);
      await close(tester);
    },
  );

  testWidgets(
    'perfil público no disponible no escucha ni solicita y ofrece reintento',
    (tester) async {
      final firestore = await seedTicket(requestStatus: null, linkedUid: null);
      final auth = FakeAuthRepository(
        user: const AppUser(
          uid: uid,
          email: 'marta@salda.test',
          displayName: 'Marta',
          emailVerified: true,
        ),
      );
      final social = _RecordingSocialAccountService(
        const SocialAccountStatus(SocialReadiness.publicProfileUnavailable),
      );
      final gateway = _RetryGateway();
      await pumpTicketWithAuthNavigation(
        tester,
        firestore,
        auth: auth,
        socialAccount: social,
        gateway: gateway,
      );

      expect(
        find.text(
          'Necesitamos terminar de preparar tu perfil. Inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Reintentar'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Soy yo'), findsNothing);
      expect(social.flows, ['manualLink:sp1:m1:view']);
      expect(gateway.requestCalls, 0);
      expect(
        (await firestore.doc('spaces/sp1/manualLinkRequests/m1_$uid').get())
            .exists,
        isFalse,
      );
      await close(tester);
    },
  );

  testWidgets(
    'una cuenta preparada llama al callable una vez con procedencia',
    (tester) async {
      final firestore = await seedTicket(requestStatus: null, linkedUid: null);
      final gateway = _RetryGateway();
      final social = _RecordingSocialAccountService(
        const SocialAccountStatus(SocialReadiness.ready),
      );
      await pumpTicket(
        tester,
        firestore,
        gateway: gateway,
        socialAccount: social,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Soy yo'));
      await tester.pumpAndSettle();
      expect(gateway.requestCalls, 1);
      expect(social.flows, ['manualLink:sp1:m1:view', 'manualLink:sp1:m1']);
      await close(tester);
    },
  );

  testWidgets('la solicitud pendiente y rechazada no se confunden con activa', (
    tester,
  ) async {
    final pending = await seedTicket(requestStatus: 'pending', linkedUid: null);
    await pumpTicket(tester, pending);
    expect(
      find.text('Pendiente de que el anfitrión lo acepte'),
      findsOneWidget,
    );
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);

    final rejected = await seedTicket(
      requestStatus: 'rejected',
      linkedUid: null,
    );
    await pumpTicket(tester, rejected);
    expect(find.text('Solicitud rechazada'), findsOneWidget);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('accepted + linkedUid sin status se muestra propagando', (
    tester,
  ) async {
    final firestore = await seedTicket();
    await pumpTicket(tester, firestore);
    expect(find.textContaining('Vinculando'), findsWidgets);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('processing, active y failed se actualizan en tiempo real', (
    tester,
  ) async {
    final firestore = await seedTicket(linkStatus: 'processing');
    await pumpTicket(tester, firestore);
    expect(find.textContaining('Vinculando'), findsOneWidget);

    await firestore.doc('spaces/sp1/manualParticipants/m1').update({
      'linkStatus': 'active',
    });
    await tester.pumpAndSettle();
    expect(find.text('Identidad vinculada'), findsOneWidget);

    await firestore.doc('spaces/sp1/manualParticipants/m1').update({
      'linkStatus': 'failed',
      'linkError': 'propagation-error',
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No hemos podido completar la vinculación'),
      findsOneWidget,
    );
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('fallo legacy usa el mensaje específico', (tester) async {
    final firestore = await seedTicket(
      linkStatus: 'failed',
      linkError: 'legacy-sessions-without-context',
    );
    await pumpTicket(tester, firestore);
    expect(find.textContaining('gastos antiguos sin contexto'), findsOneWidget);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('el claimant puede reintentar y recibe feedback de éxito', (
    tester,
  ) async {
    final firestore = await seedTicket(
      linkStatus: 'failed',
      linkError: 'propagation-error',
    );
    final gateway = _RetryGateway();
    await pumpTicket(tester, firestore, gateway: gateway);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(find.text('Vinculación completada.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('el claimant recibe feedback localizado si falla el reintento', (
    tester,
  ) async {
    final firestore = await seedTicket(
      linkStatus: 'failed',
      linkError: 'propagation-error',
    );
    final gateway = _RetryGateway(failure: StateError('network'));
    await pumpTicket(tester, firestore, gateway: gateway);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(find.text('No hemos podido completar la operación'), findsOneWidget);
    await close(tester);
  });

  testWidgets('el anfitrión recibe feedback de propagación, no de activa', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/sp1/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': null,
      'createdByUid': 'owner',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
    });
    await firestore.doc('spaces/sp1/manualLinkRequests/m1_uid-marta').set({
      'manualId': 'm1',
      'uid': uid,
      'displayName': 'Marta',
      'status': 'pending',
      'attempt': 1,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
    });

    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: loggedInOverrides(firestore: firestore, uid: 'owner'),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'sp1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vinculando'), findsWidgets);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('el anfitrión ve el fallo real y el retry enfocado', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/sp1/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': uid,
      'createdByUid': 'owner',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'linkStatus': 'failed',
      'linkError': 'propagation-error',
      'schemaVersion': 1,
    });
    final gateway = _RetryGateway();
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: loggedInOverrides(
          firestore: firestore,
          uid: 'owner',
          manualLinkFunctionsGateway: gateway,
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'sp1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No hemos podido completar la vinculación'),
      findsOneWidget,
    );
    final manualTile = find.ancestor(
      of: find.text('Marta'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: manualTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    expect(find.text('Vinculación completada.'), findsOneWidget);
    await close(tester);
  });
}
