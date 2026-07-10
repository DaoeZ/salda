import 'package:domain/domain.dart';

/// Interpretación de una línea de producto producida por una regla.
class LineInterpretation {
  const LineInterpretation({
    required this.name,
    this.quantityMilli = 1000,
    this.unitPrice,
    required this.totalPrice,
    required this.confidence,
  });

  final String name;
  final int quantityMilli;
  final Money? unitPrice;
  final Money totalPrice;
  final double confidence;

  /// Dos interpretaciones son "equivalentes" si coinciden en lo que afecta
  /// al reparto; las equivalentes no se guardan como alternativas.
  bool sameOutcomeAs(LineInterpretation other) =>
      quantityMilli == other.quantityMilli &&
      unitPrice == other.unitPrice &&
      totalPrice == other.totalPrice;
}

/// Regla de parsing de línea. El parser prueba las reglas EN ORDEN
/// (las de perfil de establecimiento primero) y conserva todas las que
/// encajan: la mejor gana, el resto quedan como alternativas.
///
/// Añadir soporte para un formato nuevo = añadir una regla (o un perfil
/// que la aporte) + un caso de corpus. Las reglas existentes no se tocan.
class LineRule {
  const LineRule(this.id, this.tryMatch);

  final String id;
  final LineInterpretation? Function(String text) tryMatch;
}
