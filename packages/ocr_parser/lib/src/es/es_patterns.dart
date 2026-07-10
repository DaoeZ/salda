/// Patrones numéricos y de fecha/hora del formato español.
library;

import 'package:domain/domain.dart';

import '../model/raw_line.dart';

/// Importe español: `1,80` · `1.234,56` · `-0,50`. Fuente para componer
/// regexes de reglas de línea.
const amountSrc = r'-?\d{1,3}(?:\.\d{3})*,\d{2}';

final _amountRe = RegExp('($amountSrc)(?!\\d)');
final _periodAmountRe = RegExp(r'(-?\d+\.\d{2})(?!\d)');

/// Céntimos desde un literal español (`1.234,56` → 123456).
Money parseEsAmount(String text) {
  final normalized = text.replaceAll('.', '').replaceAll(',', '.');
  return Money((double.parse(normalized) * 100).round());
}

/// Todos los importes de una línea, en orden de aparición.
List<Money> findAmounts(String text) =>
    [for (final m in _amountRe.allMatches(text)) parseEsAmount(m[1]!)];

/// Canonicaliza importes con decimales de punto (OCR degradado) a formato
/// español, SOLO si la línea no contiene ya importes con coma. Marca la
/// línea como degradada para bajar la confianza de lo que salga de ella.
RawLine canonicalizeAmounts(RawLine line) {
  if (_amountRe.hasMatch(line.text)) return line;
  if (!_periodAmountRe.hasMatch(line.text)) return line;
  return RawLine(
    line.text.replaceAllMapped(
      _periodAmountRe,
      (m) => m[1]!.replaceAll('.', ','),
    ),
    degradedAmounts: true,
  );
}

final _dateRe = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');

/// Fecha `dd/mm/aaaa` (también `-`/`.` y año de 2 cifras) → ISO + confianza.
({String iso, double confidence})? findEsDate(String text) {
  for (final m in _dateRe.allMatches(text)) {
    final day = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final rawYear = m[3]!;
    var year = int.parse(rawYear);
    if (rawYear.length == 2) year += 2000;
    if (rawYear.length == 3 || day < 1 || day > 31 || month < 1 || month > 12) {
      continue;
    }
    if (year < 2000 || year > 2099) continue;
    final iso = '$year-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
    return (iso: iso, confidence: rawYear.length == 4 ? 0.95 : 0.85);
  }
  return null;
}

// Con `:` el hour puede ser 1 cifra; con `.` exigimos 2 para no confundir
// con precios degradados tipo `1.19`.
final _timeRe = RegExp(
    r'\b((?:[01]?\d|2[0-3]):[0-5]\d|(?:[01]\d|2[0-3])\.[0-5]\d)\b');

({String hhmm, double confidence})? findEsTime(String text) {
  final m = _timeRe.firstMatch(text);
  if (m == null) return null;
  final raw = m[1]!;
  final colon = raw.contains(':');
  final parts = raw.split(colon ? ':' : '.');
  final hhmm = '${parts[0].padLeft(2, '0')}:${parts[1]}';
  return (hhmm: hhmm, confidence: colon ? 0.9 : 0.75);
}

/// ¿Tiene la línea suficiente contenido alfabético para ser un nombre?
bool hasNameLetters(String text) =>
    RegExp(r'[A-Za-zÁÉÍÓÚÑÜáéíóúñü]').allMatches(text).length >= 3;
