import 'dart:math';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('aritmética básica en céntimos', () {
      expect((const Money(150) + const Money(50)).cents, 200);
      expect((const Money(150) - const Money(200)).cents, -50);
      expect((const Money(150) * 3).cents, 450);
      expect((-const Money(5)).cents, -5);
      expect(const Money(-7).abs().cents, 7);
    });

    test('comparaciones', () {
      expect(const Money(1) < const Money(2), isTrue);
      expect(const Money(2) >= const Money(2), isTrue);
      expect(const Money(0).isZero, isTrue);
      expect(const Money(-1).isNegative, isTrue);
    });
  });

  group('allocateProportionally', () {
    test('reparto exacto sin resto', () {
      final parts = allocateProportionally(const Money(880), [500, 300]);
      expect(parts.map((m) => m.cents), [550, 330]);
    });

    test('resto mayor: céntimos sobrantes a las mayores fracciones', () {
      // 100 entre pesos [1,1,3]: exacto 20/20/60.
      expect(
        allocateProportionally(const Money(100), [1, 1, 3]).map((m) => m.cents),
        [20, 20, 60],
      );
      // 101 entre [1,1,1]: 33.67 cada uno → 34/34/33 (dos restos empatados,
      // ganan los índices menores).
      expect(
        allocateProportionally(const Money(101), [1, 1, 1]).map((m) => m.cents),
        [34, 34, 33],
      );
    });

    test('empate de fracciones: gana el índice menor', () {
      expect(
        allocateProportionally(const Money(1001), [
          250,
          250,
        ]).map((m) => m.cents),
        [501, 500],
      );
    });

    test('totales negativos conservan exactitud y determinismo', () {
      final parts = allocateProportionally(const Money(-100), [1, 1, 1]);
      expect(parts.map((m) => m.cents), [-34, -33, -33]);
      expect(parts.fold<int>(0, (a, m) => a + m.cents), -100);
    });

    test('peso cero para algún participante es válido (recibe 0)', () {
      expect(
        allocateProportionally(const Money(100), [1, 0]).map((m) => m.cents),
        [100, 0],
      );
    });

    test('errores: sin partes, pesos negativos, suma de pesos cero', () {
      expect(
        () => allocateProportionally(const Money(100), []),
        throwsA(
          isA<DomainException>().having(
            (e) => e.code,
            'code',
            DomainException.emptyParticipants,
          ),
        ),
      );
      expect(
        () => allocateProportionally(const Money(100), [1, -1]),
        throwsA(
          isA<DomainException>().having(
            (e) => e.code,
            'code',
            DomainException.invalidWeights,
          ),
        ),
      );
      expect(
        () => allocateProportionally(const Money(100), [0, 0]),
        throwsA(
          isA<DomainException>().having(
            (e) => e.code,
            'code',
            DomainException.invalidWeights,
          ),
        ),
      );
    });

    test('propiedad: la suma SIEMPRE es exacta (1000 casos sembrados)', () {
      final rng = Random(42); // sembrado: reproducible
      for (var i = 0; i < 1000; i++) {
        final n = 1 + rng.nextInt(8);
        final weights = List<int>.generate(n, (_) => rng.nextInt(1000));
        if (weights.every((w) => w == 0)) weights[0] = 1;
        final total = Money(rng.nextInt(1000000) - 100000);
        final parts = allocateProportionally(total, weights);
        expect(
          parts.fold<int>(0, (a, m) => a + m.cents),
          total.cents,
          reason: 'total=${total.cents} weights=$weights',
        );
        // Determinismo: segunda ejecución idéntica.
        expect(
          allocateProportionally(total, weights).map((m) => m.cents),
          parts.map((m) => m.cents),
        );
      }
    });

    test('allocateEvenly equivale a pesos iguales', () {
      expect(allocateEvenly(const Money(1000), 3).map((m) => m.cents), [
        334,
        333,
        333,
      ]);
    });
  });
}
