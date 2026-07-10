import 'package:domain/domain.dart';

import '../es/es_receipt_parser.dart';
import '../geometry/line_builder.dart';
import '../model/ocr_input.dart';
import '../model/raw_line.dart';

/// Parser de un país/locale concreto. Añadir un país = implementar esta
/// interfaz y registrarla en [ReceiptParser.standard].
abstract interface class CountryReceiptParser {
  String get locale;
  ReceiptExtraction parse(List<RawLine> lines);
}

/// Fachada del parser: registry por locale (extensible a otros países).
class ReceiptParser {
  ReceiptParser(List<CountryReceiptParser> parsers)
      : _byLocale = {for (final p in parsers) p.locale: p};

  /// Configuración estándar de la app (v1: España).
  factory ReceiptParser.standard() => ReceiptParser([EsReceiptParser()]);

  final Map<String, CountryReceiptParser> _byLocale;

  ReceiptExtraction parseLines(List<RawLine> lines, {String locale = 'es'}) {
    final parser = _byLocale[locale] ?? _byLocale['es']!;
    return parser.parse(lines);
  }

  ReceiptExtraction parseDocument(OcrDocument document,
          {String locale = 'es'}) =>
      parseLines(LineBuilder.build(document), locale: locale);

  ReceiptExtraction parsePlainText(String text, {String locale = 'es'}) =>
      parseLines(rawLinesFromPlainText(text), locale: locale);
}
