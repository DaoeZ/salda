import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  ReceiptExtraction sample() => ReceiptExtraction(
        engine: 'mlkit',
        merchantName: const Extracted('Mercadona', 1.0),
        brandKey: 'mercadona',
        category: 'supermercado',
        date: const Extracted('2026-07-09', 0.95),
        time: const Extracted('18:32', 0.9),
        lines: [
          const ExtractedLine(
            name: 'LECHE',
            quantityMilli: 2000,
            unitPrice: Money(98),
            totalPrice: Money(196),
            confidence: 0.97,
            sourceText: '2 LECHE 0,98 1,96',
            alternatives: [
              LineAlternative(
                name: '2 LECHE 0,98',
                quantityMilli: 1000,
                totalPrice: Money(196),
                confidence: 0.7,
              ),
            ],
          ),
        ],
        taxes: [const LabeledAmount('IVA 4%', Money(8))],
        discounts: [const LabeledAmount('DESCUENTO', Money(20))],
        grandTotal: const Extracted(Money(176), 0.92),
      );

  test('roundtrip JSON conserva todos los campos', () {
    final original = sample();
    final restored = ReceiptExtraction.fromJson(original.toJson());
    expect(restored.merchantName.value, 'Mercadona');
    expect(restored.brandKey, 'mercadona');
    expect(restored.category, 'supermercado');
    expect(restored.date.value, '2026-07-09');
    expect(restored.lines.single.unitPrice, const Money(98));
    expect(restored.lines.single.alternatives.single.name, '2 LECHE 0,98');
    expect(restored.taxes.single.label, 'IVA 4%');
    expect(restored.discounts.single.amount, const Money(20));
    expect(restored.grandTotal.value, const Money(176));
    expect(restored.grandTotal.confidence, 0.92);
  });

  test('computedTotal = líneas − descuentos + propina', () {
    expect(sample().computedTotal, const Money(176)); // 196 − 20
  });

  test('needsReview según confianza global e issues', () {
    expect(sample().needsReview, isFalse);

    final withIssue = ReceiptExtraction(
      engine: 'mlkit',
      lines: sample().lines,
      grandTotal: const Extracted(Money(176), 0.92),
      issues: const [ReceiptIssue(ReceiptIssue.sumMismatch, 'no cuadra')],
    );
    expect(withIssue.needsReview, isTrue);

    final lowConfidence = ReceiptExtraction(
      engine: 'mlkit',
      lines: [
        const ExtractedLine(
            name: 'X', totalPrice: Money(100), confidence: 0.3),
      ],
      grandTotal: const Extracted(Money(100), 0.4),
    );
    expect(lowConfidence.needsReview, isTrue);
  });
}
