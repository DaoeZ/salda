import 'dart:convert';

/// Estado persistido de una relación social entre dos UID.
enum FriendshipStatus { pending, friends }

/// Estado contextual que ve [viewerUid] en la interfaz.
enum FriendshipRelationState { none, outgoing, incoming, friends }

/// Una única relación canónica por pareja. Los nombres y usernames no forman
/// parte del vínculo: se leen siempre desde `profiles/{uid}`.
class Friendship {
  const Friendship({
    required this.id,
    required this.memberUids,
    required this.requesterUid,
    required this.receiverUid,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
  });

  final String id;
  final List<String> memberUids;
  final String requesterUid;
  final String receiverUid;
  final FriendshipStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;

  bool involves(String uid) => memberUids.contains(uid);

  String otherUid(String viewerUid) {
    if (!involves(viewerUid)) {
      throw ArgumentError.value(
        viewerUid,
        'viewerUid',
        'No pertenece al vínculo',
      );
    }
    return memberUids.firstWhere((uid) => uid != viewerUid);
  }

  FriendshipRelationState relationFor(String viewerUid) {
    if (!involves(viewerUid)) return FriendshipRelationState.none;
    if (status == FriendshipStatus.friends) {
      return FriendshipRelationState.friends;
    }
    return requesterUid == viewerUid
        ? FriendshipRelationState.outgoing
        : FriendshipRelationState.incoming;
  }
}

List<String> canonicalFriendshipMembers(String firstUid, String secondUid) {
  _validateUid(firstUid);
  _validateUid(secondUid);
  if (firstUid == secondUid) {
    throw ArgumentError('Una persona no puede relacionarse consigo misma');
  }
  return firstUid.compareTo(secondUid) < 0
      ? [firstUid, secondUid]
      : [secondUid, firstUid];
}

String canonicalFriendshipId(String firstUid, String secondUid) =>
    _encodeMembers(canonicalFriendshipMembers(firstUid, secondUid));

String _encodeMembers(List<String> members) {
  // Prefijar longitudes hace la serialización no ambigua incluso si un UID
  // contiene separadores. Rules reproduce exactamente esta cadena.
  final serialized = members.map((uid) => '${uid.runes.length}:$uid').join();
  return utf8
      .encode(serialized)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

void _validateUid(String uid) {
  if (uid.isEmpty || uid.runes.length > 128) {
    throw ArgumentError.value(uid, 'uid', 'UID no compatible con relaciones');
  }
}
