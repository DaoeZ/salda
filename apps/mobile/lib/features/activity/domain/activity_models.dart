/// Actividad (P6, ADR-030): cronología de auditoría derivada. NUNCA es la
/// fuente de verdad: cada evento enlaza al objeto original (espacio, sesión/
/// ticket o pago) y borrarlo jamás alteraría ese objeto. La identidad es
/// siempre UID; los nombres de personas se resuelven en vivo y solo los
/// rótulos del objeto viajan congelados para que el histórico siga legible.
library;

enum ActivityType {
  spaceCreated('space_created'),
  spaceRenamed('space_renamed'),
  spaceArchived('space_archived'),
  spaceReactivated('space_reactivated'),
  spaceTransferred('space_transferred'),
  inviteSent('invite_sent'),
  memberJoined('member_joined'),
  memberLeft('member_left'),
  memberRemoved('member_removed'),
  ticketCreated('ticket_created'),
  ticketUpdated('ticket_updated'),
  ticketLinked('ticket_linked'),
  ticketUnlinked('ticket_unlinked'),
  ticketDeleted('ticket_deleted'),
  paymentMarked('payment_marked'),
  paymentConfirmed('payment_confirmed'),
  paymentCancelled('payment_cancelled'),
  unknown('unknown');

  const ActivityType(this.wire);

  final String wire;

  static ActivityType fromWire(String? value) => ActivityType.values
      .firstWhere((type) => type.wire == value, orElse: () => unknown);
}

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.actorUid,
    this.spaceId,
    this.sessionId,
    this.ticketId,
    this.paymentId,
    this.spaceName = '',
    this.ticketName = '',
    this.sessionName = '',
    this.amountCents,
    this.currency,
    this.at,
  });

  final String id;
  final ActivityType type;
  final String actorUid;
  final String? spaceId;
  final String? sessionId;
  final String? ticketId;
  final String? paymentId;
  final String spaceName;
  final String ticketName;
  final String sessionName;
  final int? amountCents;
  final String? currency;
  final DateTime? at;

  bool get hasAmount => amountCents != null && amountCents! > 0;
}
