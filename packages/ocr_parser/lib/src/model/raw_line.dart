/// Fila visual del ticket ya reconstruida (post-geometría), normalizada.
class RawLine {
  const RawLine(this.text, {this.degradedAmounts = false});

  /// Texto completo de la fila, con espacios colapsados.
  final String text;

  /// `true` si los importes se recuperaron de un OCR degradado
  /// (p. ej. decimales con punto): baja la confianza de lo extraído.
  final bool degradedAmounts;

  RawLine copyWith({String? text, bool? degradedAmounts}) => RawLine(
        text ?? this.text,
        degradedAmounts: degradedAmounts ?? this.degradedAmounts,
      );
}
