import 'package:domain/domain.dart';

/// Estados de una sesión (spec §7).
enum SessionStatus { open, closed, archived }

enum SettlementState { pending, marked, confirmed }

/// Resumen desnormalizado para el listado (1 lectura por sesión).
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    required this.grandTotal,
    required this.settledConfirmed,
    required this.settledMarked,
    required this.participantsCount,
    required this.pendingSettlements,
    required this.ownerParticipantId,
    required this.myOutstanding,
    this.category,
    this.updatedAtMillis,
  });

  final String id;
  final String name;
  final String kind; // 'single' | 'multi'
  final SessionStatus status;
  final Money grandTotal;
  final Money settledConfirmed;
  final Money settledMarked;
  final int participantsCount;
  final int pendingSettlements;
  final String ownerParticipantId;

  /// Lo que el anfitrión tiene pendiente de recibir (+) o pagar (−),
  /// leído de los agregados que escribe la function.
  final Money myOutstanding;
  final String? category;
  final int? updatedAtMillis;

  double get settledFraction => grandTotal.isZero
      ? 0
      : (settledConfirmed.cents / grandTotal.cents).clamp(0.0, 1.0);
}

class SessionParticipant {
  const SessionParticipant({
    required this.id,
    required this.name,
    required this.isOwner,
    required this.order,
    this.claimedByDevice = '',
    this.active = true,
  });

  final String id;
  final String name;
  final bool isOwner;
  final int order;
  final String claimedByDevice;
  final bool active;
}

class SessionAccount {
  const SessionAccount({
    required this.id,
    required this.name,
    required this.order,
    required this.grandTotal,
  });

  final String id;
  final String name;
  final int order;
  final Money grandTotal;
}

class Settlement {
  const Settlement({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.state,
  });

  final String id;
  final String from;
  final String to;
  final Money amount;
  final SettlementState state;
}

class ParticipantBalanceView {
  const ParticipantBalanceView({
    required this.paid,
    required this.consumed,
    required this.net,
    required this.outstanding,
  });

  final Money paid;
  final Money consumed;
  final Money net;
  final Money outstanding;
}

/// Detalle vivo de la sesión (doc raíz).
class SessionDetail {
  const SessionDetail({
    required this.summary,
    required this.shareCode,
    required this.splitModeDefault,
    required this.balances,
  });

  final SessionSummary summary;
  final String shareCode;
  final SplitMode splitModeDefault;
  final Map<String, ParticipantBalanceView> balances;
}

// ── Export (PDF / imagen-resumen) ─────────────────────────────────────────

class LineExport {
  const LineExport({
    required this.name,
    required this.quantityMilli,
    required this.totalPrice,
  });

  final String name;
  final int quantityMilli;
  final Money totalPrice;
}

class TicketExport {
  const TicketExport({
    required this.merchantName,
    this.date,
    required this.grandTotal,
    required this.paidBy,
    this.lines = const [],
  });

  final String merchantName;
  final String? date;
  final Money grandTotal;
  final String paidBy; // pid
  final List<LineExport> lines;
}

class AccountExport {
  const AccountExport({required this.name, this.tickets = const []});

  final String name;
  final List<TicketExport> tickets;
}

// ── Entrada de creación (la mapea la feature de revisión) ────────────────

class NewLineInput {
  const NewLineInput({
    required this.name,
    this.quantityMilli = 1000,
    this.unitPrice,
    required this.totalPrice,
  });

  final String name;
  final int quantityMilli;
  final Money? unitPrice;
  final Money totalPrice;
}

class NewTicketInput {
  const NewTicketInput({
    required this.kind, // 'scanned' | 'manual'
    required this.merchantName,
    this.brandKey,
    this.category,
    this.date,
    this.time,
    required this.engine,
    required this.confidence,
    required this.grandTotal,
    this.tip,
    this.discounts = const [],
    this.taxes = const [],
    this.lines = const [],
  });

  final String kind;
  final String merchantName;
  final String? brandKey;
  final String? category;
  final String? date;
  final String? time;
  final String engine;
  final double confidence;
  final Money grandTotal;
  final Money? tip;
  final List<LabeledAmount> discounts;
  final List<LabeledAmount> taxes;
  final List<NewLineInput> lines;
}

class NewSessionInput {
  const NewSessionInput({
    required this.name,
    this.kind = 'single',
    required this.splitModeDefault,
    required this.participantNames,
    this.payerIndex = 0,
    required this.ticket,
    this.accountName,
    this.paymentMethodsSnapshot = const {},
  });

  final String name;
  final String kind;
  final SplitMode splitModeDefault;

  /// El índice 0 es SIEMPRE el anfitrión.
  final List<String> participantNames;
  final int payerIndex;
  final NewTicketInput ticket;
  final String? accountName;

  /// Snapshot de métodos de pago del anfitrión (RF-72): se congela al crear
  /// para que cambios futuros del perfil no alteren cuentas ya compartidas.
  final Map<String, String> paymentMethodsSnapshot;
}
