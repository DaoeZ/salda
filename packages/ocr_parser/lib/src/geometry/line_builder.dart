import '../model/ocr_input.dart';
import '../model/raw_line.dart';

/// Reconstruye las filas visuales del ticket a partir de los fragmentos OCR.
///
/// ML Kit separa las columnas (descripción | importe) en bloques distintos;
/// aquí se re-unen por solapamiento vertical: dos fragmentos pertenecen a la
/// misma fila si sus cajas comparten al menos el 50 % de la altura menor.
abstract final class LineBuilder {
  static List<RawLine> build(OcrDocument document) {
    if (document.elements.isEmpty) return const [];

    final sorted = [...document.elements]
      ..sort((a, b) => a.box.centerY.compareTo(b.box.centerY));

    final rows = <List<OcrElement>>[];
    for (final element in sorted) {
      final current = rows.isEmpty ? null : rows.last;
      if (current != null && _sameRow(current, element)) {
        current.add(element);
      } else {
        rows.add([element]);
      }
    }

    return [
      for (final row in rows)
        RawLine(
          _normalize(
            (row..sort((a, b) => a.box.left.compareTo(b.box.left)))
                .map((e) => e.text)
                .join(' '),
          ),
        ),
    ].where((l) => l.text.isNotEmpty).toList(growable: false);
  }

  static bool _sameRow(List<OcrElement> row, OcrElement candidate) {
    // Comparar contra la caja envolvente de la fila en curso.
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final e in row) {
      if (e.box.top < top) top = e.box.top;
      if (e.box.bottom > bottom) bottom = e.box.bottom;
    }
    final overlap = _min(bottom, candidate.box.bottom) -
        _max(top, candidate.box.top);
    final minHeight = _min(bottom - top, candidate.box.height);
    return minHeight > 0 && overlap >= 0.5 * minHeight;
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;

  /// Normalización compartida con la ingestión de texto plano (corpus/PDF):
  /// colapsa espacios y corrige confusiones OCR habituales en contexto
  /// numérico (O→0, l/I→1) sin tocar los nombres de producto.
  static String _normalize(String text) => normalizeOcrText(text);
}

/// Expuesta para poder ingerir también texto plano (PDF con capa de texto,
/// corpus de regresión) por el mismo camino que la geometría.
String normalizeOcrText(String text) {
  var t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceAll(RegExp(r'(?<=\d)[Oo]'), '0');
  t = t.replaceAll(RegExp(r'[Oo](?=\d)'), '0');
  t = t.replaceAll(RegExp(r'(?<=\d)[lI](?=\d)'), '1');
  return t;
}

/// Convierte texto plano (una fila por línea) en RawLines normalizadas.
List<RawLine> rawLinesFromPlainText(String text) => [
      for (final line in text.split('\n'))
        if (normalizeOcrText(line).isNotEmpty)
          RawLine(normalizeOcrText(line)),
    ];
