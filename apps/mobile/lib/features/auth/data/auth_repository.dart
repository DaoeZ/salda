import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Usuario de la app (no filtramos el tipo de firebase_auth a la UI).
class AppUser {
  const AppUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;
}

/// Errores de auth tipificados para mensajes claros en la UI.
class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final String code; // invalid-credential | email-already-in-use | weak-password | network | unknown
}

/// Puerto de autenticación. Google Sign-In se añade cuando existan los
/// proyectos Firebase reales (`flutterfire configure`): contra el emulador
/// solo tiene sentido email+contraseña, y la UI oculta el botón de Google
/// hasta entonces (flag [googleSignInAvailable]).
abstract interface class AuthRepository {
  static const googleSignInAvailable = false; // se activa con proyecto real

  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<void> signIn(String email, String password);
  Future<void> register(String email, String password, String displayName);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  AppUser? _map(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        );

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<void> signIn(String email, String password) => _guard(() =>
      _auth.signInWithEmailAndPassword(email: email, password: password));

  @override
  Future<void> register(
      String email, String password, String displayName) async {
    await _guard(() async {
      final credential = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      await credential.user?.updateDisplayName(displayName);
    });
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() => _auth.signOut();

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-email' =>
          'invalid-credential',
        'email-already-in-use' => 'email-already-in-use',
        'weak-password' => 'weak-password',
        'network-request-failed' => 'network',
        _ => 'unknown',
      });
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => FirebaseAuthRepository(FirebaseAuth.instance));

final authStateProvider = StreamProvider<AppUser?>(
    (ref) => ref.watch(authRepositoryProvider).authStateChanges());
