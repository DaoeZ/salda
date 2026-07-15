import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';

void main() {
  group('progreso de liquidación', () {
    test('completo usa las obligaciones necesarias y llega al 100 %', () {
      const progress = SettlementProgress(
        required: Money(6000),
        confirmed: Money(6000),
        marked: Money.zero,
      );

      expect(progress.confirmedFraction, 1);
      expect(progress.remaining, Money.zero);
      expect(progress.isSettled, isTrue);
    });

    test('parcial separa confirmado, marcado y pendiente', () {
      const progress = SettlementProgress(
        required: Money(6000),
        confirmed: Money(2000),
        marked: Money(1000),
      );

      expect(progress.confirmedFraction, closeTo(1 / 3, 0.0001));
      expect(progress.markedFraction, closeTo(1 / 6, 0.0001));
      expect(progress.remaining, const Money(4000));
      expect(progress.isSettled, isFalse);
    });

    test('sin transferencias necesarias define 0/0 como saldado', () {
      const progress = SettlementProgress(
        required: Money.zero,
        confirmed: Money.zero,
        marked: Money.zero,
      );

      expect(progress.confirmedFraction, 1);
      expect(progress.markedFraction, 0);
      expect(progress.remaining, Money.zero);
      expect(progress.isSettled, isTrue);
    });
  });
}
