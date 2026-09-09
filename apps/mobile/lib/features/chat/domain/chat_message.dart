/// Mensaje de chat contextual (P7, ADR-032).
///
/// La identidad siempre es UID y el nombre se resuelve en vivo. El mensaje no
/// es actividad ni fuente económica: borrarlo no altera ningún otro agregado.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorUid,
    required this.text,
    this.createdAt,
    this.hasPendingWrites = false,
  });

  final String id;
  final String authorUid;
  final String text;
  final DateTime? createdAt;
  final bool hasPendingWrites;
}

enum ChatFailureCode { notMember, emptyMessage, messageTooLong }

class ChatFailure implements Exception {
  const ChatFailure(this.code);

  final ChatFailureCode code;
}
