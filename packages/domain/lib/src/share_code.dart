import 'dart:convert';
import 'dart:math';

/// Código secreto del enlace de invitados (ESPECIFICACION.md §13.3):
/// 128 bits de CSPRNG en base64url sin padding (22 caracteres URL-safe).
/// Viaja en el fragment de la URL (#k=...) y es regenerable por el anfitrión.
class ShareCode {
  const ShareCode(this.value);

  factory ShareCode.generate([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return ShareCode(base64UrlEncode(bytes).replaceAll('=', ''));
  }

  final String value;

  @override
  bool operator ==(Object other) => other is ShareCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ShareCode(****)'; // nunca volcar el secreto en logs
}
