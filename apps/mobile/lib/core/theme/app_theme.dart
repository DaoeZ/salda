import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sistema visual de Salda 8: «papel y tinta».
///
/// Un libro de cuentas contemporáneo: fondo de papel templado, texto en tinta
/// azul-negra, una sola tinta de acción (ultramar) y el verde/rojo reservados
/// a lo que significan —a tu favor, en tu contra—, nunca a decorar.
///
/// La paleta vive AQUÍ y no en `design_tokens.json` a propósito: los tokens
/// compartidos también pintan la web de invitados, y este rediseño es solo de
/// la app. Espaciado, movimiento y layout siguen saliendo de los tokens.
///
/// Jerarquía por superficie, borde y tipografía, nunca por sombra.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final c = SaldaColors._of(brightness);
    final dark = brightness == Brightness.dark;
    // Sobre la tipografía de la PLATAFORMA (Roboto en Android, SF en iOS):
    // los estilos que se pasan a los componentes deben llevar ya la familia,
    // o un botón hereda la del motor y no la del sistema.
    final platform = Typography.material2021();
    final text = (dark ? platform.white : platform.black).merge(_textTheme(c));

    // El ColorScheme sigue existiendo porque los widgets de Material lo leen;
    // se rellena a mano con los roles para que nada quede al azar.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryMuted,
      onPrimaryContainer: c.primary,
      // Secundario = la misma tinta en su versión tenue. El ocre de aviso
      // NO entra en el esquema: los botones tonales y los chips seleccionados
      // lo usaban como si fuera un color de acción.
      secondary: c.primary,
      onSecondary: c.onPrimary,
      secondaryContainer: c.primaryMuted,
      onSecondaryContainer: c.primary,
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
      // `outline` es el borde de los controles (campos, botones con
      // contorno): necesita presencia. Los filetes de lista son la variante.
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: Colors.black,
      scrim: c.overlay,
      inverseSurface: c.ink,
      onInverseSurface: c.onInk,
      inversePrimary: c.primaryMuted,
    );

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SaldaRadius.surface),
      side: BorderSide(color: c.border),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SaldaRadius.control),
    );

    InputBorder field(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(SaldaRadius.control),
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
      // Tinta plana, sin destellos: el brillo de InkSparkle choca con el papel.
      splashFactory: InkRipple.splashFactory,
      extensions: [c],

      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // El título de cada pantalla es un titular, no una etiqueta: va en
        // la serifa editorial, como la cabecera de una página del libro.
        titleTextStyle: SaldaType.serif(
          size: 20,
          weight: FontWeight.w600,
          color: c.textPrimary,
          tracking: -0.2,
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.xl),
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
          padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.lg),
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

      // Botón principal de tinta, esquina contenida: un tampón, no una
      // pastilla flotante.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaldaRadius.control),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.lg,
          vertical: TokenSpacing.md,
        ),
        border: field(c.borderStrong),
        enabledBorder: field(c.borderStrong),
        focusedBorder: field(c.focus, width: 1.5),
        errorBorder: field(c.negative),
        focusedErrorBorder: field(c.negative, width: 1.5),
        disabledBorder: field(c.border),
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
        // Filas de libro: rectas. La esquina redondeada por fila era el
        // origen de la sensación de «plantilla».
        shape: const RoundedRectangleBorder(),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surfaceElevated,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        dragHandleSize: const Size(32, 3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SaldaRadius.sheet),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: SaldaType.serif(
          size: 20,
          weight: FontWeight.w600,
          color: c.textPrimary,
        ),
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaldaRadius.sheet),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInk),
        actionTextColor: c.inkAccent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(TokenSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaldaRadius.control),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primaryMuted,
        disabledColor: c.surfaceMuted,
        checkmarkColor: c.primary,
        side: BorderSide(color: c.borderStrong),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.sm,
          vertical: TokenSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaldaRadius.badge),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.textSecondary,
          selectedBackgroundColor: c.ink,
          selectedForegroundColor: c.onInk,
          side: BorderSide(color: c.borderStrong),
          textStyle: text.labelMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SaldaRadius.control),
          ),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.skeleton,
        circularTrackColor: c.skeleton,
        strokeWidth: 2,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
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
          color: c.ink,
          borderRadius: BorderRadius.circular(SaldaRadius.badge),
        ),
        textStyle: text.bodySmall?.copyWith(color: c.onInk),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaldaRadius.control),
          side: BorderSide(color: c.borderStrong),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelMedium,
        indicatorColor: c.textPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.border,
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

  /// Escala tipográfica mapeada sobre los slots de Material, para que
  /// cualquier widget no migrado herede ya la jerarquía correcta.
  ///
  /// Dos voces y nada más: la serifa para lo que es TITULAR (páginas, cifra
  /// agregada) y la sans del sistema para todo lo que se opera. La mono solo
  /// aparece dentro del recibo, ver [SaldaType.mono].
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
      displayLarge: SaldaType.serif(
        size: 40,
        weight: FontWeight.w600,
        color: c.textPrimary,
        tracking: -1.0,
        height: 1.05,
      ),
      // Cifra agregada (MoneySize.large): serifa con cifras tabulares, como
      // el total al pie de una página del libro mayor.
      displayMedium: SaldaType.serif(
        size: 34,
        weight: FontWeight.w600,
        color: c.textPrimary,
        tracking: -0.8,
        height: 1.1,
      ),
      headlineMedium: SaldaType.serif(
        size: 28,
        weight: FontWeight.w600,
        color: c.textPrimary,
        tracking: -0.5,
        height: 1.15,
      ),
      headlineSmall: s(
        TokenTypography.moneyMediumSize,
        TokenTypography.moneyMediumWeight,
        TokenTypography.moneyMediumTracking,
        TokenTypography.moneyMediumHeight,
      ),
      titleLarge: SaldaType.serif(
        size: 24,
        weight: FontWeight.w600,
        color: c.textPrimary,
        tracking: -0.4,
        height: 1.2,
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
        TokenTypography.captionSize + 1,
        TokenTypography.captionWeight,
        TokenTypography.captionTracking,
        TokenTypography.captionHeight,
        color: c.textSecondary,
      ),
      labelLarge: s(
        TokenTypography.labelSize + 1,
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

/// Radios de Salda 8. Contenidos a propósito: el papel tiene esquinas, y
/// el redondeo generoso repetido en cada caja era lo que hacía que todo
/// pareciera la misma plantilla.
abstract final class SaldaRadius {
  /// Etiquetas, chips, sellos.
  static const double badge = 3;

  /// Botones, campos, menús.
  static const double control = 6;

  /// Superficies de contenido (listas, bloques, el panel de tinta).
  static const double surface = 6;

  /// Hojas inferiores y diálogos.
  static const double sheet = 14;
}

/// Las dos familias adicionales del sistema, ambas de PLATAFORMA: no se
/// empaqueta ninguna fuente (licencia, peso del APK y funcionamiento offline
/// resueltos por construcción).
///
/// En Android `serif` resuelve a Noto Serif y `monospace` a Droid Sans Mono,
/// presentes en todas las versiones soportadas. Los repliegues cubren iOS.
abstract final class SaldaType {
  static const serifFamily = 'serif';
  static const serifFallback = ['Noto Serif', 'Georgia', 'Times New Roman'];
  static const monoFamily = 'monospace';
  static const monoFallback = ['Droid Sans Mono', 'Menlo', 'Courier New'];

  static const tabular = [FontFeature.tabularFigures()];

  /// Cifras de caja alta y ancho fijo: una serifa de libro trae por defecto
  /// cifras «elzevirianas» que bailan en la línea y no encolumnan.
  static const tabularLining = [
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  /// Voz de titular: páginas, cifras agregadas, el comercio del recibo.
  static TextStyle serif({
    required double size,
    required FontWeight weight,
    required Color color,
    double tracking = 0,
    double height = 1.2,
  }) => TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: serifFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: tracking,
    height: height,
    fontFeatures: tabularLining,
  );

  /// Voz de recibo. SOLO dentro del ticket, donde el ancho fijo tiene
  /// significado: columnas de cantidad e importe que se leen como un
  /// comprobante impreso. Fuera del recibo, la sans tabular basta.
  static TextStyle mono({
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double tracking = 0,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: tracking,
    height: 1.35,
    fontFeatures: tabular,
  );
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
    required this.ink,
    required this.onInk,
    required this.onInkMuted,
    required this.inkRule,
    required this.inkPositive,
    required this.inkNegative,
    required this.inkAccent,
    required this.paper,
    required this.paperRule,
  });

  /// Papel: el fondo de todas las pantallas.
  final Color background;

  /// Hoja: listas y bloques contenidos, un punto más clara que el papel.
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;

  /// Tinta azul-negra.
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Ultramar: la ÚNICA tinta de acción.
  final Color primary;
  final Color onPrimary;
  final Color primaryMuted;

  /// Ocre de aviso (no de marca).
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

  /// Superficie de tinta para cifras agregadas. EXCEPCIONAL: una por
  /// pantalla como mucho.
  final Color ink;
  final Color onInk;
  final Color onInkMuted;
  final Color inkRule;
  final Color inkPositive;
  final Color inkNegative;
  final Color inkAccent;

  /// Papel del recibo: solo el detalle del ticket.
  final Color paper;
  final Color paperRule;

  static SaldaColors _of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static const _light = SaldaColors(
    background: Color(0xFFF3F0E8),
    surface: Color(0xFFFBFAF6),
    surfaceElevated: Color(0xFFFDFCF9),
    surfaceMuted: Color(0xFFEAE6DC),
    border: Color(0xFFDDD8CC),
    borderStrong: Color(0xFFB7B0A1),
    textPrimary: Color(0xFF181A21),
    textSecondary: Color(0xFF474A54),
    textMuted: Color(0xFF5F626C),
    primary: Color(0xFF22389A),
    onPrimary: Color(0xFFFFFFFF),
    primaryMuted: Color(0xFFE2E5F2),
    accent: Color(0xFF8E5410),
    accentMuted: Color(0xFFF3E6D1),
    positive: Color(0xFF1C6A42),
    positiveMuted: Color(0xFFE1EDE4),
    negative: Color(0xFFA7261D),
    negativeMuted: Color(0xFFF5E3DF),
    warning: Color(0xFF855400),
    pending: Color(0xFF686456),
    disabled: Color(0xFFA6A49C),
    overlay: Color(0xFF181A21),
    skeleton: Color(0xFFE3DFD4),
    focus: Color(0xFF22389A),
    ink: Color(0xFF171A26),
    onInk: Color(0xFFF3F0E8),
    onInkMuted: Color(0xFFA7AAB9),
    inkRule: Color(0xFF30344A),
    inkPositive: Color(0xFF8AD6AA),
    inkNegative: Color(0xFFF4A59B),
    inkAccent: Color(0xFFB6C4FF),
    paper: Color(0xFFFFFDF8),
    paperRule: Color(0xFFC9C1B0),
  );

  static const _dark = SaldaColors(
    background: Color(0xFF121419),
    surface: Color(0xFF191C23),
    surfaceElevated: Color(0xFF20242C),
    surfaceMuted: Color(0xFF16181E),
    border: Color(0xFF2A2E38),
    borderStrong: Color(0xFF414654),
    textPrimary: Color(0xFFECE8DE),
    textSecondary: Color(0xFFB6B3AA),
    textMuted: Color(0xFF94918A),
    primary: Color(0xFFA3B4FF),
    onPrimary: Color(0xFF0F1638),
    primaryMuted: Color(0xFF1F2849),
    accent: Color(0xFFE2A95E),
    accentMuted: Color(0xFF33281A),
    positive: Color(0xFF7FCC9E),
    positiveMuted: Color(0xFF15291E),
    negative: Color(0xFFF1978D),
    negativeMuted: Color(0xFF34191A),
    warning: Color(0xFFE9B65C),
    pending: Color(0xFFB0A995),
    disabled: Color(0xFF535866),
    overlay: Color(0xFF000000),
    skeleton: Color(0xFF252933),
    focus: Color(0xFFA3B4FF),
    // En oscuro la tinta se hunde un punto por debajo del fondo y se
    // separa con borde: invertir a claro convertiría la excepción en un foco.
    ink: Color(0xFF0B0D12),
    onInk: Color(0xFFECE8DE),
    onInkMuted: Color(0xFF9A9DAB),
    inkRule: Color(0xFF2A2E3A),
    inkPositive: Color(0xFF7FCC9E),
    inkNegative: Color(0xFFF1978D),
    inkAccent: Color(0xFFA3B4FF),
    paper: Color(0xFF1D2028),
    paperRule: Color(0xFF454A57),
  );

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
/// (estados de liquidación y signo de balances — §3.1). Salen de los mismos
/// roles que el resto de la app para que un estado no tenga dos verdes.
extension SemanticColors on ColorScheme {
  SaldaColors get _c => SaldaColors._of(brightness);

  Color get settlementPending => _c.pending;

  Color get settlementMarked => _c.warning;

  Color get settlementConfirmed => _c.positive;

  Color get balancePositive => _c.positive;

  Color get balanceNegative => _c.negative;
}
