import 'package:ocr_parser/ocr_parser.dart';
import 'package:test/test.dart';

OcrElement el(
  String text,
  double left,
  double top, {
  double width = 100,
  double height = 20,
}) => OcrElement(text, OcrRect(left, top, left + width, top + height));

void main() {
  group('LineBuilder', () {
    test('re-une columnas separadas por ML Kit en una sola fila', () {
      final doc = OcrDocument([
        el('TOTAL', 0, 100),
        el('4,83', 300, 102), // misma fila, columna derecha
        el('GAZPACHO', 0, 60),
        el('1,80', 300, 58),
      ]);
      final lines = LineBuilder.build(doc);
      expect(lines.map((l) => l.text), ['GAZPACHO 1,80', 'TOTAL 4,83']);
    });

    test('filas distintas no se mezclan aunque estén cerca', () {
      final doc = OcrDocument([
        el('PAN', 0, 0),
        el('LECHE', 0, 22), // sin solapamiento vertical
      ]);
      expect(LineBuilder.build(doc).length, 2);
    });

    test('ordena por X dentro de la fila', () {
      final doc = OcrDocument([
        el('1,96', 300, 0),
        el('LECHE', 50, 1),
        el('2', 0, 2),
      ]);
      expect(LineBuilder.build(doc).single.text, '2 LECHE 1,96');
    });

    test('normaliza confusiones OCR en contexto numérico', () {
      expect(normalizeOcrText('O9/07/2026'), '09/07/2026');
      expect(normalizeOcrText('1O,50'), '10,50');
      expect(normalizeOcrText('4l5'), '415');
      // Fuera de contexto numérico no toca nada.
      expect(normalizeOcrText('OLIVA Y OREGANO'), 'OLIVA Y OREGANO');
    });
  });
}
