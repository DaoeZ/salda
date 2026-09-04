import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/app.dart';
import 'package:salda_mobile/core/routing/router.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/friends/presentation/friends_screen.dart';
import 'package:salda_mobile/features/home/home_screen.dart';
import 'package:salda_mobile/features/auth/presentation/guest_name_screen.dart';
import 'package:salda_mobile/features/profile/presentation/people_search_screen.dart';
import 'package:salda_mobile/features/profile/presentation/profile_screen.dart';
import 'package:salda_mobile/features/settings/presentation/account_hub_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets('Cuenta de una cuenta completa descubre Personas', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: loggedInOverrides(), child: const SaldaApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountHubScreen), findsOneWidget);
    final peopleTile = find.ancestor(
      of: find.byIcon(Icons.people_outline),
      matching: find.byType(ListTile),
    );
    expect(peopleTile, findsOneWidget);
    await tester.tap(peopleTile);
    await tester.pumpAndSettle();
    expect(find.byType(FriendsScreen), findsOneWidget);
  });

  testWidgets('Cuenta invitada abre identidad local, no perfil público', (
    tester,
  ) async {
    final overrides = loggedInOverrides();
    overrides[0] = authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        user: const AppUser(uid: 'guest-owner', isAnonymous: true),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(GuestNameScreen), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets('Cuenta invitada muestra el nombre persistido', (tester) async {
    final overrides = loggedInOverrides();
    overrides[0] = authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        user: const AppUser(uid: 'guest-owner', isAnonymous: true),
      ),
    );
    overrides.add(
      myGuestIdentityProvider.overrideWithValue(
        const AsyncData(
          GuestIdentity(uid: 'guest-owner', displayName: 'Pablo invitado'),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountHubScreen), findsOneWidget);
    expect(find.text('Pablo invitado'), findsOneWidget);
    expect(find.text('Cuenta de invitado'), findsNothing);
  });

  testWidgets('Cuenta completa conserva acceso al histórico sin organizar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: loggedInOverrides(), child: const SaldaApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    final historyTile = find.ancestor(
      of: find.byIcon(Icons.inventory_2_outlined),
      matching: find.byType(ListTile),
    );
    expect(historyTile, findsOneWidget);
    await tester.tap(historyTile);
    await tester.pumpAndSettle();
    expect(find.byType(LegacySessionsScreen), findsOneWidget);
  });

  testWidgets('invitado no puede abrir people search directo', (tester) async {
    final overrides = loggedInOverrides();
    overrides[0] = authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        user: const AppUser(uid: 'guest-owner', isAnonymous: true),
      ),
    );
    overrides.add(
      myGuestIdentityProvider.overrideWithValue(const AsyncData(null)),
    );
    final container = ProviderContainer(overrides: overrides);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/home/people-search');
    await tester.pumpAndSettle();

    expect(find.byType(PeopleSearchScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });

  testWidgets('rutas desconocidas y aliases muestran superficies de producto', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: loggedInOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);
    router.go('/does-not-exist');
    await tester.pumpAndSettle();
    expect(find.text('No encontramos esta pantalla'), findsOneWidget);
    expect(find.text('Volver a Inicio'), findsOneWidget);
    router.go('/home/people');
    await tester.pumpAndSettle();
    expect(find.byType(PeopleSearchScreen), findsOneWidget);
    router.go('/home/friends');
    await tester.pumpAndSettle();
    expect(find.byType(FriendsScreen), findsOneWidget);
    router.go('/home/personas');
    await tester.pumpAndSettle();
    expect(find.byType(FriendsScreen), findsOneWidget);
  });

  testWidgets('con sesión iniciada: historial vacío con su estado inicial', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: loggedInOverrides(), child: const SaldaApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text(Brand.appName), findsOneWidget);
    // Sin contextos no se pintan secciones vacías: un solo estado vacío que
    // dice qué hacer, y la acción de crear en el FAB.
    expect(find.text('Todavía no compartes gastos con nadie'), findsOneWidget);
    expect(find.text('Relaciones'), findsNothing);
    expect(find.text('Escanear'), findsNothing);
    expect(find.text('Añadir'), findsOneWidget);
  });

  testWidgets('sin sesión: se muestra el login', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const SaldaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('cuenta de correo pendiente queda en verificación', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              user: const AppUser(
                uid: 'pending',
                email: 'pendiente@salda.test',
                emailVerified: false,
              ),
            ),
          ),
        ],
        child: const SaldaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verifica tu email'), findsOneWidget);
    expect(find.text('Ya lo he verificado'), findsOneWidget);
    expect(find.text('Escanear'), findsNothing);
  });

  testWidgets('invitado entra al producto', (tester) async {
    final overrides = loggedInOverrides();
    overrides[0] = authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        user: const AppUser(
          uid: 'guest-owner',
          isAnonymous: true,
          emailVerified: false,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Convierte tu cuenta'), findsOneWidget);
    expect(find.text('Escanear'), findsNothing);
    expect(find.text('Estás en paz'), findsNothing);
    expect(find.text('Todo saldado'), findsNothing);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Unirme con un enlace'), findsOneWidget);
    expect(find.text('Gasto o ticket'), findsNothing);
    expect(find.text('Relación'), findsNothing);
    expect(find.text('Grupo'), findsNothing);
  });
}
