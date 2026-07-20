import 'package:domain/domain.dart';
import 'package:intl/intl.dart';

final _es = NumberFormat.currency(locale: 'es_ES', symbol: '€');

/// `Money(180)` → `1,80 €` (formato es-ES con cifras tabulares vía tema).
String formatMoney(Money money) => _es.format(money.cents / 100);

/// Formato explícito para P5: nunca mezcla ni oculta monedas distintas.
String formatCurrencyMoney(Money money, String currency) =>
    NumberFormat.currency(
      locale: 'es_ES',
      name: currency,
      symbol: NumberFormat.simpleCurrency(name: currency).currencySymbol,
    ).format(money.cents / 100);

/// Parsea entrada de usuario (`1,80` · `1.80` · `1,80 €`) a céntimos.
/// Devuelve null si no es interpretable.
Money? parseUserMoney(String input) {
  final cleaned = input.replaceAll('€', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return null;
  final normalized = cleaned.contains(',')
      ? cleaned.replaceAll('.', '').replaceAll(',', '.')
      : cleaned;
  final value = double.tryParse(normalized);
  return value == null ? null : Money((value * 100).round());
}
