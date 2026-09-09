import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/money_format.dart';

/// Tamaños de importe del sistema. Un importe no es texto corriente: se
/// compara de un vistazo, así que va siempre en cifras tabulares y en una
/// sola línea.
enum MoneySize { large, medium, small }

/// Signo económico. El color NO es el único portador: cada estado lleva
/// además signo y rótulo, para quien no distingue verde de rojo.
enum MoneyTone { neutral, positive, negative, muted }

/// Importe con tratamiento tipográfico propio.
///
/// Cifras tabulares (`tnum`) para que las columnas de dígitos se alineen
/// entre filas, `softWrap: false` para que «1.234,56 €» nunca parta, y
/// tamaño fijado por el sistema en vez de por cada pantalla.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.money, {
    super.key,
    this.size = MoneySize.medium,
    this.tone = MoneyTone.neutral,
    this.currency,
    this.signed = false,
    this.semanticsLabel,
  });

  final Money money;
  final MoneySize size;
  final MoneyTone tone;

  /// Moneda explícita (P5 nunca mezcla monedas). Null = la de la app.
  final String? currency;

  /// Antepone `+` a los positivos. Los negativos ya lo llevan por formato.
  final bool signed;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final theme = Theme.of(context);
    final base = switch (size) {
      MoneySize.large => theme.textTheme.displayMedium,
      MoneySize.medium => theme.textTheme.headlineSmall,
      MoneySize.small => theme.textTheme.titleSmall,
    };
    final color = switch (tone) {
      MoneyTone.neutral => c.textPrimary,
      MoneyTone.positive => c.positive,
      MoneyTone.negative => c.negative,
      MoneyTone.muted => c.textMuted,
    };
    final formatted = currency == null
        ? formatMoney(money)
        : formatCurrencyMoney(money, currency!);
    final text = signed && money.cents > 0 ? '+$formatted' : formatted;

    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      semanticsLabel: semanticsLabel,
      style: base?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
