import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// Placeholder del historial de sesiones (M3). Verifica que el tema M3,
/// los tokens y el branding fluyen correctamente por toda la app.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(Brand.appName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: TokenSpacing.lg),
              Text(
                Brand.tagline,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TokenSpacing.sm),
              Text(
                'Cimientos listos (M0). El historial llega en M3.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null, // cámara directa en M2 (§2.1)
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Escanear'),
      ),
    );
  }
}
