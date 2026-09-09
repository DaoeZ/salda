import 'package:domain/domain.dart';

import 'session_models.dart';

/// Qué se lleva por delante una corrección (A11c).
///
/// Salda no borra, traslada ni reinterpreta asignaciones en silencio: antes
/// de aplicar un cambio que destruye consumo ajeno hay que poder decir en
/// voz alta QUÉ desaparece y DE QUIÉN. Esta clase es ese cálculo, puro y
/// aparte de la interfaz para poder probarlo sin pantalla.
class CorrectionImpact {
  const CorrectionImpact({
    required this.lostUnitsByPid,
    required this.removedUnitIds,
  });

  /// pid → unidades (índice base 0) que pierde con el cambio.
  final Map<String, List<int>> lostUnitsByPid;

  /// Identificadores de unidad que dejan de existir (`u2`, `u3`…).
  final List<String> removedUnitIds;

  bool get isDestructive => lostUnitsByPid.isNotEmpty;

  /// Personas afectadas, en orden estable para pintarlas.
  List<String> get affectedPids => lostUnitsByPid.keys.toList()..sort();
}

/// Impacto de dejar la línea en [newQuantityMilli] unidades.
///
/// Reducir «2 × Coca-Cola» a una deja huérfana la unidad 2: quien la había
/// reclamado pierde ese consumo. Aumentar no destruye nada — y tampoco
/// inventa consumidores para las unidades nuevas.
CorrectionImpact impactOfQuantityChange(
  TicketLine line,
  int newQuantityMilli,
) {
  final after = TicketLine(
    id: line.id,
    path: line.path,
    name: line.name,
    quantityMilli: newQuantityMilli,
    totalPrice: line.totalPrice,
  ).units;

  final lost = <String, List<int>>{};
  final removed = <String>[];
  for (var unit = after; unit < line.units; unit++) {
    removed.add('u$unit');
    for (final pid in line.consumersOf(unit)) {
      (lost[pid] ??= []).add(unit);
    }
  }
  return CorrectionImpact(lostUnitsByPid: lost, removedUnitIds: removed);
}

/// Impacto de retirar la línea entera: se va con todas sus asignaciones.
CorrectionImpact impactOfRemovingLine(TicketLine line) {
  final lost = <String, List<int>>{};
  final removed = <String>[];
  for (var unit = 0; unit < line.units; unit++) {
    removed.add('u$unit');
    for (final pid in line.consumersOf(unit)) {
      (lost[pid] ??= []).add(unit);
    }
  }
  // Modelo histórico por pesos: no hay unidades, pero sí gente asignada.
  for (final pid in line.weights.keys) {
    lost.putIfAbsent(pid, () => const []);
  }
  return CorrectionImpact(lostUnitsByPid: lost, removedUnitIds: removed);
}

/// Identificadores de unidad que debe declarar la línea corregida.
List<String> unitIdsFor(int quantityMilli) {
  final units = TicketLine(
    id: '',
    path: '',
    name: '',
    quantityMilli: quantityMilli,
    totalPrice: const Money(0),
  ).units;
  return [for (var unit = 0; unit < units; unit++) 'u$unit'];
}
