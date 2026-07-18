import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

/// Identidad pública (P2): perfil en `profiles/{uid}` + claim de unicidad en
/// `usernames/{username}`. El username es SIEMPRE minúsculas (case-insensitive
/// por construcción) y ambos documentos se escriben en el mismo batch: las
/// reglas exigen con getAfter() que queden consistentes.
///
/// El modelo está pensado para crecer (bio, estadísticas, amigos, espacios)
/// añadiendo campos/colecciones, nunca renombrando: `schemaVersion` marca la
/// forma vigente y las reglas rechazan campos aún sin fase.
class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.displayName,
    required this.username,
    this.photoPath,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String username;

  /// Ruta en Storage de la foto de perfil (infraestructura preparada;
  /// la UI de subida llega en una fase posterior). Null = avatar generado.
  final String? photoPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static PublicProfile? fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return null;
    return PublicProfile(
      uid: snapshot.id,
      displayName: (data['displayName'] as String?) ?? '',
      username: (data['username'] as String?) ?? '',
      photoPath: data['photoPath'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Resultado de comprobar un username: separa "no disponible" de "inválido"
/// para que la UI explique el motivo exacto.
sealed class UsernameCheck {
  const UsernameCheck();
}

class UsernameOk extends UsernameCheck {
  const UsernameOk();
}

class UsernameInvalid extends UsernameCheck {
  const UsernameInvalid(this.error);

  final UsernameError error;
}

class UsernameTaken extends UsernameCheck {
  const UsernameTaken();
}

class ProfileRepository {
  ProfileRepository({
    required this.firestore,
    required this.uid,
    Random? random,
  }) : _random = random ?? Random();

  final FirebaseFirestore firestore;
  final String Function() uid;
  final Random _random;

  static const int searchLimit = 10;

  DocumentReference<Map<String, dynamic>> _profileDoc(String id) =>
      firestore.collection('profiles').doc(id);

  DocumentReference<Map<String, dynamic>> _claimDoc(String username) =>
      firestore.collection('usernames').doc(username);

  Stream<PublicProfile?> watchMyProfile() =>
      _profileDoc(uid()).snapshots().map(PublicProfile.fromSnapshot);

  Stream<PublicProfile?> watchProfile(String profileUid) =>
      _profileDoc(profileUid).snapshots().map(PublicProfile.fromSnapshot);

  Future<PublicProfile?> fetchProfile(String profileUid) async =>
      PublicProfile.fromSnapshot(await _profileDoc(profileUid).get());

  /// Valida forma + reservados y después consulta el claim. Un claim propio
  /// cuenta como disponible (conservar el username actual al editar).
  Future<UsernameCheck> checkUsername(String input) async {
    final username = normalizeUsername(input);
    final error = validateUsername(username);
    if (error != null) return UsernameInvalid(error);
    final claim = await _claimDoc(username).get();
    if (!claim.exists || claim.data()?['uid'] == uid()) {
      return const UsernameOk();
    }
    return const UsernameTaken();
  }

  /// Primer candidato NATURAL libre para [displayName] (edgar → edgar27 →
  /// edgar_cantera → …). Los candidatos vienen del dominio; aquí solo se
  /// consulta disponibilidad en orden.
  Future<String> suggestUsername(String displayName) async {
    final candidates = usernameCandidates(
      displayName,
      nextInt: _random.nextInt,
    );
    for (final candidate in candidates) {
      if (await checkUsername(candidate) is UsernameOk) return candidate;
    }
    // Todos ocupados (improbable con 10 variantes): el usuario decide a mano.
    return candidates.last;
  }

  /// Alta atómica de perfil + claim. Lanza si el username no es válido:
  /// la UI valida antes; esto es la última línea de defensa local.
  Future<void> createProfile({
    required String displayName,
    required String username,
  }) async {
    final canonical = normalizeUsername(username);
    _requireValid(canonical);
    final batch = firestore.batch();
    batch.set(_profileDoc(uid()), {
      'displayName': displayName.trim(),
      'displayNameLower': searchableText(displayName),
      'username': canonical,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    batch.set(_claimDoc(canonical), {
      'uid': uid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Edición. Si cambia el username, el batch libera el claim anterior y
  /// reclama el nuevo (atómico: nunca hay dos claims del mismo perfil).
  Future<void> updateProfile({
    required String displayName,
    required String username,
  }) async {
    final canonical = normalizeUsername(username);
    _requireValid(canonical);
    final current = await fetchProfile(uid());
    if (current == null) {
      return createProfile(displayName: displayName, username: canonical);
    }
    final batch = firestore.batch();
    if (canonical != current.username) {
      batch.delete(_claimDoc(current.username));
      batch.set(_claimDoc(canonical), {
        'uid': uid(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_profileDoc(uid()), {
      'displayName': displayName.trim(),
      'displayNameLower': searchableText(displayName),
      'username': canonical,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Búsqueda por prefijo sobre `username` y `displayNameLower` (queries de
  /// campo único: índices automáticos, sin composites). La web podrá usar
  /// exactamente las mismas queries.
  Future<List<PublicProfile>> search(String rawQuery) async {
    // '@edgar' busca el username 'edgar'.
    final text = searchableText(rawQuery.replaceFirst(RegExp(r'^@'), ''));
    if (text.isEmpty) return const [];
    final byUsername = _prefixQuery('username', text.replaceAll(' ', ''));
    final byName = _prefixQuery('displayNameLower', text);
    final results = await Future.wait([byUsername, byName]);
    final seen = <String>{};
    final merged = <PublicProfile>[
      for (final snap in results.expand((r) => r.docs))
        if (seen.add(snap.id)) ?PublicProfile.fromSnapshot(snap),
    ];
    merged.sort((a, b) => a.username.compareTo(b.username));
    return merged;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _prefixQuery(
    String field,
    String prefix,
  ) => firestore
      .collection('profiles')
      .orderBy(field)
      .startAt([prefix])
      // \uf8ff (último code point útil): cierre del rango de prefijo.
      .endAt(['$prefix\uf8ff'])
      .limit(searchLimit)
      .get();

  void _requireValid(String username) {
    final error = validateUsername(username);
    if (error != null) {
      throw ArgumentError('username inválido: ${error.name}');
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return ProfileRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => uid,
  );
});

/// Perfil público del usuario activo. Null = todavía no lo ha creado
/// (Home muestra el aviso de completar perfil solo a cuentas completas).
final myProfileProvider = StreamProvider.autoDispose<PublicProfile?>((ref) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null || !user.isFullAccount) return Stream.value(null);
  return ref.watch(profileRepositoryProvider).watchMyProfile();
});

/// Perfil público ajeno en tiempo real. Los cambios de nombre o username se
/// reflejan sin copiar snapshots en la relación de amistad.
final publicProfileProvider = StreamProvider.autoDispose
    .family<PublicProfile?, String>((ref, profileUid) {
      return ref.watch(profileRepositoryProvider).watchProfile(profileUid);
    });
