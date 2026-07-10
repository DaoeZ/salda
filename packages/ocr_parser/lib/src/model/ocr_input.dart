/// Entrada del pipeline OCR, agnóstica del motor (ML Kit hoy, otros mañana).
/// La app convierte `RecognizedText` de ML Kit a este modelo.
library;

/// Caja delimitadora en coordenadas de imagen (px).
class OcrRect {
  const OcrRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

/// Fragmento de texto reconocido (una "línea" de ML Kit; los tickets suelen
/// romper cada fila visual en varios fragmentos por columnas).
class OcrElement {
  const OcrElement(this.text, this.box);

  final String text;
  final OcrRect box;
}

class OcrDocument {
  const OcrDocument(this.elements);

  final List<OcrElement> elements;
}
