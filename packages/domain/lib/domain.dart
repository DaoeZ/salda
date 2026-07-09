/// Núcleo de dominio de Salda (nombre provisional).
///
/// Dart puro: sin Flutter, sin Firebase, sin IO. Los motores son
/// deterministas y exactos (Σ partes == total, siempre) y se validan contra
/// los vectores dorados de `test/golden/`, compartidos con la implementación
/// TS de `backend/functions` (ESPECIFICACION.md §8, RNF-09).
library;

export 'src/engines/balance_engine.dart';
export 'src/engines/split_engine.dart';
export 'src/errors.dart';
export 'src/money.dart';
export 'src/share_code.dart';
