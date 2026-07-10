import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/generated/app_localizations.dart';
import '../review/application/review_draft.dart';
import '../scan/application/scan_service.dart';

/// Placeholder del historial de sesiones (M3) con el flujo de escaneo
/// ya operativo: FAB → cámara/galería → OCR → parser → revisión.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _scanning = false;

  Future<void> _scan(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _scanning = true);
    try {
      final extraction =
          await ref.read(scanServiceProvider).scanFrom(source);
      if (!mounted || extraction == null) return;
      if (extraction.lines.isEmpty && !extraction.grandTotal.isPresent) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.scanNothingRecognized)));
      }
      ref.read(reviewDraftProvider.notifier).loadFrom(extraction);
      context.push('/review');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _showSourceSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.scanFromCamera),
            onTap: () {
              Navigator.pop(context);
              _scan(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.scanFromGallery),
            onTap: () {
              Navigator.pop(context);
              _scan(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(Brand.appName),
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
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
                l10n.homeTagline,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TokenSpacing.sm),
              Text(l10n.homeEmptyHint, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _showSourceSheet,
        icon: const Icon(Icons.document_scanner_outlined),
        label: Text(l10n.scanFab),
      ),
    );
  }
}
