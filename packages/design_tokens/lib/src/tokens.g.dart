// GENERATED por design_tokens:generate — NO EDITAR A MANO.
// Fuente: assets/brand.json + assets/design_tokens.json
// ignore_for_file: public_member_api_docs

abstract final class Brand {
  static const String appName = 'Salda';
  static const String tagline = 'Escanea el ticket, reparte y salda cuentas.';
  static const bool provisional = true;
  static const String developmentHostingDomain = 'salda-dev.web.app';
  static const String productionHostingDomain = 'salda-prod.web.app';
}

/// Colores como int ARGB; la app los envuelve en `Color(...)`.
abstract final class TokenColors {
  static const int seed = 0xFF0B5E4E;
  static const int backgroundLight = 0xFFF7F6F2;
  static const int backgroundDark = 0xFF101413;
  static const int surfaceLight = 0xFFFFFFFF;
  static const int surfaceDark = 0xFF181D1C;
  static const int surfaceElevatedLight = 0xFFFFFFFF;
  static const int surfaceElevatedDark = 0xFF1F2624;
  static const int surfaceMutedLight = 0xFFEFEEE8;
  static const int surfaceMutedDark = 0xFF141918;
  static const int borderLight = 0xFFE2E0D8;
  static const int borderDark = 0xFF2A312F;
  static const int borderStrongLight = 0xFFC9C6BB;
  static const int borderStrongDark = 0xFF3C4542;
  static const int textPrimaryLight = 0xFF15201C;
  static const int textPrimaryDark = 0xFFF1F3F1;
  static const int textSecondaryLight = 0xFF4C5A55;
  static const int textSecondaryDark = 0xFFAFBAB6;
  static const int textMutedLight = 0xFF77837E;
  static const int textMutedDark = 0xFF7C8783;
  static const int primaryLight = 0xFF0B5E4E;
  static const int primaryDark = 0xFF4FD1A5;
  static const int onPrimaryLight = 0xFFFFFFFF;
  static const int onPrimaryDark = 0xFF062119;
  static const int primaryMutedLight = 0xFFE3EFEA;
  static const int primaryMutedDark = 0xFF17332B;
  static const int accentLight = 0xFFC2612B;
  static const int accentDark = 0xFFE8925A;
  static const int accentMutedLight = 0xFFF8EBE2;
  static const int accentMutedDark = 0xFF33231A;
  static const int positiveLight = 0xFF1B7A4B;
  static const int positiveDark = 0xFF5FCE92;
  static const int positiveMutedLight = 0xFFE4F1E9;
  static const int positiveMutedDark = 0xFF132A1F;
  static const int negativeLight = 0xFFB3261E;
  static const int negativeDark = 0xFFF09891;
  static const int negativeMutedLight = 0xFFFAE9E7;
  static const int negativeMutedDark = 0xFF31191A;
  static const int warningLight = 0xFF8A5A00;
  static const int warningDark = 0xFFE9B65C;
  static const int pendingLight = 0xFF6B6558;
  static const int pendingDark = 0xFFB0A995;
  static const int disabledLight = 0xFFA9B2AE;
  static const int disabledDark = 0xFF525C59;
  static const int overlayLight = 0xFF15201C;
  static const int overlayDark = 0xFF000000;
  static const int skeletonLight = 0xFFE7E5DD;
  static const int skeletonDark = 0xFF232A28;
  static const int focusLight = 0xFF0B5E4E;
  static const int focusDark = 0xFF4FD1A5;
  static const int settlementPendingLight = 0xFF6B6558;
  static const int settlementPendingDark = 0xFFB0A995;
  static const int settlementMarkedLight = 0xFF8A5A00;
  static const int settlementMarkedDark = 0xFFE9B65C;
  static const int settlementConfirmedLight = 0xFF1B7A4B;
  static const int settlementConfirmedDark = 0xFF5FCE92;
  static const int balancePositiveLight = 0xFF1B7A4B;
  static const int balancePositiveDark = 0xFF5FCE92;
  static const int balanceNegativeLight = 0xFFB3261E;
  static const int balanceNegativeDark = 0xFFF09891;
  static const List<int> avatarPalette = [
    0xFF0B5E4E,
    0xFF3F6B8A,
    0xFF8A6136,
    0xFF6B5296,
    0xFF9E4A68,
    0xFF3D7A78,
    0xFF7C6A22,
    0xFF4A7C50,
  ];
}

abstract final class TokenTypography {
  /// Vacío = pila tipográfica del sistema. Ver docs/DISENO.md.
  static const String? fontFamily = null;
  static const double displaySize = 40;
  static const int displayWeight = 700;
  static const double displayTracking = -1.0;
  static const double displayHeight = 1.05;
  static const double pageTitleSize = 26;
  static const int pageTitleWeight = 700;
  static const double pageTitleTracking = -0.5;
  static const double pageTitleHeight = 1.15;
  static const double sectionTitleSize = 15;
  static const int sectionTitleWeight = 600;
  static const double sectionTitleTracking = 0.2;
  static const double sectionTitleHeight = 1.3;
  static const double cardTitleSize = 16;
  static const int cardTitleWeight = 600;
  static const double cardTitleTracking = -0.1;
  static const double cardTitleHeight = 1.3;
  static const double bodySize = 15;
  static const int bodyWeight = 400;
  static const double bodyTracking = 0.0;
  static const double bodyHeight = 1.45;
  static const double bodyStrongSize = 15;
  static const int bodyStrongWeight = 600;
  static const double bodyStrongTracking = 0.0;
  static const double bodyStrongHeight = 1.45;
  static const double labelSize = 13;
  static const int labelWeight = 500;
  static const double labelTracking = 0.1;
  static const double labelHeight = 1.3;
  static const double captionSize = 12;
  static const int captionWeight = 400;
  static const double captionTracking = 0.1;
  static const double captionHeight = 1.3;
  static const double moneyLargeSize = 34;
  static const int moneyLargeWeight = 700;
  static const double moneyLargeTracking = -1.0;
  static const double moneyLargeHeight = 1.1;
  static const double moneyMediumSize = 19;
  static const int moneyMediumWeight = 600;
  static const double moneyMediumTracking = -0.3;
  static const double moneyMediumHeight = 1.2;
  static const double moneySmallSize = 15;
  static const int moneySmallWeight = 600;
  static const double moneySmallTracking = -0.1;
  static const double moneySmallHeight = 1.2;
}

abstract final class TokenSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double section = 40;
}

abstract final class TokenRadius {
  static const double control = 10;
  static const double field = 10;
  static const double card = 14;
  static const double sheet = 24;
  static const double button = 10;
  static const double thumbnail = 8;
  static const double pill = 999;
}

abstract final class TokenMotion {
  /// Curva M3 emphasized: cubic-bezier(x1, y1, x2, y2).
  static const List<double> easingEmphasized = [0.2, 0.0, 0.0, 1.0];
  static const int toggleMs = 120;
  static const int exitMs = 150;
  static const int enterMs = 220;
  static const int maxMs = 300;
  static const int listStaggerMs = 20;
  static const int skeletonShimmerMs = 1100;
  static const int syncIndicatorDelayMs = 400;
}

abstract final class TokenLayout {
  static const double screenMargin = 20;
  static const double minTouchTarget = 48;
  static const double thumbnailSize = 52;
  static const double hairline = 1;
  static const double maxContentWidth = 560;
}
