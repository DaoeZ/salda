import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salda_mobile/app.dart';
import 'package:salda_mobile/core/config/app_environment.dart';
import 'package:salda_mobile/core/firebase/firebase_bootstrap.dart';

/// Prueba sobre un Android REAL (emulador de CI), con el plugin de
/// google_sign_in y Firebase de verdad: ni fakes ni overrides.
///
/// Qué demuestra: que la app arranca con la firma nueva, que el acceso con
/// Google llega hasta el proveedor y que —pase lo que pase— la pantalla
/// termina en un estado explicado. El bug original era justamente lo
/// contrario: la pantalla se quedaba igual, sin sesión y sin mensaje.
///
/// Qué NO puede demostrar aquí: que Google emita el idToken. Eso exige Play
/// Services con una cuenta real y la huella registrada en salda-dev, y ambas
/// cosas quedan fuera de un runner. Ver el checklist de docs/AUTENTICACION.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('el acceso con Google nunca deja la pantalla en silencio', (
    tester,
  ) async {
    AppEnvironment.validate();
    await bootstrapFirebase();
    await tester.pumpWidget(const ProviderScope(child: SaldaApp()));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // 1) La app arranca en Android real y llega al login.
    expect(find.text('Continuar con Google'), findsOneWidget);
    debugPrint('EVIDENCIA: login renderizado en Android real');

    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();

    // El proveedor tarda: se deja avanzar el reloj hasta que la pantalla se
    // estabiliza en un resultado, sin quedarse en el spinner para siempre.
    for (var i = 0; i < 40 && find.byKey(const Key('auth-error')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Continuar con Google').evaluate().isEmpty) break;
    }

    final salioDelLogin = find.text('Continuar con Google').evaluate().isEmpty;
    final errorVisible = find.byKey(const Key('auth-error')).evaluate().isNotEmpty;

    if (errorVisible) {
      final mensaje = tester
          .widget<Text>(find.byKey(const Key('auth-error')))
          .data!;
      debugPrint('EVIDENCIA: mensaje mostrado -> $mensaje');
      // 2) El fallo se explica. Comparar por igualdad no basta: el código
      // técnico se añade al final, así que el mensaje comodín pasaba el
      // filtro con solo llevarlo pegado. Se exige que ni empiece por él.
      expect(
        mensaje.startsWith('Algo ha fallado'),
        isFalse,
        reason: 'un fallo real debe decir su causa, no el mensaje comodín',
      );
    } else {
      debugPrint('EVIDENCIA: sin error; salioDelLogin=$salioDelLogin');
    }

    // 3) Lo esencial: la pantalla NO se queda igual y en silencio.
    expect(
      errorVisible || salioDelLogin,
      isTrue,
      reason: 'tras elegir cuenta debe haber sesión o una explicación visible',
    );

    // 4) El botón vuelve a estar operativo (no queda un spinner colgado).
    if (!salioDelLogin) {
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  });
}
