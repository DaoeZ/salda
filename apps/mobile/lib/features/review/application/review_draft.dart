import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'draft_store.dart';

/// Línea editable de la revisión (copia mutable de ExtractedLine).
class DraftLine {
  const DraftLine({
    required this.name,
    this.quantityMilli = 1000,
    this.unitPrice,
    required this.totalPrice,
    this.confidence = 1.0,
    this.sourceText = '',
    this.alternatives = const [],
  });

  factory DraftLine.fromExtracted(ExtractedLine line) => DraftLine(
        name: line.name,
        quantityMilli: line.quantityMilli,
        unitPrice: line.unitPrice,
        totalPrice: line.totalPrice,
        confidence: line.confidence,
        sourceText: line.sourceText,
        alternatives: line.alternatives,
      );

  final String name;
  final int quantityMilli;
  final Money? unitPrice;
  final Money totalPrice;
  final double confidence;
  final String sourceText;
  final List<LineAlternative> alternatives;

  bool get lowConfidence => confidence < 0.75;

  DraftLine copyWith({
    String? name,
    int? quantityMilli,
    Money? unitPrice,
    bool clearUnitPrice = false,
    Money? totalPrice,
  }) =>
      DraftLine(
        name: name ?? this.name,
        quantityMilli: quantityMilli ?? this.quantityMilli,
        unitPrice: clearUnitPrice ? null : (unitPrice ?? this.unitPrice),
        totalPrice: totalPrice ?? this.totalPrice,
        confidence: 1.0, // editado por el usuario = verdad
        sourceText: sourceText,
        alternatives: const [], // ya no aplican
      );
}

/// Estado de la revisión de un ticket antes de guardarlo (M3 lo persiste).
class ReviewDraftState {
  const ReviewDraftState({
    required this.engine,
    this.merchantName,
    this.brandKey,
    this.category,
    this.date,
    this.time,
    required this.lines,
    this.discounts = const [],
    this.taxes = const [],
    this.tip,
    this.grandTotal,
    this.issues = const [],
    this.sourceConfidence = 1.0,
  });

  factory ReviewDraftState.fromExtraction(ReceiptExtraction e) =>
      ReviewDraftState(
        engine: e.engine,
        merchantName: e.merchantName.value,
        brandKey: e.brandKey,
        category: e.category,
        date: e.date.value,
        time: e.time.value,
        lines: [for (final l in e.lines) DraftLine.fromExtracted(l)],
        discounts: e.discounts,
        taxes: e.taxes,
        tip: e.tip.value,
        grandTotal: e.grandTotal.value,
        issues: e.issues,
        sourceConfidence: e.overallConfidence,
      );

  final String engine;
  final String? merchantName;
  final String? brandKey;
  final String? category;
  final String? date;
  final String? time;
  final List<DraftLine> lines;
  final List<LabeledAmount> discounts;
  final List<LabeledAmount> taxes;
  final Money? tip;
  final Money? grandTotal;
  final List<ReceiptIssue> issues;
  final double sourceConfidence;

  Money get computedTotal {
    var sum = Money.zero;
    for (final l in lines) {
      sum += l.totalPrice;
    }
    for (final d in discounts) {
      sum -= d.amount;
    }
    if (tip != null) sum += tip!;
    return sum;
  }

  /// computed − grandTotal; null si aún no hay total.
  Money? get delta => grandTotal == null ? null : computedTotal - grandTotal!;

  bool get balanced {
    final d = delta;
    if (d == null) return false;
    final tolerance = grandTotal!.abs().cents ~/ 100;
    return d.abs().cents <= (tolerance > 2 ? tolerance : 2);
  }

  /// El banner de baja confianza se muestra si el origen era dudoso
  /// o el estado actual no cuadra.
  bool get needsAttention =>
      !balanced || issues.isNotEmpty || sourceConfidence < 0.75;

  /// Serialización para el draft persistente: el estado editable vuelve al
  /// contrato canónico (lo editado lleva confianza 1.0 = verdad del usuario).
  ReceiptExtraction toExtraction() => ReceiptExtraction(
        engine: engine,
        merchantName: merchantName == null
            ? const Extracted.missing()
            : Extracted(merchantName, 1.0),
        brandKey: brandKey,
        category: category,
        date: date == null
            ? const Extracted.missing()
            : Extracted(date, 1.0),
        time: time == null
            ? const Extracted.missing()
            : Extracted(time, 1.0),
        lines: [
          for (final l in lines)
            ExtractedLine(
              name: l.name,
              quantityMilli: l.quantityMilli,
              unitPrice: l.unitPrice,
              totalPrice: l.totalPrice,
              confidence: l.confidence,
              sourceText: l.sourceText,
              alternatives: l.alternatives,
            ),
        ],
        taxes: taxes,
        discounts: discounts,
        tip: tip == null ? const Extracted.missing() : Extracted(tip, 1.0),
        grandTotal: grandTotal == null
            ? const Extracted.missing()
            : Extracted(grandTotal, 1.0),
        issues: issues,
      );

  ReviewDraftState copyWith({
    String? merchantName,
    String? date,
    String? time,
    List<DraftLine>? lines,
    Money? grandTotal,
    List<ReceiptIssue>? issues,
  }) =>
      ReviewDraftState(
        engine: engine,
        merchantName: merchantName ?? this.merchantName,
        brandKey: brandKey,
        category: category,
        date: date ?? this.date,
        time: time ?? this.time,
        lines: lines ?? this.lines,
        discounts: discounts,
        taxes: taxes,
        tip: tip,
        grandTotal: grandTotal ?? this.grandTotal,
        issues: issues ?? this.issues,
        sourceConfidence: sourceConfidence,
      );
}

class ReviewDraft extends Notifier<ReviewDraftState?> {
  @override
  ReviewDraftState? build() => null;

  /// Persiste tras cada mutación: si la app muere, el ticket se recupera.
  void _persist() {
    final s = state;
    if (s == null) return;
    unawaited(ref.read(draftStoreProvider).save(s.toExtraction()));
  }

  void loadFrom(ReceiptExtraction extraction) {
    state = ReviewDraftState.fromExtraction(extraction);
    _persist();
  }

  /// Descarta el borrador (sesión creada o usuario lo desecha).
  void discard() {
    state = null;
    unawaited(ref.read(draftStoreProvider).clear());
  }

  void updateMerchant(String name) {
    state = state?.copyWith(merchantName: name);
    _persist();
  }

  void updateDate(String date) {
    state = state?.copyWith(date: date);
    _persist();
  }

  void updateTime(String time) {
    state = state?.copyWith(time: time);
    _persist();
  }

  void updateGrandTotal(Money total) {
    state = state?.copyWith(grandTotal: total, issues: const []);
    _persist();
  }

  void updateLine(int index, DraftLine line) {
    final s = state;
    if (s == null) return;
    final lines = [...s.lines]..[index] = line;
    state = s.copyWith(lines: lines, issues: const []);
    _persist();
  }

  void removeLine(int index) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
        lines: [...s.lines]..removeAt(index), issues: const []);
    _persist();
  }

  void addLine(DraftLine line) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(lines: [...s.lines, line], issues: const []);
    _persist();
  }
}

final reviewDraftProvider =
    NotifierProvider<ReviewDraft, ReviewDraftState?>(ReviewDraft.new);
