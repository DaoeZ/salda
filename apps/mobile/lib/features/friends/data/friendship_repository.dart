import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/friendship.dart';

enum FriendshipFailureCode {
  accountRequired,
  profileRequired,
  targetUnavailable,
  selfRequest,
  notAllowed,
  malformedData,
}

class FriendshipFailure implements Exception {
  const FriendshipFailure(this.code);

  final FriendshipFailureCode code;
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
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final bool Function() isFullAccount;

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

  Future<void> sendRequest(String otherUid) async {
    _requireAccount();
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

  Future<void> acceptRequest(String otherUid) =>
      _resolvePending(otherUid, requireReceiver: true, accept: true);

  Future<void> rejectRequest(String otherUid) =>
      _resolvePending(otherUid, requireReceiver: true, accept: false);

  Future<void> cancelRequest(String otherUid) =>
      _resolvePending(otherUid, requireReceiver: false, accept: false);

  Future<void> _resolvePending(
    String otherUid, {
    required bool requireReceiver,
    required bool accept,
  }) async {
    _requireAccount();
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

  Future<void> removeFriend(String otherUid) async {
    _requireAccount();
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
  );
});

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
