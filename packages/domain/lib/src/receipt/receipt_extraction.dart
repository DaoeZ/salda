import '../money.dart';

/// Valor extraído con su confianza [0..1] y alternativas descartadas pero
/// plausibles (útiles en la pantalla de revisión manual).
class Extracted<T> {
  const Extracted(this.value, this.confidence, [this.alternatives = const []]);

  const Extracted.missing()
      : value = null,
        confidence = 0,
        alternatives = const [];

  final T? value;
  final double confidence;
  final List<T> alternatives;

  bool get isPresent => value != null;
}

/// Interpretación alternativa de una línea (otra regla también encajó).
class LineAlternative {
  const LineAlternative({
    required this.name,
    required this.quantityMilli,
    required this.totalPrice,
    this.unitPrice,
    required this.confidence,
  });

  final String name;
  final int quantityMilli;
  final Money? unitPrice;
  final Money totalPrice;
  final double confidence;

  Map<String, Object?> toJson() => {
        'name': name,
        'quantityMilli': quantityMilli,
        'unitPrice': unitPrice?.cents,
        'totalPrice': totalPrice.cents,
        'confidence': confidence,
      };

  factory LineAlternative.fromJson(Map<String, dynamic> json) =>
      LineAlternative(
        name: json['name'] as String,
        quantityMilli: json['quantityMilli'] as int,
        unitPrice:
            json['unitPrice'] == null ? null : Money(json['unitPrice'] as int),
        totalPrice: Money(json['totalPrice'] as int),
        confidence: (json['confidence'] as num).toDouble(),
      );
}

/// Línea de producto extraída. `quantityMilli` = cantidad ×1000
/// (soporta pesables: 0,466 kg → 466).
class ExtractedLine {
  const ExtractedLine({
    required this.name,
    this.quantityMilli = 1000,
    this.unitPrice,
    required this.totalPrice,
    required this.confidence,
    this.sourceText = '',
    this.alternatives = const [],
  });

  final String name;
  final int quantityMilli;
  final Money? unitPrice;
  final Money totalPrice;
  final double confidence;

  /// Texto OCR original: la revisión manual lo muestra ante dudas.
  final String sourceText;
  final List<LineAlternative> alternatives;

  Map<String, Object?> toJson() => {
        'name': name,
        'quantityMilli': quantityMilli,
        'unitPrice': unitPrice?.cents,
        'totalPrice': totalPrice.cents,
        'confidence': confidence,
        'sourceText': sourceText,
        'alternatives': [for (final a in alternatives) a.toJson()],
      };

  factory ExtractedLine.fromJson(Map<String, dynamic> json) => ExtractedLine(
        name: json['name'] as String,
        quantityMilli: (json['quantityMilli'] as int?) ?? 1000,
        unitPrice:
            json['unitPrice'] == null ? null : Money(json['unitPrice'] as int),
        totalPrice: Money(json['totalPrice'] as int),
        confidence: (json['confidence'] as num).toDouble(),
        sourceText: (json['sourceText'] as String?) ?? '',
        alternatives: [
          for (final a in (json['alternatives'] as List?) ?? const [])
            LineAlternative.fromJson(a as Map<String, dynamic>),
        ],
      );
}

/// Importe etiquetado (impuestos y descuentos). Los descuentos se guardan
/// en positivo y se restan.
class LabeledAmount {
  const LabeledAmount(this.label, this.amount);

  final String label;
  final Money amount;

  Map<String, Object?> toJson() => {'label': label, 'amount': amount.cents};

  factory LabeledAmount.fromJson(Map<String, dynamic> json) =>
      LabeledAmount(json['label'] as String, Money(json['amount'] as int));
}

/// Inconsistencia detectada automáticamente → el ticket queda marcado
/// para revisión manual (requisito M2).
class ReceiptIssue {
  const ReceiptIssue(this.code, this.message, {this.deltaCents});

  /// La suma de líneas − descuentos + propina no cuadra con el total.
  static const sumMismatch = 'sumMismatch';
  static const missingTotal = 'missingTotal';
  static const noLines = 'noLines';
  static const missingDate = 'missingDate';

  final String code;
  final String message;
  final int? deltaCents;

  Map<String, Object?> toJson() => {
        'code': code,
        'message': message,
        if (deltaCents != null) 'deltaCents': deltaCents,
      };

  factory ReceiptIssue.fromJson(Map<String, dynamic> json) => ReceiptIssue(
        json['code'] as String,
        json['message'] as String,
        deltaCents: json['deltaCents'] as int?,
      );
}

/// Contrato canónico de extracción de un ticket (ESPECIFICACION.md §9.1/§10):
/// lo produce el parser OCR y también todos los proveedores de IA. La
/// pantalla de revisión es agnóstica del origen.
class ReceiptExtraction {
  const ReceiptExtraction({
    required this.engine,
    this.merchantName = const Extracted.missing(),
    this.brandKey,
    this.date = const Extracted.missing(),
    this.time = const Extracted.missing(),
    this.currency = 'EUR',
    this.category,
    this.lines = const [],
    this.taxes = const [],
    this.discounts = const [],
    this.tip = const Extracted.missing(),
    this.subtotal = const Extracted.missing(),
    this.grandTotal = const Extracted.missing(),
    this.issues = const [],
  });

  /// 'mlkit' | 'ai:<providerId>' | 'manual'.
  final String engine;

  final Extracted<String> merchantName;

  /// Clave del catálogo local de marcas (logo), si se reconoció la cadena.
  final String? brandKey;

  /// Fecha ISO `yyyy-MM-dd` y hora `HH:mm` (strings: sin zonas horarias).
  final Extracted<String> date;
  final Extracted<String> time;

  final String currency;

  /// Categoría automática (RF-26): supermercado, restaurante, gasolinera,
  /// farmacia, ocio, viaje, otros. Corregible por el usuario.
  final String? category;

  final List<ExtractedLine> lines;
  final List<LabeledAmount> taxes;
  final List<LabeledAmount> discounts;
  final Extracted<Money> tip;
  final Extracted<Money> subtotal;
  final Extracted<Money> grandTotal;
  final List<ReceiptIssue> issues;

  /// Confianza global ponderada: las líneas y el total pesan más porque
  /// son lo que determina el reparto.
  double get overallConfidence {
    final linesConfidence = lines.isEmpty
        ? 0.0
        : lines.map((l) => l.confidence).reduce((a, b) => a + b) /
            lines.length;
    final score = 0.40 * linesConfidence +
        0.30 * grandTotal.confidence +
        0.15 * merchantName.confidence +
        0.15 * date.confidence;
    // Cualquier inconsistencia detectada penaliza fuerte.
    return issues.isEmpty ? score : score * 0.6;
  }

  /// Umbral de decisión del flujo DC-4 (repetir foto / editar / IA).
  bool get needsReview => issues.isNotEmpty || overallConfidence < 0.75;

  /// Suma de líneas − descuentos + propina: lo que debería dar el total.
  Money get computedTotal {
    var sum = Money.zero;
    for (final l in lines) {
      sum += l.totalPrice;
    }
    for (final d in discounts) {
      sum -= d.amount;
    }
    if (tip.isPresent) sum += tip.value!;
    return sum;
  }

  Map<String, Object?> toJson() => {
        'engine': engine,
        'merchantName': merchantName.value,
        'merchantConfidence': merchantName.confidence,
        'brandKey': brandKey,
        'date': date.value,
        'dateConfidence': date.confidence,
        'time': time.value,
        'timeConfidence': time.confidence,
        'currency': currency,
        'category': category,
        'lines': [for (final l in lines) l.toJson()],
        'taxes': [for (final t in taxes) t.toJson()],
        'discounts': [for (final d in discounts) d.toJson()],
        'tip': tip.value?.cents,
        'subtotal': subtotal.value?.cents,
        'grandTotal': grandTotal.value?.cents,
        'grandTotalConfidence': grandTotal.confidence,
        'issues': [for (final i in issues) i.toJson()],
      };

  factory ReceiptExtraction.fromJson(Map<String, dynamic> json) {
    Extracted<Money> money(String key, [String? confidenceKey]) =>
        json[key] == null
            ? const Extracted.missing()
            : Extracted(
                Money(json[key] as int),
                confidenceKey == null
                    ? 1.0
                    : ((json[confidenceKey] as num?) ?? 1.0).toDouble(),
              );

    Extracted<String> text(String key, String confidenceKey) =>
        json[key] == null
            ? const Extracted.missing()
            : Extracted(
                json[key] as String,
                ((json[confidenceKey] as num?) ?? 1.0).toDouble(),
              );

    return ReceiptExtraction(
      engine: json['engine'] as String,
      merchantName: text('merchantName', 'merchantConfidence'),
      brandKey: json['brandKey'] as String?,
      date: text('date', 'dateConfidence'),
      time: text('time', 'timeConfidence'),
      currency: (json['currency'] as String?) ?? 'EUR',
      category: json['category'] as String?,
      lines: [
        for (final l in (json['lines'] as List?) ?? const [])
          ExtractedLine.fromJson(l as Map<String, dynamic>),
      ],
      taxes: [
        for (final t in (json['taxes'] as List?) ?? const [])
          LabeledAmount.fromJson(t as Map<String, dynamic>),
      ],
      discounts: [
        for (final d in (json['discounts'] as List?) ?? const [])
          LabeledAmount.fromJson(d as Map<String, dynamic>),
      ],
      tip: money('tip'),
      subtotal: money('subtotal'),
      grandTotal: money('grandTotal', 'grandTotalConfidence'),
      issues: [
        for (final i in (json['issues'] as List?) ?? const [])
          ReceiptIssue.fromJson(i as Map<String, dynamic>),
      ],
    );
  }
}
