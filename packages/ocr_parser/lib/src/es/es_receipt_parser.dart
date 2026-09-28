import 'package:domain/domain.dart';

import '../core/line_rule.dart';
import '../core/receipt_parser.dart';
import '../model/raw_line.dart';
import 'es_patterns.dart';
import 'es_profiles.dart';

/// Parser de tickets españoles (ESPECIFICACION.md §10).
///
/// Estrategia incremental: perfiles por establecimiento + reglas de línea
/// ordenadas. Cada campo sale con su propia confianza; las inconsistencias
/// (cuadre, total ausente…) se marcan como issues → revisión manual.
class EsReceiptParser implements CountryReceiptParser {
  @override
  String get locale => 'es';

  // ── Ruido: líneas que jamás son productos ─────────────────────────────
  static final List<RegExp> _noise = [
    RegExp(r'\bN\.?I\.?F\b|\bC\.?I\.?F\b'),
    RegExp(r'TEL[EÉ]FONO|\bTELF?\b|\bTFNO\b|\bTEL[.:]'),
    RegExp(r'FACTURA|SIMPLIF|TICKET N|\bCAJA\b|\bOP:'),
    RegExp(r'TARJETA|EFECTIVO|ENTREGADO|\bCAMBIO\b|DEVOLUC|CONTACTLESS'),
    RegExp(r'\bMESA\b|CAMARER|COMENSAL'),
    RegExp(r'GRACIAS|VISITA|HORARIO|CLIENTE|AUTORIZ|N[ºo] ?OPER'),
    RegExp(r'WWW\.|\.COM\b|\.ES\b'),
    RegExp(r'DESCRIPCI[OÓ]N|P\.? ?UNIT'),
    // Direcciones.
    RegExp(
      r'^C/|\bCALLE\b|\bAVDA\b|AVENIDA|\bPLAZA\b|PASEO|CTRA|AUTOV[IÍ]A'
      r'|POL[IÍ]GONO|^CC\b|CENTRO COMERCIAL|\bKM ?\d',
    ),
  ];

  // ── Palabras clave de total, por fuerza descendente ───────────────────
  static final List<({RegExp pattern, double confidence})> _totalKeywords = [
    (pattern: RegExp('TOTAL A PAGAR'), confidence: 0.97),
    (pattern: RegExp('A PAGAR'), confidence: 0.95),
    (pattern: RegExp('IMPORTE TOTAL'), confidence: 0.95),
    (pattern: RegExp('(?<!SUB)TOTAL'), confidence: 0.92),
  ];

  static final _taxZoneHeader = RegExp(r'IVA.*(BASE|CUOTA)|BASE.*CUOTA');
  static final _taxRow = RegExp(
    '^(\\d{1,2})\\s*%\\s+($amountSrc)\\s+($amountSrc)\$',
  );
  static final _discountKeyword = RegExp(
    r'DESCUENTO|\bDTO\b|CUP[OÓ]N|\bAHORRO\b',
  );

  // ── Desglose fiscal suelto (A12) ──────────────────────────────────────
  // Un ticket puede imprimir la base y la cuota como líneas normales, ANTES
  // del total y sin la cabecera combinada que detecta `_taxZoneHeader`. Sin
  // este filtro caían en la regla genérica `nombre + importe` y se
  // convertían en productos fantasma: se midió que «BASE IMPONIBLE 13,19» +
  // «IVA 21% 2,77» + «TOTAL 15,96» daba un ticket que CUADRABA exactamente
  // sin un solo producto real y sin ningún aviso.
  //
  // Deliberadamente ESTRECHO: exige el concepto fiscal completo, no una
  // palabra suelta. «BASE PIZZA» o «CUOTA MENSUAL GIMNASIO» son productos y
  // tienen que seguir siéndolo; solo se descarta lo que únicamente puede ser
  // fiscalidad.
  static final _fiscalKeyword = RegExp(
    r'\bBASE\s+IMP(?:ONIBLE)?\b'
    r'|\bB\.?\s?IMPONIBLE\b'
    r'|\bI\.?V\.?A\.?\s*:?\s*\d{1,2}(?:[.,]\d+)?\s*%'
    r'|\d{1,2}\s*%\s*(?:DE\s+)?I\.?V\.?A\b'
    r'|\bCUOTA\s+I\.?V\.?A\b'
    r'|\bI\.?V\.?A\.?\s+INCLUIDO\b',
  );

  // ── Reglas de línea por defecto (orden = prioridad) ───────────────────
  static final List<LineRule> _defaultRules = [
    LineRule('qty_name_unit_total', _qtyNameUnitTotal),
    LineRule('mult_name_total', _multNameTotal),
    LineRule('name_mult_total', _nameMultTotal),
    LineRule('weight_inline', _weightInline),
    LineRule('fuel', _fuel),
    LineRule('qty_name_total', _qtyNameTotal),
    LineRule('name_total', _nameTotal),
  ];

  // Reglas de continuación: consumen el nombre pendiente de la línea previa
  // (formato Mercadona pesables y DIA multiplicador).
  static final _pendingWeight = RegExp(
    '^(\\d+,\\d{1,3})\\s*[Kk][Gg]\\.?\\s+($amountSrc)\\s*€/[Kk][Gg]'
    '\\s+($amountSrc)\$',
  );
  static final _pendingMult = RegExp(
    '^(\\d{1,3})\\s*[xX]\\s*($amountSrc)\\s+($amountSrc)\$',
  );
  static final _pendingQtyName = RegExp(r'^(\d{1,2})\s+(\D.*)$');

  @override
  ReceiptExtraction parse(List<RawLine> rawLines) {
    // Fecha y hora se extraen de las líneas ORIGINALES: la canonicalización
    // de importes degradados convertiría "18.32" (hora) en "18,32" (importe).
    final dateTime = _extractDateTime(rawLines);

    final lines = rawLines.map(canonicalizeAmounts).toList(growable: false);

    final profile = EsMerchantProfiles.detect(lines);
    final noise = [..._noise, ...?profile?.extraNoise];
    final rules = [...?profile?.extraRules, ..._defaultRules];
    final taxZoneStart = lines.indexWhere(
      (l) => _taxZoneHeader.hasMatch(l.text.toUpperCase()),
    );
    final totalHit = _findGrandTotal(lines, taxZoneStart, profile);
    final taxes = _extractTaxes(lines, taxZoneStart);

    final body = _extractBody(
      lines,
      end: _bodyEnd(totalHit?.index, taxZoneStart, lines.length),
      noise: noise,
      rules: rules,
    );

    final merchant = profile != null
        ? Extracted(profile.displayName, 1.0)
        : _fallbackMerchant(lines, noise);

    // ── Total, cuadre e issues ──────────────────────────────────────────
    final issues = <ReceiptIssue>[];
    var computed = Money.zero;
    for (final l in body.lines) {
      computed += l.totalPrice;
    }
    for (final d in body.discounts) {
      computed -= d.amount;
    }
    if (body.tip.isPresent) computed += body.tip.value!;

    Extracted<Money> grandTotal;
    if (totalHit != null) {
      grandTotal = totalHit.total;
      if (body.lines.isNotEmpty) {
        final delta = computed - totalHit.total.value!;
        // A15: tolerancia FIJA de dos céntimos (ver `domain`). El 1 % de
        // antes daba por cuadrado un ticket al que le faltaba un producto.
        if (!receiptAmountsBalance(computed, totalHit.total.value!)) {
          issues.add(
            ReceiptIssue(
              ReceiptIssue.sumMismatch,
              'La suma de líneas (${computed.cents}) no cuadra con el total '
              '(${totalHit.total.value!.cents})',
              deltaCents: delta.cents,
            ),
          );
        }
      }
    } else if (body.lines.isNotEmpty) {
      // Sin palabra clave de total: se sugiere el calculado, a revisar.
      grandTotal = Extracted(computed, 0.4);
      issues.add(
        const ReceiptIssue(
          ReceiptIssue.missingTotal,
          'No se encontró el total del ticket',
        ),
      );
    } else {
      grandTotal = const Extracted.missing();
      issues.add(
        const ReceiptIssue(
          ReceiptIssue.missingTotal,
          'No se encontró el total del ticket',
        ),
      );
    }

    if (body.lines.isEmpty) {
      issues.add(
        const ReceiptIssue(
          ReceiptIssue.noLines,
          'No se reconoció ningún producto',
        ),
      );
    }
    if (!dateTime.date.isPresent) {
      issues.add(
        const ReceiptIssue(
          ReceiptIssue.missingDate,
          'No se encontró la fecha del ticket',
        ),
      );
    }

    return ReceiptExtraction(
      engine: 'mlkit',
      merchantName: merchant,
      brandKey: profile?.brandKey,
      category: profile?.category ?? EsMerchantProfiles.fallbackCategory(lines),
      date: dateTime.date,
      time: dateTime.time,
      lines: body.lines,
      taxes: taxes,
      discounts: body.discounts,
      tip: body.tip,
      subtotal: body.subtotal,
      grandTotal: grandTotal,
      issues: issues,
    );
  }

  // ── Fecha y hora (la hora solo se acepta en la línea de la fecha) ─────
  static ({Extracted<String> date, Extracted<String> time}) _extractDateTime(
    List<RawLine> lines,
  ) {
    for (final line in lines) {
      final date = findEsDate(line.text);
      if (date == null) continue;
      final time = findEsTime(line.text);
      return (
        date: Extracted(date.iso, date.confidence),
        time: time == null
            ? const Extracted.missing()
            : Extracted(time.hhmm, time.confidence),
      );
    }
    return (date: const Extracted.missing(), time: const Extracted.missing());
  }

  // ── Total ─────────────────────────────────────────────────────────────
  static ({int index, Extracted<Money> total})? _findGrandTotal(
    List<RawLine> lines,
    int taxZoneStart,
    EsMerchantProfile? profile,
  ) {
    final keywords = [
      for (final k in profile?.extraTotalKeywords ?? const <String>[])
        (pattern: RegExp(k), confidence: 0.95),
      ..._totalKeywords,
    ];
    ({int index, Extracted<Money> total})? best;
    for (var i = 0; i < lines.length; i++) {
      if (taxZoneStart != -1 && i >= taxZoneStart) break;
      final upper = lines[i].text.toUpperCase();
      if (_discountKeyword.hasMatch(upper) || upper.contains('PROPINA')) {
        continue;
      }
      for (final keyword in keywords) {
        if (!keyword.pattern.hasMatch(upper)) continue;
        final amounts = findAmounts(lines[i].text);
        if (amounts.isEmpty) break;
        final confidence =
            keyword.confidence * (lines[i].degradedAmounts ? 0.85 : 1.0);
        // La ÚLTIMA línea con palabra clave gana (el total real va al pie).
        best = (index: i, total: Extracted(amounts.last, confidence));
        break;
      }
    }
    return best;
  }

  // ── IVA (tabla al pie) ────────────────────────────────────────────────
  static List<LabeledAmount> _extractTaxes(
    List<RawLine> lines,
    int taxZoneStart,
  ) {
    if (taxZoneStart == -1) return const [];
    final taxes = <LabeledAmount>[];
    for (var i = taxZoneStart + 1; i < lines.length; i++) {
      final m = _taxRow.firstMatch(lines[i].text);
      if (m == null) {
        if (taxes.isNotEmpty) break; // fin de la tabla
        continue;
      }
      taxes.add(LabeledAmount('IVA ${m[1]}%', parseEsAmount(m[3]!)));
    }
    return taxes;
  }

  static int _bodyEnd(int? totalIndex, int taxZoneStart, int length) {
    var end = totalIndex ?? length;
    if (taxZoneStart != -1 && taxZoneStart < end) end = taxZoneStart;
    return end;
  }

  // ── Cuerpo: productos, descuentos, propina, subtotal ──────────────────
  static ({
    List<ExtractedLine> lines,
    List<LabeledAmount> discounts,
    Extracted<Money> tip,
    Extracted<Money> subtotal,
  })
  _extractBody(
    List<RawLine> lines, {
    required int end,
    required List<RegExp> noise,
    required List<LineRule> rules,
  }) {
    final products = <ExtractedLine>[];
    final discounts = <LabeledAmount>[];
    var tip = const Extracted<Money>.missing();
    var subtotal = const Extracted<Money>.missing();

    ({String name, int quantityMilli})? pending;

    for (var i = 0; i < end; i++) {
      final line = lines[i];
      final text = line.text;
      final upper = text.toUpperCase();
      final degraded = line.degradedAmounts ? 0.85 : 1.0;
      final amounts = findAmounts(text);

      if (noise.any((n) => n.hasMatch(upper))) {
        pending = null;
        continue;
      }

      // Desglose fiscal suelto (A12): ni producto ni descuento. El importe
      // sigue viviendo en `grandTotal`, que es lo que se pagó; no se
      // reconstruye el impuesto a partir de una línea suelta porque la base
      // y la cuota no siempre son distinguibles sin la tabla del pie.
      if (_fiscalKeyword.hasMatch(upper)) {
        pending = null;
        continue;
      }

      if (upper.contains('SUBTOTAL') && amounts.isNotEmpty) {
        subtotal = Extracted(amounts.last, 0.9 * degraded);
        pending = null;
        continue;
      }
      if (upper.contains('PROPINA') && amounts.isNotEmpty) {
        tip = Extracted(amounts.last, 0.9 * degraded);
        pending = null;
        continue;
      }
      if (_discountKeyword.hasMatch(upper) && amounts.isNotEmpty) {
        discounts.add(LabeledAmount(_stripAmounts(text), amounts.last.abs()));
        pending = null;
        continue;
      }
      // Importe negativo suelto = descuento sin etiqueta clara.
      if (amounts.isNotEmpty && amounts.last.isNegative) {
        discounts.add(
          LabeledAmount(
            _stripAmounts(text).isEmpty ? 'Descuento' : _stripAmounts(text),
            amounts.last.abs(),
          ),
        );
        pending = null;
        continue;
      }

      // Continuaciones que consumen el nombre pendiente.
      if (pending != null) {
        final consumed = _tryPendingContinuation(text, pending, degraded);
        if (consumed != null) {
          products.add(consumed);
          pending = null;
          continue;
        }
      }

      // Reglas de producto.
      final interpretations = <LineInterpretation>[];
      for (final rule in rules) {
        final it = rule.tryMatch(text);
        if (it != null) interpretations.add(it);
      }
      if (interpretations.isNotEmpty) {
        interpretations.sort((a, b) => b.confidence.compareTo(a.confidence));
        final chosen = interpretations.first;
        final alternatives = <LineAlternative>[];
        for (final other in interpretations.skip(1)) {
          if (other.sameOutcomeAs(chosen) || alternatives.length == 2) {
            continue;
          }
          alternatives.add(
            LineAlternative(
              name: other.name,
              quantityMilli: other.quantityMilli,
              unitPrice: other.unitPrice,
              totalPrice: other.totalPrice,
              confidence: other.confidence * degraded,
            ),
          );
        }
        products.add(
          ExtractedLine(
            name: chosen.name,
            quantityMilli: chosen.quantityMilli,
            unitPrice: chosen.unitPrice,
            totalPrice: chosen.totalPrice,
            confidence: (chosen.confidence * degraded).clamp(0, 1),
            sourceText: text,
            alternatives: alternatives,
          ),
        );
        pending = null;
        continue;
      }

      // Nombre pendiente: "1 PLATANO" o línea de solo texto.
      if (amounts.isEmpty && hasNameLetters(text)) {
        final qtyName = _pendingQtyName.firstMatch(text);
        pending = qtyName != null && hasNameLetters(qtyName[2]!)
            ? (
                name: qtyName[2]!.trim(),
                quantityMilli: int.parse(qtyName[1]!) * 1000,
              )
            : (name: text, quantityMilli: 1000);
        continue;
      }

      pending = null;
    }

    return (
      lines: products,
      discounts: discounts,
      tip: tip,
      subtotal: subtotal,
    );
  }

  static ExtractedLine? _tryPendingContinuation(
    String text,
    ({String name, int quantityMilli}) pending,
    double degraded,
  ) {
    final weight = _pendingWeight.firstMatch(text);
    if (weight != null) {
      final kg = double.parse(weight[1]!.replaceAll(',', '.'));
      final unit = parseEsAmount(weight[2]!);
      final total = parseEsAmount(weight[3]!);
      return ExtractedLine(
        name: pending.name,
        quantityMilli: (kg * 1000).round(),
        unitPrice: unit,
        totalPrice: total,
        confidence: 0.92 * degraded,
        sourceText: '${pending.name} | $text',
      );
    }
    final mult = _pendingMult.firstMatch(text);
    if (mult != null) {
      final qty = int.parse(mult[1]!);
      final unit = parseEsAmount(mult[2]!);
      final total = parseEsAmount(mult[3]!);
      final consistent = (unit * qty) == total;
      return ExtractedLine(
        name: pending.name,
        quantityMilli: qty * 1000,
        unitPrice: unit,
        totalPrice: total,
        confidence: (consistent ? 0.95 : 0.6) * degraded,
        sourceText: '${pending.name} | $text',
      );
    }
    return null;
  }

  static String _stripAmounts(String text) => text
      .replaceAll(RegExp('($amountSrc)(?!\\d)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Extracted<String> _fallbackMerchant(
    List<RawLine> lines,
    List<RegExp> noise,
  ) {
    for (final line in lines.take(4)) {
      final upper = line.text.toUpperCase();
      if (!hasNameLetters(line.text)) continue;
      if (noise.any((n) => n.hasMatch(upper))) continue;
      if (findAmounts(line.text).isNotEmpty) continue;
      if (findEsDate(line.text) != null) continue;
      return Extracted(line.text, 0.6);
    }
    return const Extracted.missing();
  }

  // ── Implementación de las reglas por defecto ──────────────────────────

  static final _reQtyNameUnitTotal = RegExp(
    '^(\\d{1,2})\\s+(.+?)\\s+($amountSrc)\\s+($amountSrc)\\s*[A-D]?\$',
  );

  static LineInterpretation? _qtyNameUnitTotal(String text) {
    final m = _reQtyNameUnitTotal.firstMatch(text);
    if (m == null || !hasNameLetters(m[2]!)) return null;
    final qty = int.parse(m[1]!);
    final unit = parseEsAmount(m[3]!);
    final total = parseEsAmount(m[4]!);
    final consistent = (unit * qty) == total;
    return LineInterpretation(
      name: m[2]!.trim(),
      quantityMilli: qty * 1000,
      unitPrice: unit,
      totalPrice: total,
      confidence: consistent ? 0.97 : 0.55,
    );
  }

  static final _reMultNameTotal = RegExp(
    '^(\\d{1,3})\\s*[xX]\\s*($amountSrc)\\s+(.+?)\\s+($amountSrc)\\s*\$',
  );

  static LineInterpretation? _multNameTotal(String text) {
    final m = _reMultNameTotal.firstMatch(text);
    if (m == null || !hasNameLetters(m[3]!)) return null;
    final qty = int.parse(m[1]!);
    final unit = parseEsAmount(m[2]!);
    final total = parseEsAmount(m[4]!);
    return LineInterpretation(
      name: m[3]!.trim(),
      quantityMilli: qty * 1000,
      unitPrice: unit,
      totalPrice: total,
      confidence: (unit * qty) == total ? 0.95 : 0.6,
    );
  }

  static final _reNameMultTotal = RegExp(
    '^(.+?)\\s+(\\d{1,3})\\s*[xX]\\s*($amountSrc)\\s+($amountSrc)\\s*\$',
  );

  static LineInterpretation? _nameMultTotal(String text) {
    final m = _reNameMultTotal.firstMatch(text);
    if (m == null || !hasNameLetters(m[1]!)) return null;
    final qty = int.parse(m[2]!);
    final unit = parseEsAmount(m[3]!);
    final total = parseEsAmount(m[4]!);
    return LineInterpretation(
      name: m[1]!.trim(),
      quantityMilli: qty * 1000,
      unitPrice: unit,
      totalPrice: total,
      confidence: (unit * qty) == total ? 0.95 : 0.6,
    );
  }

  static final _reWeightInline = RegExp(
    '^(\\d+,\\d{1,3})\\s*[Kk][Gg]\\.?\\s+(.+?)\\s+($amountSrc)\\s*€/[Kk][Gg]'
    '\\s+($amountSrc)\$',
  );

  static LineInterpretation? _weightInline(String text) {
    final m = _reWeightInline.firstMatch(text);
    if (m == null || !hasNameLetters(m[2]!)) return null;
    return LineInterpretation(
      name: m[2]!.trim(),
      quantityMilli: (double.parse(m[1]!.replaceAll(',', '.')) * 1000).round(),
      unitPrice: parseEsAmount(m[3]!),
      totalPrice: parseEsAmount(m[4]!),
      confidence: 0.92,
    );
  }

  static final _reFuel = RegExp(
    '^(.+?)\\s+(\\d+,\\d{1,3})\\s*[Ll]\\.?\\s*[xX]?\\s*\\d+,\\d{1,3}'
    '\\s*€/[Ll]\\s+($amountSrc)\$',
  );

  static LineInterpretation? _fuel(String text) {
    final m = _reFuel.firstMatch(text);
    if (m == null || !hasNameLetters(m[1]!)) return null;
    return LineInterpretation(
      name: m[1]!.trim(),
      quantityMilli: (double.parse(m[2]!.replaceAll(',', '.')) * 1000).round(),
      // €/L con 3 decimales no es representable en céntimos: unitPrice null.
      totalPrice: parseEsAmount(m[3]!),
      confidence: 0.9,
    );
  }

  static final _reQtyNameTotal = RegExp(
    '^(\\d{1,2})\\s+(.+?)\\s+($amountSrc)\\s*[A-D]?\$',
  );

  static LineInterpretation? _qtyNameTotal(String text) {
    final m = _reQtyNameTotal.firstMatch(text);
    if (m == null || !hasNameLetters(m[2]!)) return null;
    final name = m[2]!.trim();
    // Mismo criterio que en `_nameTotal`: si dentro del nombre sigue habiendo
    // un importe sin interpretar, la lectura no está resuelta.
    final suspicious = _nameStartsWithAmount.hasMatch(name);
    return LineInterpretation(
      name: name,
      quantityMilli: int.parse(m[1]!) * 1000,
      totalPrice: parseEsAmount(m[3]!),
      confidence: suspicious ? 0.45 : 0.88,
    );
  }

  static final _reNameTotal = RegExp('^(.{3,}?)\\s+($amountSrc)\\s*[A-D]?\$');

  /// El «nombre» empieza por algo con forma de importe: casi siempre es el
  /// precio unitario impreso a la IZQUIERDA que la regla no supo separar.
  static final _nameStartsWithAmount = RegExp('^($amountSrc)(?!\\d)\\s');

  static LineInterpretation? _nameTotal(String text) {
    final m = _reNameTotal.firstMatch(text);
    if (m == null || !hasNameLetters(m[1]!)) return null;
    final total = parseEsAmount(m[2]!);
    if (total.isNegative) return null; // los negativos son descuentos
    final name = m[1]!.trim();
    // A15: `1,15 MACARRON ROMERO 1 KG   5,75` se leía como UN producto de
    // 5,75 con el precio unitario metido en el nombre y cantidad 1. Cuadraba
    // y no avisaba de nada, y esa cantidad equivocada es la que después
    // decide cuántas unidades repartibles tiene la línea.
    //
    // No se inventa la cantidad —5,75/1,15 = 5 es una división exacta, no una
    // prueba: podría ser peso, oferta o descuento—. Lo que se hace es dejar
    // de afirmar que la línea es fiable: baja de confianza y la revisión la
    // marca para que una persona la mire.
    final suspicious = _nameStartsWithAmount.hasMatch(name);
    return LineInterpretation(
      name: name,
      totalPrice: total,
      confidence: suspicious ? 0.45 : 0.78,
    );
  }
}
