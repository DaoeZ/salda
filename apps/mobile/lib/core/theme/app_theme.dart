import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sistema visual de Salda.
///
/// El tema NO se deriva de una semilla: `ColorScheme.fromSeed` reparte tonos
/// por algoritmo y produce exactamente lo que hay que evitar —Material sin
/// personalizar—. Cada rol se declara en `design_tokens.json` y se elige
/// aquí, de modo que claro y oscuro están DISEÑADOS los dos, no uno invertido
/// desde el otro.
///
/// Jerarquía por **superficie y borde**, nunca por sombra: el producto es una
/// herramienta de dinero y las sombras profundas la vuelven ruidosa.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final c = SaldaColors._of(brightness);
    final text = _textTheme(c);
    final dark = brightness == Brightness.dark;

    // El ColorScheme sigue existiendo porque los widgets de Material lo leen;
    // se rellena a mano con los roles para que nada quede al azar.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryMuted,
      onPrimaryContainer: c.primary,
      secondary: c.accent,
      onSecondary: dark ? c.background : Colors.white,
      secondaryContainer: c.accentMuted,
      onSecondaryContainer: c.accent,
      tertiary: c.positive,
      onTertiary: dark ? c.background : Colors.white,
      tertiaryContainer: c.positiveMuted,
      onTertiaryContainer: c.positive,
      error: c.negative,
      onError: dark ? c.background : Colors.white,
      errorContainer: c.negativeMuted,
      onErrorContainer: c.negative,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surfaceMuted,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceElevated,
      surfaceContainerHighest: c.surfaceElevated,
      onSurfaceVariant: c.textSecondary,
      outline: c.border,
      outlineVariant: c.border,
      shadow: Colors.black,
      scrim: c.overlay,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: c.primaryMuted,
    );

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TokenRadius.card),
      side: BorderSide(color: c.border),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TokenRadius.button),
    );

    InputBorder field(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(TokenRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: TokenTypography.fontFamily,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],

      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: c.background,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: c.background,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        // Separación por defecto hacia abajo: las pantallas que aún apilan
        // `Card` sueltas mantienen el mismo ritmo vertical que las migradas
        // a `SaldaCard`, en vez de quedar pegadas unas a otras.
        margin: const EdgeInsets.only(bottom: TokenSpacing.md),
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
      ),

      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: TokenLayout.hairline,
        space: TokenLayout.hairline,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.disabled.withValues(alpha: 0.35),
          disabledForegroundColor: c.textMuted,
          minimumSize: const Size(0, TokenLayout.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.xxl),
          textStyle: text.labelLarge,
          shape: controlShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.borderStrong),
          minimumSize: const Size(0, TokenLayout.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.xl),
          textStyle: text.labelLarge,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(0, TokenLayout.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.md),
          textStyle: text.labelLarge,
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(
            TokenLayout.minTouchTarget,
            TokenLayout.minTouchTarget,
          ),
        ),
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 22),

      // Un FAB discreto: el acceso principal no necesita un botón enorme.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.card),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.lg,
          vertical: TokenSpacing.md,
        ),
        border: field(c.border),
        enabledBorder: field(c.border),
        focusedBorder: field(c.focus, width: 1.5),
        errorBorder: field(c.negative),
        focusedErrorBorder: field(c.negative, width: 1.5),
        disabledBorder: field(c.border.withValues(alpha: 0.5)),
        labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        floatingLabelStyle: text.labelMedium?.copyWith(color: c.primary),
        hintStyle: text.bodyMedium?.copyWith(color: c.textMuted),
        helperStyle: text.bodySmall?.copyWith(color: c.textMuted),
        errorStyle: text.bodySmall?.copyWith(color: c.negative),
        prefixIconColor: c.textMuted,
        suffixIconColor: c.textMuted,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.lg,
          vertical: TokenSpacing.xs,
        ),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall?.copyWith(color: c.textSecondary),
        iconColor: c.textSecondary,
        minVerticalPadding: TokenSpacing.md,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.control),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surfaceElevated,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TokenRadius.sheet),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.sheet),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.textPrimary,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
        actionTextColor: dark ? c.primary : c.primaryMuted,
        elevation: 0,
        insetPadding: const EdgeInsets.all(TokenSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.control),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceMuted,
        selectedColor: c.primaryMuted,
        disabledColor: c.surfaceMuted,
        checkmarkColor: c.primary,
        side: BorderSide(color: c.border),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.md,
          vertical: TokenSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.control),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.surfaceMuted,
          foregroundColor: c.textSecondary,
          selectedBackgroundColor: c.primaryMuted,
          selectedForegroundColor: c.primary,
          side: BorderSide(color: c.border),
          textStyle: text.labelMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TokenRadius.control),
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? c.primary
                : c.textMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? c.primary
                : c.textMuted,
          ),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.skeleton,
        circularTrackColor: c.skeleton,
        strokeWidth: 2.5,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? c.primary : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(c.onPrimary),
        side: BorderSide(color: c.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.borderStrong,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: c.skeleton,
        thumbColor: c.primary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.textPrimary,
          borderRadius: BorderRadius.circular(TokenRadius.control),
        ),
        textStyle: text.bodySmall?.copyWith(color: c.background),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.card),
          side: BorderSide(color: c.border),
        ),
      ),
      // Transición corta y sin deslizamientos largos: la navegación no debe
      // hacer esperar.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Escala tipográfica del sistema mapeada sobre los slots de Material, para
  /// que cualquier widget no migrado herede ya la jerarquía correcta.
  static TextTheme _textTheme(SaldaColors c) {
    TextStyle s(
      double size,
      int weight,
      double tracking,
      double height, {
      Color? color,
    }) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      letterSpacing: tracking,
      height: height,
      color: color ?? c.textPrimary,
    );

    return TextTheme(
      displayLarge: s(
        TokenTypography.displaySize,
        TokenTypography.displayWeight,
        TokenTypography.displayTracking,
        TokenTypography.displayHeight,
      ),
      displayMedium: s(
        TokenTypography.moneyLargeSize,
        TokenTypography.moneyLargeWeight,
        TokenTypography.moneyLargeTracking,
        TokenTypography.moneyLargeHeight,
      ),
      headlineMedium: s(
        TokenTypography.pageTitleSize,
        TokenTypography.pageTitleWeight,
        TokenTypography.pageTitleTracking,
        TokenTypography.pageTitleHeight,
      ),
      headlineSmall: s(
        TokenTypography.moneyMediumSize,
        TokenTypography.moneyMediumWeight,
        TokenTypography.moneyMediumTracking,
        TokenTypography.moneyMediumHeight,
      ),
      titleLarge: s(
        TokenTypography.pageTitleSize,
        TokenTypography.pageTitleWeight,
        TokenTypography.pageTitleTracking,
        TokenTypography.pageTitleHeight,
      ),
      titleMedium: s(
        TokenTypography.cardTitleSize,
        TokenTypography.cardTitleWeight,
        TokenTypography.cardTitleTracking,
        TokenTypography.cardTitleHeight,
      ),
      titleSmall: s(
        TokenTypography.bodyStrongSize,
        TokenTypography.bodyStrongWeight,
        TokenTypography.bodyStrongTracking,
        TokenTypography.bodyStrongHeight,
      ),
      bodyLarge: s(
        TokenTypography.bodySize,
        TokenTypography.bodyWeight,
        TokenTypography.bodyTracking,
        TokenTypography.bodyHeight,
      ),
      bodyMedium: s(
        TokenTypography.bodySize,
        TokenTypography.bodyWeight,
        TokenTypography.bodyTracking,
        TokenTypography.bodyHeight,
      ),
      bodySmall: s(
        TokenTypography.captionSize,
        TokenTypography.captionWeight,
        TokenTypography.captionTracking,
        TokenTypography.captionHeight,
        color: c.textSecondary,
      ),
      labelLarge: s(
        TokenTypography.labelSize,
        600,
        TokenTypography.labelTracking,
        TokenTypography.labelHeight,
      ),
      labelMedium: s(
        TokenTypography.labelSize,
        TokenTypography.labelWeight,
        TokenTypography.labelTracking,
        TokenTypography.labelHeight,
      ),
      labelSmall: s(
        TokenTypography.captionSize,
        500,
        TokenTypography.captionTracking,
        TokenTypography.captionHeight,
      ),
    );
  }
}

/// Roles de color del sistema, disponibles en cualquier widget mediante
/// `Theme.of(context).salda` o el atajo `context.salda`.
///
/// Es una `ThemeExtension` y no un puñado de constantes sueltas para que el
/// color dependa SIEMPRE del tema activo: así el modo oscuro no puede
/// quedarse a medias por un color escrito a mano en una pantalla.
@immutable
class SaldaColors extends ThemeExtension<SaldaColors> {
  const SaldaColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.primaryMuted,
    required this.accent,
    required this.accentMuted,
    required this.positive,
    required this.positiveMuted,
    required this.negative,
    required this.negativeMuted,
    required this.warning,
    required this.pending,
    required this.disabled,
    required this.overlay,
    required this.skeleton,
    required this.focus,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color onPrimary;
  final Color primaryMuted;
  final Color accent;
  final Color accentMuted;
  final Color positive;
  final Color positiveMuted;
  final Color negative;
  final Color negativeMuted;
  final Color warning;
  final Color pending;
  final Color disabled;
  final Color overlay;
  final Color skeleton;
  final Color focus;

  static SaldaColors _of(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    Color pick(int light, int darkValue) => Color(dark ? darkValue : light);
    return SaldaColors(
      background: pick(TokenColors.backgroundLight, TokenColors.backgroundDark),
      surface: pick(TokenColors.surfaceLight, TokenColors.surfaceDark),
      surfaceElevated: pick(
        TokenColors.surfaceElevatedLight,
        TokenColors.surfaceElevatedDark,
      ),
      surfaceMuted: pick(
        TokenColors.surfaceMutedLight,
        TokenColors.surfaceMutedDark,
      ),
      border: pick(TokenColors.borderLight, TokenColors.borderDark),
      borderStrong: pick(
        TokenColors.borderStrongLight,
        TokenColors.borderStrongDark,
      ),
      textPrimary: pick(
        TokenColors.textPrimaryLight,
        TokenColors.textPrimaryDark,
      ),
      textSecondary: pick(
        TokenColors.textSecondaryLight,
        TokenColors.textSecondaryDark,
      ),
      // El token claro original no alcanzaba contraste AA sobre blanco para
      // texto pequeño. Se ajusta en el rol semántico de la app sin alterar la
      // marca compartida ni la paleta oscura.
      textMuted: Color(dark ? TokenColors.textMutedDark : 0xFF59645F),
      primary: pick(TokenColors.primaryLight, TokenColors.primaryDark),
      onPrimary: pick(TokenColors.onPrimaryLight, TokenColors.onPrimaryDark),
      primaryMuted: pick(
        TokenColors.primaryMutedLight,
        TokenColors.primaryMutedDark,
      ),
      accent: pick(TokenColors.accentLight, TokenColors.accentDark),
      accentMuted: pick(
        TokenColors.accentMutedLight,
        TokenColors.accentMutedDark,
      ),
      positive: pick(TokenColors.positiveLight, TokenColors.positiveDark),
      positiveMuted: pick(
        TokenColors.positiveMutedLight,
        TokenColors.positiveMutedDark,
      ),
      negative: pick(TokenColors.negativeLight, TokenColors.negativeDark),
      negativeMuted: pick(
        TokenColors.negativeMutedLight,
        TokenColors.negativeMutedDark,
      ),
      warning: pick(TokenColors.warningLight, TokenColors.warningDark),
      pending: pick(TokenColors.pendingLight, TokenColors.pendingDark),
      disabled: pick(TokenColors.disabledLight, TokenColors.disabledDark),
      overlay: pick(TokenColors.overlayLight, TokenColors.overlayDark),
      skeleton: pick(TokenColors.skeletonLight, TokenColors.skeletonDark),
      focus: pick(TokenColors.focusLight, TokenColors.focusDark),
    );
  }

  @override
  SaldaColors copyWith() => this;

  @override
  SaldaColors lerp(ThemeExtension<SaldaColors>? other, double t) =>
      // Los roles no se interpolan: el tema cambia de golpe, y mezclar dos
      // paletas a medio camino produce colores que nadie ha diseñado.
      t < 0.5 ? this : (other as SaldaColors? ?? this);
}

extension SaldaColorsAccess on BuildContext {
  /// Roles del sistema visual para este contexto.
  SaldaColors get salda =>
      Theme.of(this).extension<SaldaColors>() ??
      SaldaColors._of(Theme.of(this).brightness);
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
