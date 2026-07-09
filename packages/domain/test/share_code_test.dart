import 'dart:math';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('ShareCode', () {
    test('genera 22 caracteres base64url (128 bits) sin padding', () {
      final code = ShareCode.generate(Random(1));
      expect(code.value.length, 22);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(code.value), isTrue);
    });

    test('códigos distintos en generaciones sucesivas', () {
      final rng = Random(1);
      final codes = {for (var i = 0; i < 100; i++) ShareCode.generate(rng)};
      expect(codes.length, 100);
    });

    test('toString no filtra el secreto (seguridad de logs)', () {
      final code = ShareCode.generate(Random(1));
      expect(code.toString().contains(code.value), isFalse);
    });

    test('igualdad por valor', () {
      expect(const ShareCode('abc'), const ShareCode('abc'));
    });
  });
}
