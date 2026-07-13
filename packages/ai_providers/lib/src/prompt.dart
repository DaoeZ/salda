import 'dart:convert';

import 'package:domain/domain.dart';

import 'contract.dart';

/// Prompt canónico de extracción (spec §9.1): ÚNICO para todos los
/// proveedores; cada adaptador solo lo envuelve en su formato.
const extractionPrompt = '''
Eres un extractor de tickets de compra españoles. Devuelve EXCLUSIVAMENTE un
objeto JSON (sin markdown, sin explicaciones) con esta forma exacta; importes
en CÉNTIMOS enteros; cantidades multiplicadas por 1000 (1 unidad = 1000,
0,466 kg = 466); usa null cuando un dato no aparezca:

{
  "merchantName": "string|null",
  "date": "yyyy-MM-dd|null",
  "time": "HH:mm|null",
  "category": "supermercado|restaurante|gasolinera|farmacia|ocio|otros",
  "lines": [
    {"name": "string", "quantityMilli": 1000, "unitPrice": null, "totalPrice": 180}
  ],
  "taxes": [{"label": "IVA 10%", "amount": 17}],
  "discounts": [{"label": "string", "amount": 50}],
  "tip": null,
  "grandTotal": 483
}

Reglas: los descuentos van en positivo; grandTotal es el total final pagado;
la suma de lines - discounts + tip debe cuadrar con grandTotal.
''';

/// Parsea y valida la respuesta del modelo → contrato canónico.
/// Tolera vallas markdown y texto alrededor del JSON; ante cualquier
/// malformación lanza [AiErrorCode.badResponse] (el llamante reintenta una
/// vez citando el error, spec §9.1).
ReceiptExtraction parseAiResponse(String content, {required String engine}) {
  final start = content.indexOf('{');
  final end = content.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const AiProviderException(
        AiErrorCode.badResponse, 'La respuesta no contiene JSON');
  }
  Map<String, dynamic> json;
  try {
    json = jsonDecode(content.substring(start, end + 1))
        as Map<String, dynamic>;
  } on Object {
    throw const AiProviderException(
        AiErrorCode.badResponse, 'JSON inválido en la respuesta');
  }

  try {
    final lines = <ExtractedLine>[
      for (final l in (json['lines'] as List? ?? const []))
        ExtractedLine(
          name: (l as Map)['name'] as String,
          quantityMilli: (l['quantityMilli'] as num?)?.toInt() ?? 1000,
          unitPrice: l['unitPrice'] == null
              ? null
              : Money((l['unitPrice'] as num).toInt()),
          totalPrice: Money((l['totalPrice'] as num).toInt()),
          confidence: 0.9, // la IA no da confianza por campo: umbral alto único
        ),
    ];
    final grandTotal = json['grandTotal'] == null
        ? null
        : Money((json['grandTotal'] as num).toInt());
    if (lines.isEmpty && grandTotal == null) {
      throw const AiProviderException(
          AiErrorCode.badResponse, 'Sin líneas ni total');
    }

    List<LabeledAmount> amounts(String key) => [
          for (final e in (json[key] as List? ?? const []))
            LabeledAmount(
              (e as Map)['label'] as String? ?? key,
              Money((e['amount'] as num).toInt()),
            ),
        ];

    final extraction = ReceiptExtraction(
      engine: engine,
      merchantName: json['merchantName'] == null
          ? const Extracted.missing()
          : Extracted(json['merchantName'] as String, 0.9),
      category: json['category'] as String?,
      date: json['date'] == null
          ? const Extracted.missing()
          : Extracted(json['date'] as String, 0.9),
      time: json['time'] == null
          ? const Extracted.missing()
          : Extracted(json['time'] as String, 0.9),
      lines: lines,
      taxes: amounts('taxes'),
      discounts: amounts('discounts'),
      tip: json['tip'] == null
          ? const Extracted.missing()
          : Extracted(Money((json['tip'] as num).toInt()), 0.9),
      grandTotal: grandTotal == null
          ? const Extracted.missing()
          : Extracted(grandTotal, 0.9),
    );

    // Validación de cuadre: si no cuadra se marca para revisión (issue),
    // igual que hace el parser OCR.
    if (grandTotal != null && lines.isNotEmpty) {
      final delta = extraction.computedTotal - grandTotal;
      final tolerance =
          grandTotal.abs().cents ~/ 100 > 2 ? grandTotal.abs().cents ~/ 100 : 2;
      if (delta.abs().cents > tolerance) {
        return ReceiptExtraction(
          engine: engine,
          merchantName: extraction.merchantName,
          category: extraction.category,
          date: extraction.date,
          time: extraction.time,
          lines: extraction.lines,
          taxes: extraction.taxes,
          discounts: extraction.discounts,
          tip: extraction.tip,
          grandTotal: extraction.grandTotal,
          issues: [
            ReceiptIssue(
              ReceiptIssue.sumMismatch,
              'La suma de líneas no cuadra con el total',
              deltaCents: delta.cents,
            ),
          ],
        );
      }
    }
    return extraction;
  } on AiProviderException {
    rethrow;
  } on Object catch (error) {
    throw AiProviderException(
        AiErrorCode.badResponse, 'Estructura inesperada: $error');
  }
}
