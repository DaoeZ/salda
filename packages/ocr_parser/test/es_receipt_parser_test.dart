import 'package:domain/domain.dart';
import 'package:ocr_parser/ocr_parser.dart';
import 'package:test/test.dart';

/// Regresiones de A15 que el corpus no puede expresar: la CONFIANZA de una
/// línea y el margen exacto con el que un ticket se considera cuadrado.
///
/// El corpus compara valores (nombre, importes, issues); estas dos cosas son
/// señales, y son justo las que hacían que un ticket mal leído pasara por
/// bueno sin que nadie lo mirase.
void main() {
  final parser = ReceiptParser.standard();

  ReceiptExtraction parse(String body) => parser.parsePlainText('''
SUPER
28/08/2026
$body
''');

  group('A15: precio unitario impreso a la izquierda', () {
    test('la línea deja de presentarse como lectura fiable', () {
      // Caso observado en un ticket real: el precio unitario va a la
      // izquierda, la regla genérica se lo traga dentro del nombre y la
      // cantidad se pierde (1 en vez de 5). Sumaba con el total, así que el
      // ticket parecía correcto.
      final r = parse('1,15 MACARRON ROMERO 1 KG 5,75\nTOTAL 5,75');
      final line = r.lines.single;

      expect(line.totalPrice, const Money(575));
      // NO se inventa la cantidad: 5,75/1,15 = 5 es una división exacta, no
      // una prueba (podría ser peso, oferta o descuento).
      expect(line.quantityMilli, 1000);
      // Pero la lectura no está resuelta y hay que decirlo.
      expect(line.confidence, lessThan(0.75), reason: 'debe marcarse dudosa');
    });

    test('el layout bien estructurado sigue interpretándose entero', () {
      final r = parse('5 MACARRON ROMERO 1 KG 1,15 5,75\nTOTAL 5,75');
      final line = r.lines.single;

      expect(line.name, 'MACARRON ROMERO 1 KG');
      expect(line.quantityMilli, 5000);
      expect(line.unitPrice, const Money(115));
      expect(line.totalPrice, const Money(575));
      expect(line.confidence, greaterThan(0.9));
    });

    test(
      'un nombre que empieza por número pero no por importe no se penaliza',
      () {
        final r = parse('7 UP LIMON 1,50\nTOTAL 1,50');
        expect(r.lines.single.confidence, greaterThan(0.75));
      },
    );
  });

  group('A15: el total cuadra con dos céntimos, no con el 1 %', () {
    ReceiptExtraction conDelta(int centimos) => parse(
      'UNO 10,00\nDOS ${(586 + centimos) ~/ 100},'
      '${((586 + centimos) % 100).toString().padLeft(2, '0')}\n'
      'TOTAL 15,86',
    );

    for (final delta in [0, 1, 2]) {
      test('descuadre de $delta céntimos: cuadra', () {
        expect(conDelta(delta).issues, isEmpty);
      });
    }

    test('descuadre de 3 céntimos: NO cuadra', () {
      expect(
        conDelta(3).issues.map((i) => i.code),
        contains(ReceiptIssue.sumMismatch),
      );
    });

    test('en un ticket grande el margen sigue siendo de dos céntimos', () {
      // Con la tolerancia anterior (1 %) un descuadre de 9,99 € sobre 999 €
      // pasaba por cuadrado: cabía un producto entero dentro del margen.
      final r = parse('UNO 989,01\nDOS 0,50\nTOTAL 999,00');
      expect(r.issues.map((i) => i.code), contains(ReceiptIssue.sumMismatch));
    });
  });

  test('A12: base y cuota sueltas no son productos ni inventan impuestos', () {
    final r = parse('BASE IMPONIBLE 13,19\nIVA 21% 2,77\nTOTAL 15,96');
    expect(r.lines, isEmpty);
    // No se reconstruye el impuesto desde una línea suelta: el importe
    // pagado sigue viviendo en el total, que es lo único demostrable.
    expect(r.taxes, isEmpty);
    expect(r.grandTotal.value, const Money(1596));
    expect(r.issues.map((i) => i.code), contains(ReceiptIssue.noLines));
  });
}
