import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/presentation/login_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('login valida campos antes de autenticar', (tester) async {
    final auth = _RecordingAuthRepository();
    await _pump(tester, const LoginScreen(), auth);
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    expect(find.text('Escribe tu email'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('login ofrece Google e invitado', (tester) async {
    final auth = _RecordingAuthRepository();
    await _pump(tester, const LoginScreen(), auth);
    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();
    await tester.tap(find.text('Continuar como invitado'));
    await tester.pump();
    expect(auth.calls, ['google', 'guest']);
  });

  testWidgets('login admite contraseñas históricas de 6 caracteres', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository();
    await _pump(tester, const LoginScreen(), auth);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'legacy@salda.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    expect(auth.calls, ['signIn:legacy@salda.test']);
  });

  testWidgets('registro valida y envía los datos completos', (tester) async {
    final auth = _RecordingAuthRepository();
    await _pump(tester, const RegisterScreen(), auth);
    await tester.enterText(find.byType(TextFormField).at(0), 'Edgar');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'edgar@salda.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'correcta123');
    await tester.enterText(find.byType(TextFormField).at(3), 'correcta123');
    final createButton = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pump();
    expect(auth.calls, ['register:edgar@salda.test:Edgar']);
  });

  testWidgets('recuperación muestra confirmación no enumerativa', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository();
    await _pump(
      tester,
      const ForgotPasswordScreen(initialEmail: 'edgar@salda.test'),
      auth,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar enlace'));
    await tester.pump();
    expect(auth.calls, ['reset:edgar@salda.test']);
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(
      find.textContaining('Si existe una cuenta con ese email'),
      findsOneWidget,
    );
  });

  testWidgets('verificación permite comprobar, reenviar y cambiar de cuenta', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository(
      user: const AppUser(
        uid: 'pending',
        email: 'pendiente@salda.test',
        emailVerified: false,
      ),
    );
    await _pump(tester, const VerifyEmailScreen(), auth);
    await tester.tap(find.text('Ya lo he verificado'));
    await tester.pump();
    expect(find.textContaining('Todavía no aparece'), findsOneWidget);
    await tester.tap(find.text('Reenviar correo'));
    await tester.pump();
    expect(
      find.text('Correo de verificación enviado de nuevo.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Usar otra cuenta'));
    await tester.pump();
    expect(auth.calls, ['refresh', 'resend', 'signOut']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('los errores de red se anuncian dentro de la pantalla', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository()
      ..failure = const AuthFailure(AuthFailureCode.network);
    await _pump(tester, const LoginScreen(), auth);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'edgar@salda.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'correcta123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    expect(
      find.text('No se pudo conectar con el servicio. Inténtalo de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets('credencial inválida de email conserva el texto de email', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository()
      ..failure = const AuthFailure(
        AuthFailureCode.invalidCredential,
        stage: AuthFailureStage.emailAuthentication,
      );
    await _pump(tester, const LoginScreen(), auth);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'edgar@salda.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'correcta123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
  });

  testWidgets('credencial inválida de Google usa el texto de Google', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository()
      ..failure = const AuthFailure(
        AuthFailureCode.invalidCredential,
        stage: AuthFailureStage.firebaseAuthentication,
      );
    await _pump(tester, const LoginScreen(), auth);
    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();

    expect(
      find.text(
        'No se pudo validar el acceso con Google. Vuelve a intentarlo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Email o contraseña incorrectos'), findsNothing);
  });

  testWidgets('la configuración de email usa un mensaje neutral', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository()
      ..failure = const AuthFailure(AuthFailureCode.configuration);
    await _pump(tester, const LoginScreen(), auth);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'edgar@salda.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'correcta123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(
      find.text(
        'No se pudo iniciar sesión. La aplicación necesita una revisión de configuración.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('El acceso con Google'), findsNothing);
  });

  testWidgets('cancelar Google no muestra error y permite reintentar', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository()
      ..failure = const AuthFailure(AuthFailureCode.cancelled);
    await _pump(tester, const LoginScreen(), auth);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );

    auth.failure = null;
    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();
    expect(auth.calls, ['google', 'google']);
  });

  testWidgets('cada error visible restaura Google para reintentar', (
    tester,
  ) async {
    final auth = _RecordingAuthRepository();
    await _pump(tester, const LoginScreen(), auth);
    const visibleFailures = [
      AuthFailureCode.invalidCredential,
      AuthFailureCode.network,
      AuthFailureCode.configuration,
      AuthFailureCode.googleUnavailable,
      AuthFailureCode.accountMismatch,
      AuthFailureCode.userDisabled,
      AuthFailureCode.temporary,
      AuthFailureCode.unknown,
    ];
    final googleButton = find.widgetWithText(
      OutlinedButton,
      'Continuar con Google',
    );

    for (final code in visibleFailures) {
      auth.failure = AuthFailure(code);
      await tester.ensureVisible(googleButton);
      await tester.tap(googleButton);
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(googleButton).onPressed,
        isNotNull,
        reason: 'el botón se restaura tras $code',
      );
    }

    auth.failure = null;
    await tester.ensureVisible(googleButton);
    await tester.tap(googleButton);
    await tester.pump();
    expect(auth.calls.length, visibleFailures.length + 1);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  _RecordingAuthRepository auth,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pump();
}

class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({this.user});

  AppUser? user;
  AuthFailure? failure;
  final calls = <String>[];
  final _changes = StreamController<AppUser?>.broadcast();

  Future<void> _record(String call) async {
    calls.add(call);
    if (failure case final value?) throw value;
  }

  @override
  AppUser? get currentUser => user;

  @override
  Stream<AppUser?> userChanges() async* {
    yield user;
    yield* _changes.stream;
  }

  @override
  Future<void> signIn(String email, String password) =>
      _record('signIn:$email');

  @override
  Future<void> register(String email, String password, String displayName) =>
      _record('register:$email:$displayName');

  @override
  Future<void> signInWithGoogle() => _record('google');

  @override
  Future<void> signInAsGuest() => _record('guest');

  @override
  Future<void> sendEmailVerification() => _record('resend');

  @override
  Future<bool> refreshEmailVerification() async {
    await _record('refresh');
    return false;
  }

  @override
  Future<void> sendPasswordReset(String email) => _record('reset:$email');

  @override
  Future<void> signOut() async {
    await _record('signOut');
    user = null;
    _changes.add(null);
  }
}
