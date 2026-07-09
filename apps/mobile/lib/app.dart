import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import 'core/routing/router.dart';
import 'core/theme/app_theme.dart';

/// Raíz de la aplicación. El nombre visible procede del branding generado
/// (fuente única en packages/design_tokens) — nunca se hardcodea.
class SaldaApp extends StatelessWidget {
  const SaldaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: Brand.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system, // selector manual en Ajustes (M5)
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
