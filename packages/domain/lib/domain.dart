/// Núcleo de dominio de Salda (nombre provisional).
///
/// Dart puro: sin Flutter, sin Firebase, sin IO. Aquí viven las entidades,
/// los value objects (`Money`, `ShareCode`) y los motores deterministas
/// (`SplitEngine`, `BalanceEngine`) — ver ESPECIFICACION.md §8.
///
/// Se implementa en M1. Los motores se validan contra los vectores dorados
/// de `test/golden/`, compartidos con la implementación TS de las functions.
library;
