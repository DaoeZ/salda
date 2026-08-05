import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';

void main() {
  group('DefaultAuthRepository', () {
    test('inicia sesión con email y contraseña', () async {
      final gateway = _FakeAuthGateway();
      final repository = DefaultAuthRepository(gateway);

      await repository.signIn('edgar@salda.test', 'correcta123');

      expect(gateway.calls, ['signIn:edgar@salda.test']);
      expect(repository.currentUser?.uid, 'email-user');
    });

    test('registra, guarda el nombre y envía verificación', () async {
      final gateway = _FakeAuthGateway();
      final repository = DefaultAuthRepository(gateway);

      await repository.register('edgar@salda.test', 'correcta123', 'Edgar');

      expect(gateway.calls, [
        'create:edgar@salda.test',
        'displayName:Edgar',
        'verify',
      ]);
      expect(repository.currentUser?.needsEmailVerification, isTrue);
    });

    test('reenvía el correo de verificación', () async {
      final gateway = _FakeAuthGateway();
      final repository = DefaultAuthRepository(gateway);

      await repository.sendEmailVerification();

      expect(gateway.calls, ['verify']);
    });

    test('recarga usuario y refresca el token al verificar', () async {
      final gateway = _FakeAuthGateway(
        user: const AppUser(
          uid: 'email-user',
          email: 'edgar@salda.test',
          emailVerified: false,
        ),
      )..verifiedOnReload = true;
      final repository = DefaultAuthRepository(gateway);

      expect(await repository.refreshEmailVerification(), isTrue);
      expect(gateway.calls, ['reload:true']);
      expect(repository.currentUser?.isFullAccount, isTrue);
    });

    test('inicia sesión con Google como cuenta verificada', () async {
      final gateway = _FakeAuthGateway();
      final repository = DefaultAuthRepository(gateway);

      await repository.signInWithGoogle();

      expect(gateway.calls, ['googleSignIn']);
      expect(repository.currentUser?.providerIds, contains('google.com'));
      expect(repository.currentUser?.isFullAccount, isTrue);
    });

    test('crea una identidad invitada', () async {
      final gateway = _FakeAuthGateway();
      final repository = DefaultAuthRepository(gateway);

      await repository.signInAsGuest();

      expect(gateway.calls, ['anonymous']);
      expect(repository.currentUser?.isAnonymous, isTrue);
    });

    test('convierte invitado por email conservando el UID', () async {
      final gateway = _FakeAuthGateway(
        user: const AppUser(
          uid: 'guest-stable-uid',
          isAnonymous: true,
          emailVerified: false,
        ),
      );
      final repository = DefaultAuthRepository(gateway);

      await repository.register('nuevo@salda.test', 'correcta123', 'Edgar');

      expect(gateway.calls.first, 'linkEmail:nuevo@salda.test');
      // Igual que en Google: el token se refresca justo tras vincular.
      expect(gateway.calls[1], 'reload:true');
      expect(repository.currentUser?.uid, 'guest-stable-uid');
      expect(repository.currentUser?.isAnonymous, isFalse);
      expect(repository.currentUser?.needsEmailVerification, isTrue);
    });

    test('convierte invitado con Google conservando el UID', () async {
      final gateway = _FakeAuthGateway(
        user: const AppUser(
          uid: 'guest-stable-uid',
          isAnonymous: true,
          emailVerified: false,
        ),
      );
      final repository = DefaultAuthRepository(gateway);

      await repository.signInWithGoogle();

      // El refresco del token es OBLIGATORIO tras convertir: sin él, el ID
      // token conserva `sign_in_provider: 'anonymous'` y las Rules deniegan
      // toda escritura social aunque la app se crea con cuenta completa.
      expect(gateway.calls, ['googleLink', 'reload:true']);
      expect(repository.currentUser?.uid, 'guest-stable-uid');
      expect(repository.currentUser?.isFullAccount, isTrue);
    });

    test(
      'un fallo al refrescar tras vincular Google conserva su etapa Firebase',
      () async {
        const refreshFailure = AuthFailure(
          AuthFailureCode.temporary,
          provider: AuthFailureProvider.firebase,
          stage: AuthFailureStage.tokenRefresh,
          technicalCode: 'internal-error',
        );
        final gateway = _FakeAuthGateway(
          user: const AppUser(
            uid: 'guest-stable-uid',
            isAnonymous: true,
            emailVerified: false,
          ),
        )..reloadFailure = refreshFailure;
        final repository = DefaultAuthRepository(gateway);

        await expectLater(
          repository.signInWithGoogle(),
          throwsA(same(refreshFailure)),
        );
        expect(gateway.calls, ['googleLink', 'reload:true']);
      },
    );

    test('envía recuperación de contraseña', () async {
      final gateway = _FakeAuthGateway();
      final repository = DefaultAuthRepository(gateway);

      await repository.sendPasswordReset('edgar@salda.test');

      expect(gateway.calls, ['reset:edgar@salda.test']);
    });

    test('recuperación no revela si la cuenta no existe', () async {
      final gateway = _FakeAuthGateway()
        ..resetFailure = const AuthFailure(AuthFailureCode.invalidCredential);
      final repository = DefaultAuthRepository(gateway);

      await expectLater(
        repository.sendPasswordReset('nadie@salda.test'),
        completes,
      );
      expect(gateway.calls, ['reset:nadie@salda.test']);
    });

    test('cierra sesión y permite cambiar de usuario', () async {
      final gateway = _FakeAuthGateway(user: const AppUser(uid: 'first-user'));
      final repository = DefaultAuthRepository(gateway);
      final emitted = <String?>[];
      final subscription = repository
          .userChanges()
          .map((user) => user?.uid)
          .listen(emitted.add);

      await repository.signOut();
      await repository.signIn('second@salda.test', 'correcta123');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.calls, ['signOut', 'signIn:second@salda.test']);
      expect(repository.currentUser?.uid, 'email-user');
      expect(emitted, [null, 'email-user']);
      await subscription.cancel();
    });
  });

  group('AppUser', () {
    // Regresión del bug de amistades: reloadUser re-emite un AppUser nuevo
    // en cada escritura social; sin igualdad de valor, authStateProvider
    // notificaba, el router se recreaba y la pantalla activa se cerraba.
    test('dos instancias con los mismos datos son iguales', () {
      const first = AppUser(
        uid: 'uid-a',
        email: 'a@salda.test',
        displayName: 'Alba',
        providerIds: {'password', 'google.com'},
      );
      const second = AppUser(
        uid: 'uid-a',
        email: 'a@salda.test',
        displayName: 'Alba',
        providerIds: {'google.com', 'password'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('cambiar cualquier campo relevante rompe la igualdad', () {
      const base = AppUser(uid: 'uid-a', email: 'a@salda.test');
      expect(base, isNot(const AppUser(uid: 'uid-b', email: 'a@salda.test')));
      expect(base, isNot(const AppUser(uid: 'uid-a', email: 'b@salda.test')));
      expect(
        base,
        isNot(
          const AppUser(uid: 'uid-a', email: 'a@salda.test', isAnonymous: true),
        ),
      );
      expect(
        base,
        isNot(
          const AppUser(
            uid: 'uid-a',
            email: 'a@salda.test',
            emailVerified: false,
          ),
        ),
      );
    });
  });
}

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({this.user});

  AppUser? user;
  bool verifiedOnReload = false;
  AuthFailure? resetFailure;
  AuthFailure? reloadFailure;
  final calls = <String>[];
  final _changes = StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser => user;

  @override
  Stream<AppUser?> userChanges() => _changes.stream;

  @override
  Future<AppUser> signInWithEmail(String email, String password) async {
    calls.add('signIn:$email');
    return _set(
      AppUser(uid: 'email-user', email: email, providerIds: const {'password'}),
    );
  }

  @override
  Future<AppUser> createEmailAccount(String email, String password) async {
    calls.add('create:$email');
    return _set(
      AppUser(
        uid: 'email-user',
        email: email,
        emailVerified: false,
        providerIds: const {'password'},
      ),
    );
  }

  @override
  Future<AppUser> linkEmailAccount(String email, String password) async {
    calls.add('linkEmail:$email');
    return _set(
      AppUser(
        uid: user!.uid,
        email: email,
        emailVerified: false,
        providerIds: const {'password'},
      ),
    );
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    calls.add('googleSignIn');
    return _set(
      const AppUser(
        uid: 'google-user',
        email: 'google@salda.test',
        providerIds: {'google.com'},
      ),
    );
  }

  @override
  Future<AppUser> linkGoogleAccount() async {
    calls.add('googleLink');
    return _set(
      AppUser(
        uid: user!.uid,
        email: 'google@salda.test',
        providerIds: const {'google.com'},
      ),
    );
  }

  @override
  Future<AppUser> signInAnonymously() async {
    calls.add('anonymous');
    return _set(
      const AppUser(uid: 'guest-user', isAnonymous: true, emailVerified: false),
    );
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    calls.add('displayName:$displayName');
    user = AppUser(
      uid: user!.uid,
      email: user!.email,
      displayName: displayName,
      isAnonymous: user!.isAnonymous,
      emailVerified: user!.emailVerified,
      providerIds: user!.providerIds,
    );
    _changes.add(user);
  }

  @override
  Future<void> sendEmailVerification() async {
    calls.add('verify');
  }

  @override
  Future<AppUser?> reloadUser({required bool refreshToken}) async {
    calls.add('reload:$refreshToken');
    if (reloadFailure case final failure?) throw failure;
    if (user != null && verifiedOnReload) {
      user = AppUser(
        uid: user!.uid,
        email: user!.email,
        displayName: user!.displayName,
        emailVerified: true,
        providerIds: user!.providerIds,
      );
      _changes.add(user);
    }
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('reset:$email');
    if (resetFailure case final failure?) throw failure;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    user = null;
    _changes.add(null);
  }

  AppUser _set(AppUser value) {
    user = value;
    _changes.add(value);
    return value;
  }
}
