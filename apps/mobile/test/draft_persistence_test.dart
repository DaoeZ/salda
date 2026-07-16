import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/review/application/draft_store.dart';
import 'package:salda_mobile/features/review/application/review_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReceiptExtraction _sample() => ReceiptExtraction(
  engine: 'mlkit',
  merchantName: const Extracted('Mercadona', 1.0),
  brandKey: 'mercadona',
  category: 'supermercado',
  date: const Extracted('2026-07-10', 0.95),
  lines: [
    const ExtractedLine(
      name: 'GAZPACHO',
      totalPrice: Money(180),
      confidence: 0.9,
    ),
  ],
  taxes: [const LabeledAmount('IVA 4%', Money(7))],
  discounts: [const LabeledAmount('DTO', Money(20))],
  grandTotal: const Extracted(Money(160), 0.92),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('roundtrip draft ↔ extraction conserva lo que afecta al guardado', () {
    final draft = ReviewDraftState.fromExtraction(_sample());
    final restored = ReviewDraftState.fromExtraction(draft.toExtraction());

    expect(restored.merchantName, 'Mercadona');
    expect(restored.brandKey, 'mercadona');
    expect(restored.category, 'supermercado');
    expect(restored.date, '2026-07-10');
    expect(restored.lines.single.name, 'GAZPACHO');
    expect(restored.lines.single.totalPrice, const Money(180));
    expect(restored.taxes.single.label, 'IVA 4%');
    expect(restored.discounts.single.amount, const Money(20));
    expect(restored.grandTotal, const Money(160));
  });

  test('DraftStore guarda, recupera y limpia', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DraftStore('owner');

    expect(await store.load(), isNull);

    await store.save(_sample());
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.merchantName.value, 'Mercadona');
    expect(loaded.grandTotal.value, const Money(160));

    await store.clear();
    expect(await store.load(), isNull);
  });

  test('contenido corrupto se descarta sin romper', () async {
    SharedPreferences.setMockInitialValues({
      'review_draft_v1': '{esto no es json',
    });
    expect(await DraftStore('owner').load(), isNull);
  });
}
