import 'package:domain/domain.dart';

/// Gasto manual sin ticket (RF-13): se modela como una extracción `manual`
/// de una sola línea, así reutiliza TODO el flujo (revisión, gente, reparto,
/// backend) sin ningún caso especial.
ReceiptExtraction manualExpenseExtraction({
  required String concept,
  required Money amount,
  required DateTime date,
}) {
  final iso =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return ReceiptExtraction(
    engine: 'manual',
    merchantName: Extracted(concept, 1.0),
    category: 'otros',
    date: Extracted(iso, 1.0),
    lines: [ExtractedLine(name: concept, totalPrice: amount, confidence: 1.0)],
    grandTotal: Extracted(amount, 1.0),
  );
}
