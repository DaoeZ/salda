import 'package:domain/domain.dart';
import 'package:ocr_parser/src/es/es_patterns.dart';
import 'package:ocr_parser/src/model/raw_line.dart';
import 'package:test/test.dart';

void main() {
  group('importes es-ES', () {
    test('parsea formatos español', () {
      expect(parseEsAmount('1,80'), const Money(180));
      expect(parseEsAmount('1.234,56'), const Money(123456));
      expect(parseEsAmount('-0,50'), const Money(-50));
    });

    test('encuentra todos los importes de una línea', () {
      expect(findAmounts('2 LECHE 0,98 1,96').map((m) => m.cents), [98, 196]);
      // 1,479 (3 decimales, €/L) no es un importe.
      expect(findAmounts('45,30 L x 1,479 €/L 67,00').map((m) => m.cents), [
        4530,
        6700,
      ]);
    });

    test('canonicaliza decimales de punto solo si no hay comas', () {
      final degraded = canonicalizeAmounts(const RawLine('GAZPACHO 1.80'));
      expect(degraded.text, 'GAZPACHO 1,80');
      expect(degraded.degradedAmounts, isTrue);

      // Con coma presente, el punto es separador de miles: no se toca.
      final ok = canonicalizeAmounts(const RawLine('JAMON 1.234,56'));
      expect(ok.text, 'JAMON 1.234,56');
      expect(ok.degradedAmounts, isFalse);
    });
  });

  group('fecha y hora es-ES', () {
    test('formatos de fecha habituales', () {
      expect(findEsDate('09/07/2026')!.iso, '2026-07-09');
      expect(findEsDate('28-06-2026')!.iso, '2026-06-28');
      expect(findEsDate('5.1.26')!.iso, '2026-01-05');
      expect(findEsDate('99/99/2026'), isNull);
      // Números de factura no son fechas.
      expect(findEsDate('FACTURA 2308-017-836214'), isNull);
    });

    test('hora con dos separadores', () {
      expect(findEsTime('18:32')!.hhmm, '18:32');
      expect(findEsTime('18.32')!.hhmm, '18:32');
      // Un precio no es una hora.
      expect(findEsTime('1.19'), isNull);
      expect(findEsTime('4,83'), isNull);
    });
  });
}
