/// Pipeline OCR de tickets (ESPECIFICACION.md §10).
///
/// Entrada agnóstica del motor OCR (`OcrDocument`) → reconstrucción
/// geométrica de filas (`LineBuilder`) → parser por país con perfiles de
/// establecimiento y reglas incrementales → `ReceiptExtraction` (contrato
/// de `domain`, con confianza por campo e inconsistencias detectadas).
library;

export 'src/core/line_rule.dart';
export 'src/core/receipt_parser.dart';
export 'src/es/es_profiles.dart';
export 'src/es/es_receipt_parser.dart';
export 'src/geometry/line_builder.dart';
export 'src/model/ocr_input.dart';
export 'src/model/raw_line.dart';
