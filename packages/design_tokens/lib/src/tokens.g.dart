// GENERATED por design_tokens:generate — NO EDITAR A MANO.
// Fuente: assets/brand.json + assets/design_tokens.json
// ignore_for_file: public_member_api_docs

abstract final class Brand {
  static const String appName = 'Salda';
  static const String tagline = 'Escanea el ticket, reparte y salda cuentas.';
  static const bool provisional = true;
  static const String hostingDomain = 'salda-dev.web.app';
}

/// Colores como int ARGB; la app los envuelve en `Color(...)`.
abstract final class TokenColors {
  static const int seed = 0xFF0B6E5D;
  static const int settlementPendingLight = 0xFF5F6368;
  static const int settlementPendingDark = 0xFF9AA0A6;
  static const int settlementMarkedLight = 0xFFB58500;
  static const int settlementMarkedDark = 0xFFFFD166;
  static const int settlementConfirmedLight = 0xFF1B7A43;
  static const int settlementConfirmedDark = 0xFF6CD597;
  static const int balancePositiveLight = 0xFF1B7A43;
  static const int balancePositiveDark = 0xFF6CD597;
  static const int balanceNegativeLight = 0xFFB3261E;
  static const int balanceNegativeDark = 0xFFF2B8B5;
  static const List<int> avatarPalette = [0xFF0B6E5D, 0xFF5B7C99, 0xFF8C6D4F, 0xFF7A5EA6, 0xFFB05A7A, 0xFF4E8098, 0xFF96772E, 0xFF5E8C5A];
}

abstract final class TokenTypography {
  static const String fontFamily = 'Inter';
  static const double displayLargeSize = 45;
  static const int displayLargeWeight = 600;
  static const double headlineSize = 28;
  static const int headlineWeight = 600;
  static const double titleSize = 20;
  static const int titleWeight = 600;
  static const double bodySize = 16;
  static const int bodyWeight = 400;
  static const double bodySmallSize = 14;
  static const int bodySmallWeight = 400;
  static const double labelSize = 12;
  static const int labelWeight = 500;
}

abstract final class TokenSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class TokenRadius {
  static const double card = 16;
  static const double sheet = 28;
  static const double button = 24;
  static const double field = 12;
  static const double thumbnail = 8;
}

abstract final class TokenMotion {
  /// Curva M3 emphasized: cubic-bezier(x1, y1, x2, y2).
  static const List<double> easingEmphasized = [0.2, 0.0, 0.0, 1.0];
  static const int toggleMs = 150;
  static const int exitMs = 200;
  static const int enterMs = 350;
  static const int maxMs = 500;
  static const int listStaggerMs = 25;
  static const int skeletonShimmerMs = 1200;
  static const int syncIndicatorDelayMs = 400;
}

abstract final class TokenLayout {
  static const double screenMargin = 16;
  static const double minTouchTarget = 48;
  static const double thumbnailSize = 56;
}
