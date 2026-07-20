import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// Tema Material 3 construido desde los tokens de diseño
/// (ESPECIFICACION.md §3). Dynamic Color desactivado por defecto:
/// la marca manda (RNF-01); se ofrecerá como opción en Ajustes (M5).
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(TokenColors.seed),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: TokenTypography.fontFamily,
      cardTheme: CardThemeData(
        elevation: 0, // jerarquía por tono, no por sombra (§3.4)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, TokenLayout.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TokenRadius.button),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TokenRadius.field),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TokenRadius.sheet),
          ),
        ),
      ),
    );
  }
}

/// Colores semánticos que no forman parte del ColorScheme M3
/// (estados de liquidación y signo de balances — §3.1).
extension SemanticColors on ColorScheme {
  bool get _dark => brightness == Brightness.dark;

  Color get settlementPending => Color(
    _dark
        ? TokenColors.settlementPendingDark
        : TokenColors.settlementPendingLight,
  );

  Color get settlementMarked => Color(
    _dark
        ? TokenColors.settlementMarkedDark
        : TokenColors.settlementMarkedLight,
  );

  Color get settlementConfirmed => Color(
    _dark
        ? TokenColors.settlementConfirmedDark
        : TokenColors.settlementConfirmedLight,
  );

  Color get balancePositive => Color(
    _dark ? TokenColors.balancePositiveDark : TokenColors.balancePositiveLight,
  );

  Color get balanceNegative => Color(
    _dark ? TokenColors.balanceNegativeDark : TokenColors.balanceNegativeLight,
  );
}
