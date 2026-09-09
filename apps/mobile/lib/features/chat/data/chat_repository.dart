import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/chat_message.dart';

/// Chat contextual (P7): mensajes directos dentro de un espacio.
///
/// Toda lectura usa `createdAt >= joinedAt`. No es un filtro cosmético: esa
/// cota forma parte de la autorización de Rules y evita que una incorporación
/// nueva herede conversación privada anterior.
class ChatRepository {
  ChatRepository({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String Function() uid;

  static const int pageSize = 40;
  static const int maxMessageLength = 2000;

  CollectionReference<Map<String, dynamic>> _messages(String spaceId) =>
      firestore.collection('spaces').doc(spaceId).collection('messages');

  Future<DateTime> _joinedAt(String spaceId) async {
    final member = await firestore
        .collection('spaces')
        .doc(spaceId)
        .collection('members')
        .doc(uid())
        .get();
    final joinedAt = member.data()?['joinedAt'] as Timestamp?;
    if (!member.exists || joinedAt == null) {
      throw const ChatFailure(ChatFailureCode.notMember);
    }
    return joinedAt.toDate();
  }

  Query<Map<String, dynamic>> _base(String spaceId, DateTime joinedAt) =>
      _messages(spaceId)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(joinedAt),
          )
          .orderBy('createdAt', descending: true);

  /// Primera página EN VIVO, devuelta en orden de conversación (antiguo→nuevo).
  Stream<List<ChatMessage>> watchFirstPage(String spaceId) =>
      Stream.fromFuture(_joinedAt(spaceId))
          .asyncExpand(
            (joinedAt) => _base(spaceId, joinedAt).limit(pageSize).snapshots(),
          )
          .map(
            (snapshot) =>
                snapshot.docs.map(_fromDoc).toList().reversed.toList(),
          );

  /// Mensajes anteriores a [before], leídos bajo demanda y ordenados para UI.
  Future<List<ChatMessage>> fetchOlder(String spaceId, DateTime before) async {
    final joinedAt = await _joinedAt(spaceId);
    final snapshot = await _messages(spaceId)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(joinedAt),
        )
        .where('createdAt', isLessThan: Timestamp.fromDate(before))
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .get();
    return snapshot.docs.map(_fromDoc).toList().reversed.toList();
  }

  Future<String> send(String spaceId, String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) {
      throw const ChatFailure(ChatFailureCode.emptyMessage);
    }
    if (text.length > maxMessageLength) {
      throw const ChatFailure(ChatFailureCode.messageTooLong);
    }
    final message = _messages(spaceId).doc();
    await message.set({
      'authorUid': uid(),
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    return message.id;
  }

  Future<void> delete(String spaceId, String messageId) =>
      _messages(spaceId).doc(messageId).delete();

  ChatMessage _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    return ChatMessage(
      id: document.id,
      authorUid: (data['authorUid'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      hasPendingWrites: document.metadata.hasPendingWrites,
    );
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return ChatRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => userId,
  );
});

final currentChatUserIdProvider = Provider<String>(
  (ref) => ref.watch(chatRepositoryProvider).uid(),
);

final spaceChatProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>(
      (ref, spaceId) =>
          ref.watch(chatRepositoryProvider).watchFirstPage(spaceId),
    );
