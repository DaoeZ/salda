import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/application/social_account.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';

/// La cuenta real entra con Google, tiene el correo verificado y en Ajustes
/// se ve bien — pero `canUseSocial()` la rechaza. Aquí se prueba cada
/// precondición por separado y la reparación del único caso recuperable.
void main() {
  const uid = 'uid-google';

  late FakeFirebaseFirestore firestore;
  late ProfileRepository profiles;

  ProfileRepository repoFor(String id) =>
      ProfileRepository(firestore: firestore, uid: () => id);

  SocialAccountService service(_FakeAuth auth, {ProfileRepository? repo}) =>
      SocialAccountService(auth: auth, profiles: repo ?? profiles);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    profiles = repoFor(uid);
  });

  /// Cuenta de Google tal y como llega: nombre y correo ya rellenos por el
  /// proveedor, correo verificado desde el primer segundo.
  _FakeAuth google({
    bool verified = true,
    String? displayName = 'Edgar Cantera',
  }) => _FakeAuth(
    AppUser(
      uid: uid,
      displayName: displayName,
      email: 'edgar@example.test',
      emailVerified: verified,
    ),
  );

  Future<void> perfilPublico({String username = 'edgar'}) => firestore
      .doc('profiles/$uid')
      .set({'displayName': 'Edgar', 'username': username, 'schemaVersion': 1});

  test('cuenta de Google CON perfil público ya está lista', () async {
    await perfilPublico();
    final estado = await service(google()).prepare();
    expect(estado.readiness, SocialReadiness.ready);
    expect(estado.repaired, isFalse);
  });

  test('SIN perfil público lo crea y queda lista', () async {
    // Esta es la cuenta real: entrar con Google nunca creó `profiles/{uid}`.
    final estado = await service(google()).prepare();
    expect(estado.readiness, SocialReadiness.ready);
    expect(estado.repaired, isTrue);

    final creado = await firestore.doc('profiles/$uid').get();
    expect(creado.exists, isTrue);
    expect(creado.data()!['displayName'], 'Edgar Cantera');
    expect((creado.data()!['username'] as String), isNotEmpty);
    // Y el claim del username queda reservado para esta cuenta.
    final claim = await firestore
        .doc('usernames/${creado.data()!['username']}')
        .get();
    expect(claim.data()!['uid'], uid);
  });

  test('la reparación es IDEMPOTENTE', () async {
    final primero = await service(google()).prepare();
    final segundo = await service(google()).prepare();

    expect(primero.repaired, isTrue);
    // La segunda vez ya no repara nada: encuentra el perfil y sigue.
    expect(segundo.readiness, SocialReadiness.ready);
    expect(segundo.repaired, isFalse);
    // Un solo perfil y un solo claim, sin duplicados.
    expect((await firestore.collection('profiles').get()).docs.length, 1);
    expect((await firestore.collection('usernames').get()).docs.length, 1);
  });

  test('no se apropia del username de otra persona', () async {
    // El username que saldría del nombre ya es de otra cuenta.
    await firestore.doc('usernames/edgar').set({'uid': 'uid-otra-persona'});
    await firestore.doc('profiles/uid-otra-persona').set({
      'displayName': 'Edgar',
      'username': 'edgar',
    });

    final estado = await service(google()).prepare();
    expect(estado.readiness, SocialReadiness.ready);

    final mio = await firestore.doc('profiles/$uid').get();
    expect(mio.data()!['username'], isNot('edgar'));
    // El claim ajeno sigue siendo suyo.
    final ajeno = await firestore.doc('usernames/edgar').get();
    expect(ajeno.data()!['uid'], 'uid-otra-persona');
  });

  test('perfil LEGACY existente no se sobrescribe', () async {
    await perfilPublico(username: 'edgar_viejo');
    final estado = await service(google()).prepare();

    expect(estado.readiness, SocialReadiness.ready);
    expect(estado.repaired, isFalse);
    final perfil = await firestore.doc('profiles/$uid').get();
    // Ni el nombre ni el username válidos se tocan.
    expect(perfil.data()!['username'], 'edgar_viejo');
    expect(perfil.data()!['displayName'], 'Edgar');
  });

  test('correo sin verificar: se intenta refrescar y se informa', () async {
    final auth = google(verified: false);
    final estado = await service(auth).prepare();
    expect(estado.readiness, SocialReadiness.emailNotVerified);
    // Se intentó renovar el token antes de rendirse.
    expect(auth.refrescos, 1);
  });

  test('claim antiguo en token pero verificado al refrescar: queda lista', () {
    return () async {
      final auth = google(verified: false)..verificaAlRefrescar = true;
      final estado = await service(auth).prepare();
      expect(estado.readiness, SocialReadiness.ready);
      expect(auth.refrescos, 1);
    }();
  });

  test('sesión anónima sigue rechazada', () async {
    final auth = _FakeAuth(
      const AppUser(uid: 'guest', isAnonymous: true, emailVerified: false),
    );
    final estado = await service(auth).prepare();
    expect(estado.readiness, SocialReadiness.anonymous);
    // No se intenta reparar nada para un invitado.
    expect((await firestore.collection('profiles').get()).docs, isEmpty);
  });

  test('sin sesión no se toca nada', () async {
    final estado = await service(_FakeAuth(null)).prepare();
    expect(estado.readiness, SocialReadiness.notSignedIn);
  });

  test('sin nombre ni correo no se inventa un perfil', () async {
    final auth = _FakeAuth(const AppUser(uid: uid, emailVerified: true));
    final estado = await service(auth).prepare();
    expect(estado.readiness, SocialReadiness.publicProfileMissing);
    expect((await firestore.collection('profiles').get()).docs, isEmpty);
  });

  test('sin displayName usa la parte local del correo', () async {
    final estado = await service(google(displayName: null)).prepare();
    expect(estado.readiness, SocialReadiness.ready);
    final perfil = await firestore.doc('profiles/$uid').get();
    expect(perfil.data()!['displayName'], 'edgar');
  });
}

/// Auth mínimo: lo único que necesita el servicio es el usuario actual y
/// poder renovar sus credenciales.
class _FakeAuth implements AuthRepository {
  _FakeAuth(this._user);

  AppUser? _user;
  int refrescos = 0;
  bool verificaAlRefrescar = false;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<bool> refreshEmailVerification() async {
    refrescos++;
    if (verificaAlRefrescar && _user != null) {
      _user = AppUser(
        uid: _user!.uid,
        displayName: _user!.displayName,
        email: _user!.email,
        emailVerified: true,
      );
    }
    return _user?.emailVerified ?? false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa aquí');
}
