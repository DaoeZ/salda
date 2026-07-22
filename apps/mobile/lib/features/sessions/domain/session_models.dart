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
    required this.settlementRequired,
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

  /// Confirmado histórico + obligaciones residuales actuales.
  /// Es el denominador autoritativo del progreso de liquidación.
  final Money settlementRequired;
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

  SettlementProgress get settlementProgress => SettlementProgress(
    required: settlementRequired,
    confirmed: settledConfirmed,
    marked: settledMarked,
  );
}

/// Estado derivado exclusivamente de agregados autoritativos de liquidación.
///
/// `required` no es el gasto total: suma lo confirmado y las transferencias
/// residuales que todavía hacen falta. Por definición 0/0 está saldado.
class SettlementProgress {
  const SettlementProgress({
    required this.required,
    required this.confirmed,
    required this.marked,
  });

  final Money required;
  final Money confirmed;
  final Money marked;

  bool get isSettled => required.cents == confirmed.cents;

  Money get remaining =>
      Money((required.cents - confirmed.cents).clamp(0, required.cents));

  double get confirmedFraction =>
      required.isZero ? 1 : (confirmed.cents / required.cents).clamp(0.0, 1.0);

  double get markedFraction => required.isZero
      ? 0
      : (marked.cents / required.cents).clamp(0.0, 1.0 - confirmedFraction);
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

/// Ticket dentro de una cuenta (historial, RF-80/83).
class SessionTicket {
  const SessionTicket({
    required this.id,
    required this.path,
    required this.merchantName,
    this.date,
    required this.grandTotal,
    required this.paidBy,
    required this.kind,
    this.imagePath,
    this.splitModeOverride,
    this.spaceId,
  });

  final String id;

  /// Ruta completa del documento (para líneas, foto y navegación).
  final String path;
  final String merchantName;
  final String? date;
  final Money grandTotal;
  final String paidBy; // pid
  final String kind; // scanned | manual
  final String? imagePath; // ruta en Storage (null hasta subir la foto)

  /// Modo forzado del ticket; null = hereda el de la sesión. Decide si las
  /// líneas son seleccionables en el detalle (P2.1).
  final SplitMode? splitModeOverride;

  /// Espacio compartido al que pertenece (P4); null/'' = sin espacio. Un
  /// ticket pertenece como máximo a UN espacio y vincularlo no cambia
  /// participantes, asignaciones, balances ni pagos.
  final String? spaceId;

  bool get hasSpace => spaceId != null && spaceId!.isNotEmpty;
}

/// Línea VIVA de un ticket (P2.1): el creador ve y edita las asignaciones
/// exactamente igual que un invitado. Los pesos son unidades reclamadas.
class TicketLine {
  const TicketLine({
    required this.id,
    required this.path,
    required this.name,
    required this.quantityMilli,
    required this.totalPrice,
    this.assignmentType = 'unassigned',
    this.weights = const {},
    this.assignmentSchemaVersion,
    this.unitConsumers = const {},
  });

  final String id;

  /// Ruta completa del documento (para la escritura de la asignación).
  final String path;
  final String name;
  final int quantityMilli;
  final Money totalPrice;
  final String assignmentType; // unassigned | one | shared | all
  final Map<String, int> weights; // pid → unidades reclamadas
  final int? assignmentSchemaVersion;

  /// P2.2: índice de unidad → pids que comparten ESA unidad.
  final Map<int, Set<String>> unitConsumers;

  bool get usesUnitModel => assignmentSchemaVersion == 2;

  /// Unidades reclamables (misma derivación que motor y reglas).
  int get units => SplitLine.unitsFromQuantityMilli(quantityMilli);

  int weightOf(String pid) => weights[pid] ?? 0;

  /// pids con consumo distintos de [pid] (para "compartido con…").
  List<String> othersThan(String pid) => [
    for (final entry in weights.keys)
      if (entry != pid) entry,
  ];

  Set<String> consumersOf(int unit) => unitConsumers[unit] ?? const {};

  bool unitIsMine(int unit, String pid) => consumersOf(unit).contains(pid);
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
    this.participantUids = const [],
    this.payerIndex = 0,
    required this.ticket,
    this.spaceId,
    this.spaceName,
    this.accountName,
    this.paymentMethodsSnapshot = const {},
  });

  final String name;
  final String kind;
  final SplitMode splitModeDefault;

  /// El índice 0 es SIEMPRE el anfitrión.
  final List<String> participantNames;
  final List<String> participantUids;
  final int payerIndex;
  final NewTicketInput ticket;
  final String? spaceId;
  final String? spaceName;
  final String? accountName;

  /// Snapshot de métodos de pago del anfitrión (RF-72): se congela al crear
  /// para que cambios futuros del perfil no alteren cuentas ya compartidas.
  final Map<String, String> paymentMethodsSnapshot;
}
