import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Identidad que consume la app, desacoplada de los tipos de Firebase.
class AppUser {
  const AppUser({
    required this.uid,
    this.isAnonymous = false,
    this.emailVerified = true,
    this.email,
    this.displayName,
    this.photoUrl,
    this.providerIds = const <String>{},
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isAnonymous;
  final bool emailVerified;
  final Set<String> providerIds;

  /// Las cuentas de correo deben verificar la dirección antes de escribir.
  bool get needsEmailVerification => !isAnonymous && !emailVerified;

  /// Cuenta apta para las futuras funciones de perfil y ámbito social.
  bool get isFullAccount => !isAnonymous && emailVerified;

  /// Igualdad de VALOR: userChanges() re-emite tras cada reload/refresh de
  /// token aunque nada cambie, y los providers que observan la identidad
  /// (router incluido) no deben reaccionar a una emisión idéntica: recrear
  /// el GoRouter reinicia la pila de navegación y cierra pantallas en uso.
  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl &&
      other.isAnonymous == isAnonymous &&
      other.emailVerified == emailVerified &&
      other.providerIds.length == providerIds.length &&
      other.providerIds.containsAll(providerIds);

  @override
  int get hashCode => Object.hash(
    uid,
    email,
    displayName,
    photoUrl,
    isAnonymous,
    emailVerified,
  );
}

enum AuthFailureCode {
  invalidCredential,
  emailAlreadyInUse,
  weakPassword,
  network,
  tooManyRequests,
  userDisabled,
  operationNotAllowed,
  credentialAlreadyInUse,
  accountMismatch,
  configuration,
  googleUnavailable,
  temporary,
  cancelled,
  unknown,
}

enum AuthFailureProvider { firebase, google, unknown }

enum AuthFailureStage {
  emailAuthentication,
  emailAccountCreation,
  emailLink,
  googleInitialization,
  googleAccountSelection,
  googleCredentialCreation,
  firebaseAuthentication,
  firebaseLink,
  tokenRefresh,
  unknown,
}

/// Error estable y presentable: la UI nunca depende de códigos de Firebase.
class AuthFailure implements Exception {
  const AuthFailure(
    this.code, {
    this.cause,
    this.stackTrace,
    this.provider = AuthFailureProvider.unknown,
    this.stage = AuthFailureStage.unknown,
    this.technicalCode,
  });

  final AuthFailureCode code;

  /// Datos de diagnóstico internos; la UI nunca los presenta.
  final Object? cause;
  final StackTrace? stackTrace;
  final AuthFailureProvider provider;
  final AuthFailureStage stage;
  final String? technicalCode;

  @override
  String toString() => 'AuthFailure(code: $code)';
}

typedef AuthFailureReporter = void Function(AuthFailure failure);

/// Línea de diagnóstico deliberadamente sin descripción, detalles ni PII.
String authFailureLogLine(AuthFailure failure) =>
    'platform=${defaultTargetPlatform.name} '
    'provider=${failure.provider.name} '
    'stage=${failure.stage.name} '
    'exception=${failure.cause?.runtimeType ?? 'none'} '
    'technicalCode=${failure.technicalCode ?? 'none'} '
    'category=${failure.code.name}';

void reportAuthFailure(AuthFailure failure) {
  if (!shouldReportAuthFailure(failure)) return;
  final trace = failure.stackTrace?.toString().split('\n').take(3).join('\n');
  debugPrint('auth_failure ${authFailureLogLine(failure)}');
  if (trace != null && trace.isNotEmpty) debugPrint(trace);
}

bool shouldReportAuthFailure(AuthFailure failure) =>
    failure.code != AuthFailureCode.cancelled;

/// Puerto de bajo nivel. Separarlo permite probar todas las transiciones de
/// identidad sin inicializar Firebase ni abrir el selector nativo de Google.
abstract interface class AuthGateway {
  Stream<AppUser?> userChanges();
  AppUser? get currentUser;
  Future<AppUser> signInWithEmail(String email, String password);
  Future<AppUser> createEmailAccount(String email, String password);
  Future<AppUser> linkEmailAccount(String email, String password);
  Future<AppUser> signInWithGoogle();
  Future<AppUser> linkGoogleAccount();
  Future<AppUser> signInAnonymously();
  Future<void> updateDisplayName(String displayName);
  Future<void> sendEmailVerification();
  Future<AppUser?> reloadUser({required bool refreshToken});
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

abstract interface class AuthRepository {
  Stream<AppUser?> userChanges();
  AppUser? get currentUser;
  Future<void> signIn(String email, String password);
  Future<void> register(String email, String password, String displayName);
  Future<void> signInWithGoogle();
  Future<void> signInAsGuest();
  Future<void> sendEmailVerification();
  Future<bool> refreshEmailVerification();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

/// Orquesta las reglas de producto sobre el proveedor de autenticación.
class DefaultAuthRepository implements AuthRepository {
  DefaultAuthRepository(this._gateway);

  final AuthGateway _gateway;

  @override
  Stream<AppUser?> userChanges() => _gateway.userChanges();

  @override
  AppUser? get currentUser => _gateway.currentUser;

  @override
  Future<void> signIn(String email, String password) async {
    await _gateway.signInWithEmail(email, password);
  }

  @override
  Future<void> register(
    String email,
    String password,
    String displayName,
  ) async {
    final wasAnonymous = _gateway.currentUser?.isAnonymous ?? false;
    if (wasAnonymous) {
      await _gateway.linkEmailAccount(email, password);
      // CONVERSIÓN: `User.isAnonymous` pasa a false al instante, pero el ID
      // TOKEN conserva `sign_in_provider: 'anonymous'` hasta que caduca. Las
      // Rules leen el token, no el objeto local, así que sin este refresco
      // la app se cree con cuenta completa mientras el servidor la sigue
      // tratando como invitada y deniega TODA escritura social.
      await _gateway.reloadUser(refreshToken: true);
    } else {
      await _gateway.createEmailAccount(email, password);
    }
    await _gateway.updateDisplayName(displayName);
    await _gateway.sendEmailVerification();
  }

  @override
  Future<void> signInWithGoogle() async {
    if (_gateway.currentUser?.isAnonymous ?? false) {
      await _gateway.linkGoogleAccount();
      // Mismo motivo que en `register`: sin refrescar el token, las Rules
      // siguen viendo una sesión anónima.
      await _gateway.reloadUser(refreshToken: true);
    } else {
      await _gateway.signInWithGoogle();
    }
  }

  @override
  Future<void> signInAsGuest() async {
    await _gateway.signInAnonymously();
  }

  @override
  Future<void> sendEmailVerification() => _gateway.sendEmailVerification();

  @override
  Future<bool> refreshEmailVerification() async {
    final user = await _gateway.reloadUser(refreshToken: true);
    return user?.emailVerified ?? false;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _gateway.sendPasswordReset(email);
    } on AuthFailure catch (failure) {
      // No revelar si un correo está registrado (email enumeration).
      if (failure.code != AuthFailureCode.invalidCredential) rethrow;
    }
  }

  @override
  Future<void> signOut() => _gateway.signOut();
}

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway(
    this._auth, {
    GoogleSignIn? googleSignIn,
    AuthFailureReporter? failureReporter,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _failureReporter = failureReporter ?? reportAuthFailure;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final AuthFailureReporter _failureReporter;
  Future<void>? _googleInitialization;

  AppUser? _map(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoURL,
          isAnonymous: user.isAnonymous,
          emailVerified: user.emailVerified,
          providerIds: {
            for (final provider in user.providerData) provider.providerId,
          },
        );

  @override
  Stream<AppUser?> userChanges() => _auth.userChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AppUser> signInWithEmail(String email, String password) => _guard(
    () async => _required(
      (await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      )).user,
    ),
    stage: AuthFailureStage.emailAuthentication,
  );

  @override
  Future<AppUser> createEmailAccount(String email, String password) => _guard(
    () async => _required(
      (await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      )).user,
    ),
    stage: AuthFailureStage.emailAccountCreation,
  );

  @override
  Future<AppUser> linkEmailAccount(String email, String password) => _guard(
    () async => _required(
      (await _requiredFirebaseUser().linkWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      )).user,
    ),
    stage: AuthFailureStage.emailLink,
  );

  @override
  Future<AppUser> signInWithGoogle() async {
    final credential = await _googleCredential();
    return _guard(
      () async =>
          _required((await _auth.signInWithCredential(credential)).user),
      stage: AuthFailureStage.firebaseAuthentication,
    );
  }

  @override
  Future<AppUser> linkGoogleAccount() async {
    final credential = await _googleCredential();
    return _guard(
      () async => _required(
        (await _requiredFirebaseUser().linkWithCredential(credential)).user,
      ),
      stage: AuthFailureStage.firebaseLink,
    );
  }

  @override
  Future<AppUser> signInAnonymously() =>
      _guard(() async => _required((await _auth.signInAnonymously()).user));

  @override
  Future<void> updateDisplayName(String displayName) =>
      _guardVoid(() => _requiredFirebaseUser().updateDisplayName(displayName));

  @override
  Future<void> sendEmailVerification() =>
      _guardVoid(() => _requiredFirebaseUser().sendEmailVerification());

  @override
  Future<AppUser?> reloadUser({required bool refreshToken}) => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    if (refreshToken) {
      // Las Rules leen email_verified del token, no del objeto local.
      await _auth.currentUser?.getIdToken(true);
    }
    return _map(_auth.currentUser);
  }, stage: AuthFailureStage.tokenRefresh);

  @override
  Future<void> sendPasswordReset(String email) =>
      _guardVoid(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() => _guardVoid(() async {
    await _auth.signOut();
    try {
      await _googleSignIn.signOut();
    } on Object {
      // Firebase ya cerró la sesión; un fallo del SDK social no debe
      // mantener al usuario dentro de Salda.
    }
  });

  Future<AuthCredential> _googleCredential() async {
    _googleInitialization ??= _googleSignIn.initialize(
      serverClientId: _googleServerClientId.isEmpty
          ? null
          : _googleServerClientId,
    );
    // google_sign_in 7.x exige inicializar una sola vez por instancia.
    await _guardGoogleStage(
      () => _googleInitialization!,
      AuthFailureStage.googleInitialization,
    );
    final account = await _guardGoogleStage(
      _googleSignIn.authenticate,
      AuthFailureStage.googleAccountSelection,
    );
    return _guardGoogleStage(() {
      final authentication = account.authentication;
      return GoogleAuthProvider.credential(idToken: authentication.idToken);
    }, AuthFailureStage.googleCredentialCreation);
  }

  User _requiredFirebaseUser() {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure(AuthFailureCode.unknown);
    return user;
  }

  AppUser _required(User? user) {
    final mapped = _map(user);
    if (mapped == null) throw const AuthFailure(AuthFailureCode.unknown);
    return mapped;
  }

  Future<T> _guard<T>(
    Future<T> Function() action, {
    AuthFailureStage stage = AuthFailureStage.unknown,
  }) async {
    try {
      return await action();
    } on AuthFailure catch (failure, stackTrace) {
      final enriched = enrichAuthFailure(
        failure,
        stackTrace,
        provider: AuthFailureProvider.firebase,
        stage: stage,
      );
      _report(enriched);
      throw enriched;
    } on Object catch (error, stackTrace) {
      final failure = mapAuthFailure(
        error,
        stackTrace,
        provider: AuthFailureProvider.firebase,
        stage: stage,
      );
      _report(failure);
      throw failure;
    }
  }

  Future<T> _guardGoogleStage<T>(
    FutureOr<T> Function() action,
    AuthFailureStage stage,
  ) async {
    try {
      return await action();
    } on AuthFailure catch (failure, stackTrace) {
      final enriched = enrichAuthFailure(
        failure,
        stackTrace,
        provider: AuthFailureProvider.google,
        stage: stage,
      );
      _report(enriched);
      throw enriched;
    } on Object catch (error, stackTrace) {
      final failure = mapAuthFailure(
        error,
        stackTrace,
        provider: AuthFailureProvider.google,
        stage: stage,
      );
      _report(failure);
      throw failure;
    }
  }

  void _report(AuthFailure failure) {
    if (shouldReportAuthFailure(failure)) _failureReporter(failure);
  }

  Future<void> _guardVoid(Future<void> Function() action) =>
      _guard<void>(action);
}

const _googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  // Cliente web OAuth público de salda-dev. Producción lo sustituirá con un
  // dart-define al introducir flavors; no es un secreto.
  defaultValue:
      '923355592259-qo73cse3nbhcmidpmjahinimd88aviji.apps.googleusercontent.com',
);

AuthFailureCode _mapFirebaseCode(String code) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-email' ||
  'invalid-verification-code' ||
  'invalid-verification-id' ||
  'missing-verification-code' ||
  'missing-verification-id' => AuthFailureCode.invalidCredential,
  'email-already-in-use' => AuthFailureCode.emailAlreadyInUse,
  'weak-password' => AuthFailureCode.weakPassword,
  'network-request-failed' => AuthFailureCode.network,
  'too-many-requests' => AuthFailureCode.tooManyRequests,
  'user-disabled' => AuthFailureCode.userDisabled,
  'operation-not-allowed' => AuthFailureCode.operationNotAllowed,
  'credential-already-in-use' || 'account-exists-with-different-credential' =>
    AuthFailureCode.credentialAlreadyInUse,
  'invalid-api-key' ||
  'app-not-authorized' ||
  'invalid-app-credential' => AuthFailureCode.configuration,
  'internal-error' || 'unavailable' => AuthFailureCode.temporary,
  _ => AuthFailureCode.unknown,
};

AuthFailureCode _mapGoogleCode(GoogleSignInExceptionCode code) =>
    switch (code) {
      GoogleSignInExceptionCode.canceled => AuthFailureCode.cancelled,
      GoogleSignInExceptionCode.interrupted => AuthFailureCode.temporary,
      GoogleSignInExceptionCode.clientConfigurationError =>
        AuthFailureCode.configuration,
      GoogleSignInExceptionCode.providerConfigurationError ||
      GoogleSignInExceptionCode.uiUnavailable =>
        AuthFailureCode.googleUnavailable,
      GoogleSignInExceptionCode.userMismatch => AuthFailureCode.accountMismatch,
      // The package explicitly permits future enum values.
      _ => AuthFailureCode.unknown,
    };

AuthFailure mapAuthFailure(
  Object error,
  StackTrace stackTrace, {
  required AuthFailureProvider provider,
  required AuthFailureStage stage,
}) {
  if (error is AuthFailure) {
    return enrichAuthFailure(
      error,
      stackTrace,
      provider: provider,
      stage: stage,
    );
  }
  final technicalCode = switch (error) {
    FirebaseAuthException() => error.code,
    GoogleSignInException() => error.code.name,
    TimeoutException() => 'timeout',
    _ => 'unknown',
  };
  final code = switch (error) {
    FirebaseAuthException() => _mapFirebaseCode(error.code),
    GoogleSignInException() => _mapGoogleCode(error.code),
    TimeoutException() => AuthFailureCode.network,
    _ => AuthFailureCode.unknown,
  };
  return AuthFailure(
    code,
    cause: error,
    stackTrace: stackTrace,
    provider: provider,
    stage: stage,
    technicalCode: technicalCode,
  );
}

AuthFailure enrichAuthFailure(
  AuthFailure failure,
  StackTrace stackTrace, {
  required AuthFailureProvider provider,
  required AuthFailureStage stage,
}) {
  final resolvedProvider = failure.provider == AuthFailureProvider.unknown
      ? provider
      : failure.provider;
  final resolvedStage = failure.stage == AuthFailureStage.unknown
      ? stage
      : failure.stage;
  final resolvedStackTrace = failure.stackTrace ?? stackTrace;
  if (resolvedProvider == failure.provider &&
      resolvedStage == failure.stage &&
      identical(resolvedStackTrace, failure.stackTrace)) {
    return failure;
  }
  return AuthFailure(
    failure.code,
    cause: failure.cause,
    stackTrace: resolvedStackTrace,
    provider: resolvedProvider,
    stage: resolvedStage,
    technicalCode: failure.technicalCode,
  );
}

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => FirebaseAuthGateway(FirebaseAuth.instance),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => DefaultAuthRepository(ref.watch(authGatewayProvider)),
);

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).userChanges(),
);

/// Identidad síncrona durante el breve arranque del stream. Firebase mantiene
/// [currentUser], así que no hay que tratar una sesión restaurada como ausente.
final currentAppUserProvider = Provider<AppUser?>((ref) {
  final streamed = ref.watch(authStateProvider).value;
  return streamed ?? ref.watch(authRepositoryProvider).currentUser;
});

/// Fuente única del UID para dependencias de datos. Al cambiar de cuenta,
/// Riverpod recrea los repositorios y cancela sus listeners anteriores.
final currentUserIdProvider = Provider<String>((ref) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null) throw StateError('No hay una identidad activa');
  return user.uid;
});
