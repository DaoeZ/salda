import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/friendship.dart';

enum FriendshipFailureCode {
  accountRequired,
  unverifiedAccount,
  profileRequired,
  targetUnavailable,
  selfRequest,
  requestAlreadyExists,
  alreadyFriends,
  permissionDenied,
  serviceUnavailable,
  network,
  notAllowed,
  malformedData,
  unexpected,
}

class FriendshipFailure implements Exception {
  const FriendshipFailure(this.code, {this.technicalCode});

  final FriendshipFailureCode code;

  /// Código estable del SDK, útil para soporte sin registrar datos personales.
  final String? technicalCode;
}

/// Fuente única de verdad social: `friendships/{uidMenor}~{uidMayor}`.
///
/// Todas las mutaciones son transacciones. Dos solicitudes cruzadas convergen
/// en amistad; repetir cualquier acción es idempotente y nunca crea otro doc.
class FriendshipRepository {
  FriendshipRepository({
    required this.firestore,
    required this.uid,
    required this.isFullAccount,
    this.refreshAccount,
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final bool Function() isFullAccount;

  /// Refresca el usuario y su ID token antes de una escritura social.
  ///
  /// Firebase Auth puede conocer localmente que el correo está verificado y
  /// mantener todavía un token anterior. Las Rules solo ven el token.
  final Future<bool> Function()? refreshAccount;

  CollectionReference<Map<String, dynamic>> get _collection =>
      firestore.collection('friendships');

  DocumentReference<Map<String, dynamic>> _document(String otherUid) =>
      _collection.doc(canonicalFriendshipId(uid(), otherUid));

  Stream<List<Friendship>> watchAll() {
    _requireAccount();
    final currentUid = uid();
    return _collection
        .where('memberUids', arrayContains: currentUid)
        .snapshots()
        .map((snapshot) {
          final relationships = snapshot.docs.map(_fromSnapshot).toList();
          relationships.sort((a, b) {
            final byTime =
                (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    );
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
          return relationships;
        });
  }

  Future<void> sendRequest(String otherUid) =>
      _guard(() => _sendRequest(otherUid));

  Future<void> _sendRequest(String otherUid) async {
    await _prepareWrite();
    final currentUid = uid();
    if (currentUid == otherUid) {
      throw const FriendshipFailure(FriendshipFailureCode.selfRequest);
    }
    final members = canonicalFriendshipMembers(currentUid, otherUid);
    final relationship = _document(otherUid);
    await firestore.runTransaction((transaction) async {
      final ownProfile = await transaction.get(
        firestore.collection('profiles').doc(currentUid),
      );
      final targetProfile = await transaction.get(
        firestore.collection('profiles').doc(otherUid),
      );
      if (!ownProfile.exists) {
        throw const FriendshipFailure(FriendshipFailureCode.profileRequired);
      }
      if (!targetProfile.exists) {
        throw const FriendshipFailure(FriendshipFailureCode.targetUnavailable);
      }

      final snapshot = await transaction.get(relationship);
      if (!snapshot.exists) {
        transaction.set(relationship, {
          'memberUids': members,
          'requesterUid': currentUid,
          'receiverUid': otherUid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'schemaVersion': 1,
        });
        return;
      }

      final current = _fromSnapshot(snapshot);
      if (current.status == FriendshipStatus.friends ||
          current.requesterUid == currentUid) {
        return;
      }
      // Solicitud cruzada: quien era receptor acepta de forma determinista.
      if (current.receiverUid == currentUid &&
          current.requesterUid == otherUid) {
        transaction.update(relationship, {
          'status': 'friends',
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      throw const FriendshipFailure(FriendshipFailureCode.malformedData);
    });
  }

  Future<void> acceptRequest(String otherUid) => _guard(
    () => _resolvePending(otherUid, requireReceiver: true, accept: true),
  );

  Future<void> rejectRequest(String otherUid) => _guard(
    () => _resolvePending(otherUid, requireReceiver: true, accept: false),
  );

  Future<void> cancelRequest(String otherUid) => _guard(
    () => _resolvePending(otherUid, requireReceiver: false, accept: false),
  );

  Future<void> _resolvePending(
    String otherUid, {
    required bool requireReceiver,
    required bool accept,
  }) async {
    await _prepareWrite();
    final currentUid = uid();
    final relationship = _document(otherUid);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(relationship);
      if (!snapshot.exists) return;
      final current = _fromSnapshot(snapshot);
      if (current.status == FriendshipStatus.friends) return;
      final actorUid = requireReceiver
          ? current.receiverUid
          : current.requesterUid;
      if (actorUid != currentUid) {
        throw const FriendshipFailure(FriendshipFailureCode.notAllowed);
      }
      if (accept) {
        transaction.update(relationship, {
          'status': 'friends',
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.delete(relationship);
      }
    });
  }

  Future<void> removeFriend(String otherUid) =>
      _guard(() => _removeFriend(otherUid));

  Future<void> _removeFriend(String otherUid) async {
    await _prepareWrite();
    final currentUid = uid();
    final relationship = _document(otherUid);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(relationship);
      if (!snapshot.exists) return;
      final current = _fromSnapshot(snapshot);
      if (current.status != FriendshipStatus.friends ||
          !current.involves(currentUid)) {
        throw const FriendshipFailure(FriendshipFailureCode.notAllowed);
      }
      transaction.delete(relationship);
    });
  }

  void _requireAccount() {
    if (!isFullAccount()) {
      throw const FriendshipFailure(FriendshipFailureCode.accountRequired);
    }
  }

  Future<void> _prepareWrite() async {
    _requireAccount();
    final refresh = refreshAccount;
    if (refresh == null) return;
    try {
      if (!await refresh()) {
        throw const FriendshipFailure(FriendshipFailureCode.unverifiedAccount);
      }
    } on AuthFailure catch (error, stackTrace) {
      final mapped = FriendshipFailure(
        error.code == AuthFailureCode.network
            ? FriendshipFailureCode.network
            : FriendshipFailureCode.unexpected,
        technicalCode: error.code.name,
      );
      Error.throwWithStackTrace(mapped, stackTrace);
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FriendshipFailure {
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        mapFriendshipFirebaseFailure(error),
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FriendshipFailure(
          FriendshipFailureCode.unexpected,
          technicalCode: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }
  }

  Friendship _fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw const FriendshipFailure(FriendshipFailureCode.malformedData);
    }
    final memberUids = (data['memberUids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final status = switch (data['status']) {
      'pending' => FriendshipStatus.pending,
      'friends' => FriendshipStatus.friends,
      _ => throw const FriendshipFailure(FriendshipFailureCode.malformedData),
    };
    final requesterUid = data['requesterUid'] as String?;
    final receiverUid = data['receiverUid'] as String?;
    if (memberUids.length != 2 ||
        requesterUid == null ||
        receiverUid == null ||
        !memberUids.contains(requesterUid) ||
        !memberUids.contains(receiverUid) ||
        requesterUid == receiverUid) {
      throw const FriendshipFailure(FriendshipFailureCode.malformedData);
    }
    return Friendship(
      id: snapshot.id,
      memberUids: memberUids,
      requesterUid: requesterUid,
      receiverUid: receiverUid,
      status: status,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
    );
  }
}

final friendshipRepositoryProvider = Provider<FriendshipRepository>((ref) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null) throw StateError('No hay una identidad activa');
  return FriendshipRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => user.uid,
    isFullAccount: () => user.isFullAccount,
    refreshAccount: () =>
        ref.read(authRepositoryProvider).refreshEmailVerification(),
  );
});

/// Traduce los códigos reales de Firestore sin disfrazar permisos como red.
FriendshipFailure mapFriendshipFirebaseFailure(FirebaseException error) {
  final code = switch (error.code) {
    'unauthenticated' => FriendshipFailureCode.unverifiedAccount,
    'permission-denied' => FriendshipFailureCode.permissionDenied,
    'already-exists' => FriendshipFailureCode.requestAlreadyExists,
    'unavailable' ||
    'deadline-exceeded' ||
    'network-request-failed' => FriendshipFailureCode.network,
    'failed-precondition' ||
    'unimplemented' => FriendshipFailureCode.serviceUnavailable,
    _ => FriendshipFailureCode.unexpected,
  };
  return FriendshipFailure(code, technicalCode: error.code);
}

final friendshipsProvider = StreamProvider.autoDispose<List<Friendship>>((ref) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null || !user.isFullAccount) return Stream.value(const []);
  return ref.watch(friendshipRepositoryProvider).watchAll();
});

final friendshipWithProvider = Provider.autoDispose
    .family<AsyncValue<Friendship?>, String>((ref, otherUid) {
      return ref.watch(friendshipsProvider).whenData((relationships) {
        for (final relationship in relationships) {
          if (relationship.involves(otherUid)) return relationship;
        }
        return null;
      });
    });
