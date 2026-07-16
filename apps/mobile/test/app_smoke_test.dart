import 'package:design_tokens/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/app.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';

import 'fakes.dart';

void main() {
  testWidgets('con sesión iniciada: historial vacío con su estado inicial', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: loggedInOverrides(), child: const SaldaApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text(Brand.appName), findsOneWidget);
    expect(find.text('Escanea tu primer ticket'), findsOneWidget);
    expect(find.text('Escanear'), findsOneWidget);
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

    expect(find.text('Escanear'), findsOneWidget);
  });
}
