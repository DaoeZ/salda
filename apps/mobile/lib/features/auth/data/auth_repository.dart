import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
  cancelled,
  unknown,
}

/// Error estable y presentable: la UI nunca depende de códigos de Firebase.
class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;
}

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
  FirebaseAuthGateway(this._auth, {GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
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
  );

  @override
  Future<AppUser> createEmailAccount(String email, String password) => _guard(
    () async => _required(
      (await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      )).user,
    ),
  );

  @override
  Future<AppUser> linkEmailAccount(String email, String password) => _guard(
    () async => _required(
      (await _requiredFirebaseUser().linkWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      )).user,
    ),
  );

  @override
  Future<AppUser> signInWithGoogle() => _guard(() async {
    final credential = await _googleCredential();
    return _required((await _auth.signInWithCredential(credential)).user);
  });

  @override
  Future<AppUser> linkGoogleAccount() => _guard(() async {
    final credential = await _googleCredential();
    return _required(
      (await _requiredFirebaseUser().linkWithCredential(credential)).user,
    );
  });

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
  });

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
    await _googleInitialization;
    final account = await _googleSignIn.authenticate();
    final authentication = account.authentication;
    return GoogleAuthProvider.credential(idToken: authentication.idToken);
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

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_mapFirebaseCode(error.code));
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure(AuthFailureCode.cancelled);
      }
      throw const AuthFailure(AuthFailureCode.unknown);
    } on TimeoutException {
      throw const AuthFailure(AuthFailureCode.network);
    } on Object {
      throw const AuthFailure(AuthFailureCode.unknown);
    }
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
  'invalid-email' => AuthFailureCode.invalidCredential,
  'email-already-in-use' => AuthFailureCode.emailAlreadyInUse,
  'weak-password' => AuthFailureCode.weakPassword,
  'network-request-failed' => AuthFailureCode.network,
  'too-many-requests' => AuthFailureCode.tooManyRequests,
  'user-disabled' => AuthFailureCode.userDisabled,
  'operation-not-allowed' => AuthFailureCode.operationNotAllowed,
  'credential-already-in-use' || 'account-exists-with-different-credential' =>
    AuthFailureCode.credentialAlreadyInUse,
  _ => AuthFailureCode.unknown,
};

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
