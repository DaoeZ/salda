import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/presentation/login_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations_es.dart';

void main() {
  const googleStage = AuthFailureStage.googleAccountSelection;

  AuthFailure mapGoogle(GoogleSignInExceptionCode code) {
    final cause = GoogleSignInException(
      code: code,
      description: 'token=secret email=person@example.test client=client-id',
      details: const {'authorization': 'sensitive'},
    );
    final stack = StackTrace.current;
    final failure = mapAuthFailure(
      cause,
      stack,
      provider: AuthFailureProvider.google,
      stage: googleStage,
    );
    expect(failure.cause, same(cause));
    expect(failure.stackTrace, same(stack));
    return failure;
  }

  group('Google auth failures', () {
    test('cancellation is silent and is not error-reported', () {
      final failure = mapGoogle(GoogleSignInExceptionCode.canceled);

      expect(failure.code, AuthFailureCode.cancelled);
      expect(shouldReportAuthFailure(failure), isFalse);
      expect(
        failure.toString(),
        'AuthFailure(code: AuthFailureCode.cancelled)',
      );
    });

    test('uses structured Google codes with safe fallback', () {
      expect(
        mapGoogle(GoogleSignInExceptionCode.clientConfigurationError).code,
        AuthFailureCode.configuration,
      );
      expect(
        mapGoogle(GoogleSignInExceptionCode.providerConfigurationError).code,
        AuthFailureCode.googleUnavailable,
      );
      expect(
        mapGoogle(GoogleSignInExceptionCode.uiUnavailable).code,
        AuthFailureCode.googleUnavailable,
      );
      expect(
        mapGoogle(GoogleSignInExceptionCode.interrupted).code,
        AuthFailureCode.temporary,
      );
      expect(
        mapGoogle(GoogleSignInExceptionCode.userMismatch).code,
        AuthFailureCode.accountMismatch,
      );
      expect(
        mapGoogle(GoogleSignInExceptionCode.unknownError).code,
        AuthFailureCode.unknown,
      );
    });
  });

  test('Firebase, timeout and other failures use stable categories', () {
    AuthFailure mapFirebase(String code) => mapAuthFailure(
      _FirebaseFailure(code),
      StackTrace.current,
      provider: AuthFailureProvider.firebase,
      stage: AuthFailureStage.firebaseAuthentication,
    );

    expect(mapFirebase('network-request-failed').code, AuthFailureCode.network);
    expect(
      mapFirebase('invalid-credential').code,
      AuthFailureCode.invalidCredential,
    );
    expect(mapFirebase('user-disabled').code, AuthFailureCode.userDisabled);
    expect(mapFirebase('internal-error').code, AuthFailureCode.temporary);
    expect(mapFirebase('invalid-api-key').code, AuthFailureCode.configuration);
    expect(mapFirebase('future-code').code, AuthFailureCode.unknown);
    expect(
      mapAuthFailure(
        TimeoutException('network description with token=secret'),
        StackTrace.current,
        provider: AuthFailureProvider.firebase,
        stage: AuthFailureStage.tokenRefresh,
      ).code,
      AuthFailureCode.network,
    );
    expect(
      mapAuthFailure(
        StateError('email=person@example.test'),
        StackTrace.current,
        provider: AuthFailureProvider.unknown,
        stage: AuthFailureStage.unknown,
      ).code,
      AuthFailureCode.unknown,
    );
  });

  test('retains the actual provider and stage at every auth boundary', () {
    for (final stage in const [
      AuthFailureStage.googleInitialization,
      AuthFailureStage.googleAccountSelection,
      AuthFailureStage.googleCredentialCreation,
    ]) {
      final failure = mapAuthFailure(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
        StackTrace.current,
        provider: AuthFailureProvider.google,
        stage: stage,
      );
      expect(failure.provider, AuthFailureProvider.google);
      expect(failure.stage, stage);
    }
    for (final stage in const [
      AuthFailureStage.firebaseAuthentication,
      AuthFailureStage.firebaseLink,
      AuthFailureStage.tokenRefresh,
    ]) {
      final failure = mapAuthFailure(
        _FirebaseFailure('internal-error'),
        StackTrace.current,
        provider: AuthFailureProvider.firebase,
        stage: stage,
      );
      expect(failure.provider, AuthFailureProvider.firebase);
      expect(failure.stage, stage);
      expect(failure.code, AuthFailureCode.temporary);
    }
  });

  test('enriches unknown context without overwriting specific diagnostics', () {
    final cause = StateError('sensitive description');
    final caughtStack = StackTrace.current;
    final enriched = enrichAuthFailure(
      AuthFailure(
        AuthFailureCode.unknown,
        cause: cause,
        technicalCode: 'safe-code',
      ),
      caughtStack,
      provider: AuthFailureProvider.google,
      stage: AuthFailureStage.googleAccountSelection,
    );
    expect(enriched.cause, same(cause));
    expect(enriched.stackTrace, same(caughtStack));
    expect(enriched.technicalCode, 'safe-code');
    expect(enriched.provider, AuthFailureProvider.google);
    expect(enriched.stage, AuthFailureStage.googleAccountSelection);

    final originalStack = StackTrace.current;
    final specific = AuthFailure(
      AuthFailureCode.temporary,
      cause: cause,
      stackTrace: originalStack,
      provider: AuthFailureProvider.firebase,
      stage: AuthFailureStage.tokenRefresh,
      technicalCode: 'internal-error',
    );
    final unchanged = enrichAuthFailure(
      specific,
      StackTrace.current,
      provider: AuthFailureProvider.google,
      stage: AuthFailureStage.googleAccountSelection,
    );
    expect(unchanged, same(specific));
    expect(unchanged.provider, AuthFailureProvider.firebase);
    expect(unchanged.stage, AuthFailureStage.tokenRefresh);
  });

  test('localized categories and diagnostics are safe', () {
    final l10n = AppLocalizationsEs();
    expect(
      authErrorText(l10n, AuthFailureCode.invalidCredential),
      'Email o contraseña incorrectos',
    );
    expect(
      authErrorText(
        l10n,
        AuthFailureCode.invalidCredential,
        stage: AuthFailureStage.emailAuthentication,
      ),
      'Email o contraseña incorrectos',
    );
    for (final stage in const [
      AuthFailureStage.firebaseAuthentication,
      AuthFailureStage.firebaseLink,
    ]) {
      expect(
        authErrorText(l10n, AuthFailureCode.invalidCredential, stage: stage),
        'No se pudo validar el acceso con Google. Vuelve a intentarlo.',
      );
    }
    expect(
      authErrorText(l10n, AuthFailureCode.accountMismatch),
      'La cuenta de Google seleccionada no coincide. Prueba con la cuenta correcta.',
    );
    expect(
      authErrorText(l10n, AuthFailureCode.userDisabled),
      'Esta cuenta está desactivada.',
    );
    expect(
      authErrorText(l10n, AuthFailureCode.unknown),
      'Algo ha fallado. Inténtalo de nuevo.',
    );
    expect(
      authErrorText(l10n, AuthFailureCode.network),
      'No se pudo conectar con el servicio. Inténtalo de nuevo.',
    );
    expect(
      authErrorText(l10n, AuthFailureCode.configuration),
      'No se pudo iniciar sesión. La aplicación necesita una revisión de configuración.',
    );
    expect(
      authErrorText(l10n, AuthFailureCode.googleUnavailable),
      'El acceso con Google no está disponible ahora. Inténtalo de nuevo.',
    );
    expect(
      authErrorText(l10n, AuthFailureCode.temporary),
      'El servicio no está disponible ahora. Inténtalo de nuevo.',
    );
    expect(authErrorText(l10n, AuthFailureCode.cancelled), isEmpty);
    for (final code in [
      AuthFailureCode.invalidCredential,
      AuthFailureCode.network,
      AuthFailureCode.configuration,
      AuthFailureCode.googleUnavailable,
      AuthFailureCode.accountMismatch,
      AuthFailureCode.userDisabled,
      AuthFailureCode.temporary,
      AuthFailureCode.unknown,
    ]) {
      final message = authErrorText(l10n, code);
      expect(message, isNot(contains('secret')));
      expect(message, isNot(contains('person@example.test')));
      expect(message, isNot(contains('client-id')));
    }

    final failure = mapGoogle(
      GoogleSignInExceptionCode.clientConfigurationError,
    );
    final log = authFailureLogLine(failure);
    expect(log, contains('platform='));
    expect(log, contains('provider=google'));
    expect(log, contains('stage=googleAccountSelection'));
    expect(log, contains('exception=GoogleSignInException'));
    expect(log, contains('technicalCode=clientConfigurationError'));
    expect(log, contains('category=configuration'));
    expect(log, isNot(contains('secret')));
    expect(log, isNot(contains('person@example.test')));
    expect(log, isNot(contains('client-id')));
    expect(log, isNot(contains('authorization')));
  });
}

class _FirebaseFailure extends FirebaseAuthException {
  _FirebaseFailure(String code) : super(code: code);
}
