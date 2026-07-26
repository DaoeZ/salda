import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
// flutter_riverpod no re-exporta Override en v3: viene del core.
import 'package:riverpod/misc.dart' show Override;
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/friends/data/friendship_repository.dart';
import 'package:salda_mobile/features/people/data/frequent_people_repository.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/data/session_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user});

  AppUser? user;
  final _controller = StreamController<AppUser?>.broadcast();

  @override
  Stream<AppUser?> userChanges() async* {
    yield user;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => user;

  @override
  Future<void> signIn(String email, String password) async {
    user = AppUser(uid: 'owner', email: email, displayName: 'Edgar');
    _controller.add(user);
  }

  @override
  Future<void> register(
    String email,
    String password,
    String displayName,
  ) async {
    user = AppUser(
      uid: user?.isAnonymous ?? false ? user!.uid : 'owner',
      email: email,
      displayName: displayName,
      emailVerified: false,
    );
    _controller.add(user);
  }

  @override
  Future<void> signInWithGoogle() async {
    user = AppUser(
      uid: user?.isAnonymous ?? false ? user!.uid : 'google-owner',
      email: 'google@salda.test',
      displayName: 'Google User',
      providerIds: const {'google.com'},
    );
    _controller.add(user);
  }

  @override
  Future<void> signInAsGuest() async {
    user = const AppUser(
      uid: 'guest-owner',
      isAnonymous: true,
      emailVerified: false,
    );
    _controller.add(user);
  }

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<bool> refreshEmailVerification() async => user?.emailVerified ?? false;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    user = null;
    _controller.add(null);
  }
}

/// Overrides estándar para tests de widgets: usuario logueado y Firestore
/// falso en memoria (sin tocar Firebase real).
List<Override> loggedInOverrides({
  FakeFirebaseFirestore? firestore,
  SessionRepository? sessionRepository,
  // Quien mira. Casi todo se prueba desde 'owner', pero hay pantallas cuyo
  // resultado DEPENDE del lector —el titulo de una relacion (BUG-5)— y hay
  // que poder sentarse en la otra silla.
  String uid = 'owner',
  String displayName = 'Edgar',
}) {
  final fake = firestore ?? FakeFirebaseFirestore();
  return [
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        user: AppUser(uid: uid, displayName: displayName),
      ),
    ),
    sessionRepositoryProvider.overrideWithValue(
      sessionRepository ??
          FirestoreSessionRepository(
            firestore: fake,
            uid: () => uid,
            shareCodeFactory: () => 'TEST-CODE-1234567890',
          ),
    ),
    frequentPeopleRepositoryProvider.overrideWithValue(
      FrequentPeopleRepository(firestore: fake, uid: () => uid),
    ),
    profileRepositoryProvider.overrideWithValue(
      ProfileRepository(firestore: fake, uid: () => uid),
    ),
    friendshipRepositoryProvider.overrideWithValue(
      FriendshipRepository(
        firestore: fake,
        uid: () => uid,
        isFullAccount: () => true,
      ),
    ),
    spacesRepositoryProvider.overrideWithValue(
      SpacesRepository(
        firestore: fake,
        uid: () => uid,
        isFullAccount: () => true,
      ),
    ),
  ];
}
