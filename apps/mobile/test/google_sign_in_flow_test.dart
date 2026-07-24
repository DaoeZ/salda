import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// flutter_riverpod no re-exporta Override en v3: viene del core.
import 'package:riverpod/misc.dart' show Override;
import 'package:salda_mobile/app.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';

import 'fakes.dart';

/// Flujo posterior a "Continuar con Google", extremo a extremo sobre el router
/// real. Cubre lo que el bug dejaba a oscuras: que tras identificarse el
/// usuario SALE del login, que uno nuevo aterriza en el alta de perfil, que
/// uno existente llega a Inicio y que reabrir la app conserva la sesión.
///
/// Lo que estos tests NO pueden cubrir (necesitan hardware y el registro de la
/// huella en Firebase): que Google emita realmente el idToken. Ver el
/// checklist manual en docs/AUTENTICACION.md.
void main() {
  Future<void> seedProfile(FakeFirebaseFirestore firestore) =>
      firestore.doc('profiles/owner').set({
        'displayName': 'Edgar',
        'displayNameLower': 'edgar',
        'username': 'edgar',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'schemaVersion': 1,
      });

  List<Override> signedOutOverrides(FakeFirebaseFirestore firestore) =>
      loggedInOverrides(firestore: firestore)
        ..[0] = authRepositoryProvider.overrideWithValue(FakeAuthRepository());

  testWidgets('elegir cuenta de Google saca al usuario del login y llega a '
      'Inicio', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await seedProfile(firestore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedOutOverrides(firestore),
        child: const SaldaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsOneWidget);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    // Salió del login…
    expect(find.text('Entrar'), findsNothing);
    // …y está en Inicio, sin que le pidan crear un perfil que ya tiene.
    expect(find.text(Brand.appName), findsOneWidget);
    expect(find.text('Relaciones'), findsOneWidget);
    expect(find.text('Completa tu perfil público'), findsNothing);
  });

  testWidgets('un usuario nuevo de Google continúa al alta de perfil', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedOutOverrides(firestore),
        child: const SaldaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsNothing);
    expect(find.text('Completa tu perfil público'), findsOneWidget);

    await tester.tap(find.text('Crear perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Nombre de usuario'), findsOneWidget);
  });

  testWidgets('reabrir la app con la sesión restaurada no vuelve al login', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedProfile(firestore);
    // Arranque en frío: Firebase Auth ya tiene sesión persistida, igual que
    // tras cerrar y volver a abrir la app.
    final overrides = loggedInOverrides(firestore: firestore)
      ..[0] = authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          user: const AppUser(
            uid: 'google-owner',
            email: 'google@salda.test',
            displayName: 'Google User',
            providerIds: {'google.com'},
          ),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SaldaApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsNothing);
    expect(find.text('Continuar con Google'), findsNothing);
    expect(find.text(Brand.appName), findsOneWidget);
  });

  testWidgets('una cuenta de Google cuenta como verificada y no pasa por la '
      'pantalla de verificación', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await seedProfile(firestore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedOutOverrides(firestore),
        child: const SaldaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(find.text('Verifica tu email'), findsNothing);
    expect(find.text(Brand.appName), findsOneWidget);
  });
}
