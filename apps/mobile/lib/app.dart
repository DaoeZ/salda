import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'l10n/generated/app_localizations.dart';

/// Raíz de la aplicación. El nombre visible procede del branding generado
/// (fuente única en packages/design_tokens) — nunca se hardcodea.
class SaldaApp extends ConsumerWidget {
  const SaldaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: Brand.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeControllerProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
      // Respeta "reducir movimiento" del sistema: con la opción activada,
      // Flutter desactiva por sí solo las animaciones implícitas de sus
      // transiciones. Aquí solo se garantiza que ninguna dure de más.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          // Se acota el escalado por arriba para que la tipografía siga
          // siendo legible sin romper las filas de importes; por abajo no
          // se toca, para no impedir un cuerpo menor.
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
