import '../errors.dart';
import '../money.dart';

/// Modo de reparto (ESPECIFICACION.md RF-41).
enum SplitMode { equal, byItem }

/// Qué hacer con líneas sin asignar en modo byItem (RF-46).
enum UnassignedLinePolicy {
  /// Lanzar [DomainException.unassignedLine] (por defecto: la UI avisa).
  error,

  /// Tratarlas como compartidas por todos (tras confirmación explícita).
  splitAmongAll,
}

enum AssignmentType { unassigned, one, shared, all }

/// Asignación de una línea a participantes.
///
/// - `one`: exactamente un participante en [weights] (peso irrelevante).
/// - `shared`: 2+ participantes con pesos > 0 (partes iguales = pesos 1).
/// - `all`: todos los participantes activos; [weights] vacío.
/// - `unassigned`: pendiente; la resuelve [UnassignedLinePolicy].
class LineAssignment {
  const LineAssignment(this.type, [this.weights = const {}]);

  static const unassigned = LineAssignment(AssignmentType.unassigned);
  static const all = LineAssignment(AssignmentType.all);

  final AssignmentType type;

  /// participantId → peso (solo para `one` y `shared`).
  final Map<String, int> weights;
}

/// Línea de ticket vista por el motor: importe total, asignación y unidades.
class SplitLine {
  const SplitLine({
    required this.id,
    required this.totalPrice,
    required this.assignment,
    this.units = 1,
    this.unitConsumers,
  });

  final String id;
  final Money totalPrice;
  final LineAssignment assignment;

  /// Unidades de la línea (P2.1): "2 × flauta" son 2 unidades y un peso de 1
  /// reclama UNA (la mitad del importe). Deriva de quantityMilli solo cuando
  /// es un múltiplo entero (los pesos —0,466 kg— siguen siendo 1 unidad):
  /// [unitsFromQuantityMilli]. Con 1 (por defecto) el comportamiento es el
  /// histórico: cualquier selección reparte la línea completa.
  final int units;

  /// Modelo P2.2 por unidades físicas: índice de unidad → consumidores.
  ///
  /// `null` conserva EXACTAMENTE la semántica histórica/P2.1 de [assignment].
  /// Un mapa presente activa el modelo nuevo; una unidad ausente o con lista
  /// vacía es residual y recae en el pagador. Los índices son implícitos y
  /// estables (`0 .. units-1`), por lo que no hacen falta documentos extra.
  final Map<int, List<String>>? unitConsumers;

  /// Unidades "reclamables" a partir de una cantidad ×1000.
  static int unitsFromQuantityMilli(int quantityMilli) =>
      quantityMilli >= 2000 && quantityMilli % 1000 == 0
      ? quantityMilli ~/ 1000
      : 1;
}

/// Entrada del motor para un ticket.
class SplitTicketInput {
  const SplitTicketInput({required this.grandTotal, this.lines = const []});

  /// Total final del ticket (tras impuestos, descuentos y propina).
  final Money grandTotal;
  final List<SplitLine> lines;
}

/// Motor de reparto por ticket: puro, determinista y exacto
/// (Σ resultado == grandTotal, garantizado por [allocateProportionally]).
///
/// Impuestos, descuentos y propina NO se reciben por separado: al repartir
/// el `grandTotal` proporcionalmente al consumo en líneas, el prorrateo
/// proporcional (DC-11) sale gratis y sin errores de redondeo acumulados.
abstract final class SplitEngine {
  /// Consumo por participante para un ticket.
  ///
  /// [participantIds] define el universo de participantes activos y el orden
  /// estable de desempate en redondeos. Todos aparecen en el resultado
  /// (con 0 si no consumieron).
  ///
  /// [payerId] activa la regla de residual por unidades (P2.1): si en una
  /// línea la suma de pesos reclamados no llega a sus [SplitLine.units], las
  /// unidades sin reclamar recaen en el pagador (extensión natural de
  /// ADR-021: lo que nadie ha cogido es de quien pagó). Cuando la suma
  /// alcanza o supera las unidades, el reparto es proporcional puro — el
  /// comportamiento de compartir de siempre, intacto.
  static Map<String, Money> splitTicket({
    required List<String> participantIds,
    required SplitMode mode,
    required SplitTicketInput ticket,
    UnassignedLinePolicy unassignedPolicy = UnassignedLinePolicy.error,
    String? payerId,
  }) {
    if (participantIds.isEmpty) {
      throw const DomainException(
        DomainException.emptyParticipants,
        'Un ticket necesita al menos un participante',
      );
    }

    final weights = switch (mode) {
      SplitMode.equal => List<int>.filled(participantIds.length, 1),
      SplitMode.byItem => _lineWeights(
        participantIds,
        ticket.lines,
        unassignedPolicy,
        payerId,
      ),
    };

    // byItem sin consumo en líneas (ticket manual sin desglose): a medias.
    final effectiveWeights = weights.every((w) => w == 0)
        ? List<int>.filled(participantIds.length, 1)
        : weights;

    final shares = ticket.grandTotal.isZero
        ? List<Money>.filled(participantIds.length, Money.zero)
        : allocateProportionally(ticket.grandTotal, effectiveWeights);

    return {
      for (var i = 0; i < participantIds.length; i++)
        participantIds[i]: shares[i],
    };
  }

  /// Consumo en líneas por participante (en céntimos), usado como peso del
  /// reparto del grandTotal. Cada línea se reparte con resto mayor.
  static List<int> _lineWeights(
    List<String> participantIds,
    List<SplitLine> lines,
    UnassignedLinePolicy unassignedPolicy,
    String? payerId,
  ) {
    final index = {
      for (var i = 0; i < participantIds.length; i++) participantIds[i]: i,
    };
    final totals = List<int>.filled(participantIds.length, 0);

    for (final line in lines) {
      if (line.unitConsumers != null) {
        _addUnitShares(
          line: line,
          participantIds: participantIds,
          index: index,
          totals: totals,
          unassignedPolicy: unassignedPolicy,
          payerId: payerId,
        );
        continue;
      }

      var type = line.assignment.type;
      if (type == AssignmentType.unassigned) {
        if (unassignedPolicy == UnassignedLinePolicy.error) {
          throw DomainException(
            DomainException.unassignedLine,
            'La línea ${line.id} no está asignada a nadie',
          );
        }
        type = AssignmentType.all;
      }

      final lineWeights = switch (type) {
        AssignmentType.all => List<int>.filled(participantIds.length, 1),
        AssignmentType.one || AssignmentType.shared => _explicitWeights(
          line,
          index,
          participantIds.length,
        ),
        AssignmentType.unassigned => throw StateError('resuelto arriba'),
      };

      // Residual por unidades: reclamar 1 de las 2 flautas deja la otra al
      // pagador. Solo aplica a reclamaciones explícitas: `all` ya cubre el
      // total por definición.
      if (payerId != null &&
          (type == AssignmentType.one || type == AssignmentType.shared)) {
        final payerIndex = index[payerId];
        final claimed = lineWeights.fold(0, (a, w) => a + w);
        if (payerIndex != null && claimed < line.units) {
          lineWeights[payerIndex] += line.units - claimed;
        }
      }

      final shares = allocateProportionally(line.totalPrice, lineWeights);
      for (var i = 0; i < shares.length; i++) {
        totals[i] += shares[i].cents;
      }
    }
    return totals;
  }

  /// Reparte primero el importe exacto de la línea entre unidades iguales y
  /// después cada unidad entre sus consumidores. Ambos pasos usan resto mayor
  /// y el orden estable de [participantIds], así que Dart y TS desempatan igual.
  static void _addUnitShares({
    required SplitLine line,
    required List<String> participantIds,
    required Map<String, int> index,
    required List<int> totals,
    required UnassignedLinePolicy unassignedPolicy,
    required String? payerId,
  }) {
    if (line.units <= 0) {
      throw DomainException(
        DomainException.invalidWeights,
        'Número de unidades inválido en la línea ${line.id}',
      );
    }
    final unitAmounts = allocateProportionally(
      line.totalPrice,
      List<int>.filled(line.units, 1),
    );
    for (var unit = 0; unit < line.units; unit++) {
      final requested = line.unitConsumers![unit] ?? const <String>[];
      final consumers = <String>[];
      for (final pid in requested) {
        if (!index.containsKey(pid)) {
          throw DomainException(
            DomainException.unknownParticipant,
            'Participante desconocido "$pid" en la unidad $unit '
            'de la línea ${line.id}',
          );
        }
        if (!consumers.contains(pid)) consumers.add(pid);
      }
      if (consumers.isEmpty) {
        if (payerId != null && index.containsKey(payerId)) {
          consumers.add(payerId);
        } else if (unassignedPolicy == UnassignedLinePolicy.splitAmongAll) {
          consumers.addAll(participantIds);
        } else {
          throw DomainException(
            DomainException.unassignedLine,
            'La unidad $unit de la línea ${line.id} no está asignada',
          );
        }
      }
      final unitWeights = <int>[
        for (final pid in participantIds) consumers.contains(pid) ? 1 : 0,
      ];
      final shares = allocateProportionally(unitAmounts[unit], unitWeights);
      for (var i = 0; i < shares.length; i++) {
        totals[i] += shares[i].cents;
      }
    }
  }

  static List<int> _explicitWeights(
    SplitLine line,
    Map<String, int> index,
    int count,
  ) {
    final entries = line.assignment.weights;
    if (entries.isEmpty || entries.values.any((w) => w <= 0)) {
      throw DomainException(
        DomainException.invalidWeights,
        'Pesos inválidos en la línea ${line.id}',
      );
    }
    if (line.assignment.type == AssignmentType.one && entries.length != 1) {
      throw DomainException(
        DomainException.invalidWeights,
        'Asignación "one" con ${entries.length} participantes '
        'en la línea ${line.id}',
      );
    }
    final weights = List<int>.filled(count, 0);
    for (final entry in entries.entries) {
      final i = index[entry.key];
      if (i == null) {
        throw DomainException(
          DomainException.unknownParticipant,
          'Participante desconocido "${entry.key}" en la línea ${line.id}',
        );
      }
      weights[i] = entry.value;
    }
    return weights;
  }
}
