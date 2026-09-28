import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/scan/application/manual_expense.dart';
import 'package:salda_mobile/features/settings/data/user_profile_repository.dart';

void main() {
  group('UserProfileRepository', () {
    test(
      'guarda y recupera métodos de pago; el snapshot omite vacíos',
      () async {
        final repo = UserProfileRepository(
          firestore: FakeFirebaseFirestore(),
          uid: () => 'owner',
        );

        await repo.savePaymentMethods(
          const PaymentMethods(
            bizumPhone: '612345678',
            iban: 'ES9121000418450200051332',
          ),
        );
        final profile = await repo.fetch();

        expect(profile.paymentMethods.bizumPhone, '612345678');
        expect(profile.paymentMethods.paypalLink, '');
        expect(profile.paymentMethods.toSnapshot(), {
          'bizumPhone': '612345678',
          'iban': 'ES9121000418450200051332',
        });
      },
    );
  });

  group('gasto manual', () {
    test('extracción de una línea, cuadrada y sin revisión necesaria', () {
      final extraction = manualExpenseExtraction(
        concept: 'Taxi aeropuerto',
        amount: const Money(2350),
        date: DateTime(2026, 7, 13),
      );
      expect(extraction.engine, 'manual');
      expect(extraction.date.value, '2026-07-13');
      expect(extraction.lines.single.name, 'Taxi aeropuerto');
      expect(extraction.computedTotal, const Money(2350));
      expect(extraction.grandTotal.value, const Money(2350));
      expect(extraction.needsReview, isFalse);
    });
  });
}
