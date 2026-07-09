import 'errors.dart';

/// Cantidad de dinero en céntimos enteros (regla DC-7 de la especificación:
/// jamás `double` para dinero). La moneda vive a nivel de sesión; aquí solo
/// aritmética exacta.
///
/// Extension type: coste cero en runtime, seguridad de tipos en compilación
/// (un `Money` no se mezcla accidentalmente con un `int` cualquiera).
extension type const Money(int cents) {
  static const zero = Money(0);

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);
  Money operator *(int factor) => Money(cents * factor);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;
  Money abs() => Money(cents.abs());
}

/// Reparte [total] proporcionalmente a [weights] con el método del resto
/// mayor (largest remainder): la suma de las partes es SIEMPRE exactamente
/// [total] y el resultado es determinista (empates → índice menor).
///
/// Es la única primitiva de redondeo del sistema; SplitEngine y BalanceEngine
/// se apoyan en ella (ESPECIFICACION.md RF-45).
List<Money> allocateProportionally(Money total, List<int> weights) {
  if (weights.isEmpty) {
    throw const DomainException(
      DomainException.emptyParticipants,
      'No se puede repartir entre cero partes',
    );
  }
  if (weights.any((w) => w < 0)) {
    throw const DomainException(
      DomainException.invalidWeights,
      'Los pesos no pueden ser negativos',
    );
  }
  final totalWeight = weights.fold<int>(0, (a, b) => a + b);
  if (totalWeight == 0) {
    throw const DomainException(
      DomainException.invalidWeights,
      'La suma de pesos no puede ser cero',
    );
  }

  // Totales negativos (p. ej. ajustes): se reparte el valor absoluto y se
  // niega, conservando el mismo criterio determinista de desempate.
  if (total.isNegative) {
    return allocateProportionally(-total, weights)
        .map((m) => -m)
        .toList(growable: false);
  }

  final base = List<int>.generate(
    weights.length,
    (i) => total.cents * weights[i] ~/ totalWeight,
    growable: false,
  );
  final remainders = List<int>.generate(
    weights.length,
    (i) => total.cents * weights[i] % totalWeight,
    growable: false,
  );

  var leftover = total.cents - base.fold<int>(0, (a, b) => a + b);
  final result = List<int>.of(base);

  // Índices ordenados por resto descendente; empate → índice menor.
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (leftover == 0) break;
    result[i] += 1;
    leftover -= 1;
  }

  return result.map(Money.new).toList(growable: false);
}

/// Reparto a partes iguales entre [parts] (caso particular del proporcional).
List<Money> allocateEvenly(Money total, int parts) =>
    allocateProportionally(total, List<int>.filled(parts, 1));
