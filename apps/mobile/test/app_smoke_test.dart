import 'dart:async';

import 'package:design_tokens/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/app.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';

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
    expect(find.text('Relaciones'), findsOneWidget);
    expect(find.text('Grupos'), findsOneWidget);
    expect(find.text('Escanear'), findsNothing);
    expect(find.text('Crear'), findsOneWidget);
  });

  // Tras entrar con Google, un perfil ilegible (sin red, permisos) dejaba el
  // aviso de "Completa tu perfil": empujaba a duplicar uno que ya existe.
  testWidgets('un perfil que no se puede leer ofrece reintentar, no crear', (
    tester,
  ) async {
    // El stream real de Firestore sigue abierto tras un error; con
    // Stream.error (que cierra al instante) Riverpod se queda en
    // AsyncLoading y no reproduciría el estado que ve el usuario.
    final controller = StreamController<PublicProfile?>()
      ..addError(Exception('sin conexión'));
    addTearDown(controller.close);
    final overrides = loggedInOverrides()
      ..add(myProfileProvider.overrideWith((ref) => controller.stream));
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('no hemos podido cargar tu perfil'), findsOneWidget);
    expect(find.text('Completa tu perfil público'), findsNothing);
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
  });
}
