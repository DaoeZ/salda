import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/presentation/join_space_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// La regla de producto del Sprint 4: **a quien ya tiene identidad no se le
/// pregunta quién es**. El enlace entra solo. El selector de identidad se
/// reserva a los participantes MANUAL de los enlaces de TICKET (Sprint 5).
void main() {
  late FakeFirebaseFirestore firestore;

  /// Grupo ajeno con enlace vivo: el caso real de recibirlo por WhatsApp.
  Future<String> seedGroupWithLink({DateTime? expiresAt}) async {
    await firestore.doc('spaces/sp1').set({
      'name': 'Cena viernes',
      'ownerUid': 'owner-ajeno',
      'status': 'active',
      'kind': 'group',
      'schemaVersion': 2,
    });
    await firestore.doc('spaceLinks/TOKEN').set({
      'spaceId': 'sp1',
      'spaceName': 'Cena viernes',
      'createdByUid': 'owner-ajeno',
      'status': 'active',
      'schemaVersion': 1,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
    });
    return 'sp1';
  }

  Future<void> pump(
    WidgetTester tester,
    List<Override> overrides, {
    String? token = 'TOKEN',
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/g/${token ?? ''}',
      routes: [
        GoRoute(
          path: '/g/:token',
          builder: (_, state) =>
              JoinSpaceScreen(token: state.pathParameters['token']),
        ),
        GoRoute(
          path: '/home/spaces/:sid',
          builder: (_, state) =>
              Scaffold(body: Text('GRUPO ${state.pathParameters['sid']}')),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Placeholder()),
        GoRoute(path: '/register', builder: (_, _) => const Placeholder()),
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
  }

  /// Invitado operativo: sesión anónima + nombre visible ya elegido.
  List<Override> guestOverrides() => [
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        user: const AppUser(uid: 'guest-1', isAnonymous: true),
      ),
    ),
    guestIdentityRepositoryProvider.overrideWithValue(
      GuestIdentityRepository(firestore: firestore, uid: () => 'guest-1'),
    ),
    spacesRepositoryProvider.overrideWithValue(
      SpacesRepository(
        firestore: firestore,
        uid: () => 'guest-1',
        isFullAccount: () => false,
        guestDisplayName: () => 'Alba',
      ),
    ),
  ];

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  testWidgets('CUENTA: el enlace entra solo, sin preguntar quién eres', (
    tester,
  ) async {
    await seedGroupWithLink();
    await pump(tester, loggedInOverrides(firestore: firestore));

    // Aterriza en el grupo sin ningún paso intermedio.
    expect(find.text('GRUPO sp1'), findsOneWidget);
    expect(
      (await firestore.doc('spaces/sp1/members/owner').get()).exists,
      isTrue,
    );
    // Y jamás se le ofreció confirmar ni elegir identidad.
    expect(find.text('Unirme al grupo'), findsNothing);
    expect(find.text('Continuar como invitado'), findsNothing);
  });

  testWidgets('INVITADO: su identidad del dispositivo basta; entra directo', (
    tester,
  ) async {
    await seedGroupWithLink();
    await firestore.doc('guestIdentities/guest-1').set({
      'uid': 'guest-1',
      'displayName': 'Alba',
      'schemaVersion': 1,
    });

    await pump(tester, guestOverrides());

    expect(find.text('GRUPO sp1'), findsOneWidget);
    final member = (await firestore.doc('spaces/sp1/members/guest-1').get())
        .data()!;
    expect(member['kind'], 'guest');
    expect(member['displayName'], 'Alba');
    expect(find.text('Unirme al grupo'), findsNothing);
  });

  testWidgets('SIN IDENTIDAD: ofrece invitado, iniciar sesión y crear cuenta', (
    tester,
  ) async {
    await seedGroupWithLink();
    await pump(tester, [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      spacesRepositoryProvider.overrideWithValue(
        SpacesRepository(
          firestore: firestore,
          uid: () => 'nadie',
          isFullAccount: () => false,
        ),
      ),
    ]);

    // Se ve a qué grupo se entra antes de decidir.
    expect(find.text('Cena viernes'), findsOneWidget);
    expect(find.text('Continuar como invitado'), findsOneWidget);
    expect(find.text('Entrar con mi cuenta'), findsOneWidget);
    expect(find.text('Crear una cuenta'), findsOneWidget);
    // Nadie se ha unido a nada todavía.
    expect(
      (await firestore.doc('spaces/sp1/members/nadie').get()).exists,
      isFalse,
    );
  });

  testWidgets('el enlace se recuerda para volver tras identificarse', (
    tester,
  ) async {
    await seedGroupWithLink();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        spacesRepositoryProvider.overrideWithValue(
          SpacesRepository(
            firestore: firestore,
            uid: () => 'nadie',
            isFullAccount: () => false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: JoinSpaceScreen(token: 'TOKEN'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sin esto, tocar "iniciar sesión" perdía el enlace del chat.
    expect(container.read(pendingGroupLinkProvider), 'TOKEN');
  });

  testWidgets('un enlace caducado no entra y lo dice sin dar pistas', (
    tester,
  ) async {
    await seedGroupWithLink(
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    await pump(tester, loggedInOverrides(firestore: firestore));

    expect(find.text('GRUPO sp1'), findsNothing);
    expect(find.textContaining('ya no sirve'), findsOneWidget);
    // El nombre del grupo NO se filtra: caducado e inexistente son iguales.
    expect(find.text('Cena viernes'), findsNothing);
    expect(
      (await firestore.doc('spaces/sp1/members/owner').get()).exists,
      isFalse,
    );
  });
}
