import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../ai/application/ai_analysis_controller.dart';
import '../../review/application/review_draft.dart';
import '../../sessions/application/add_ticket_controller.dart';
import '../application/manual_expense.dart';
import '../application/scan_service.dart';

/// Punto de entrada único del escaneo (Home y detalle de sesión):
/// cámara / galería / gasto manual → draft → /review.
/// Con [targetSessionId], la revisión añadirá el ticket a esa sesión
/// en lugar de crear una nueva.
Future<void> showScanEntrySheet(
  BuildContext context,
  WidgetRef ref, {
  String? targetSessionId,
  ValueChanged<bool>? onBusy,
}) {
  final l10n = AppLocalizations.of(context);
  // Fija (o limpia) el destino ANTES de entrar al flujo.
  ref.read(addTicketTargetProvider.notifier).set(targetSessionId);

  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.scanFromCamera),
            onTap: () {
              Navigator.pop(sheetContext);
              _scanToReview(context, ref, ImageSource.camera, onBusy);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.scanFromGallery),
            onTap: () {
              Navigator.pop(sheetContext);
              _scanToReview(context, ref, ImageSource.gallery, onBusy);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: Text(l10n.scanManualEntry),
            onTap: () {
              Navigator.pop(sheetContext);
              _manualToReview(context, ref);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _scanToReview(
  BuildContext context,
  WidgetRef ref,
  ImageSource source,
  ValueChanged<bool>? onBusy,
) async {
  final l10n = AppLocalizations.of(context);
  onBusy?.call(true);
  try {
    final result = await ref.read(scanServiceProvider).scanFrom(source);
    if (!context.mounted || result == null) return;
    if (result.extraction.lines.isEmpty &&
        !result.extraction.grandTotal.isPresent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.scanNothingRecognized)));
    }
    ref.read(lastScanImageProvider.notifier).set(result.imagePath);
    ref.read(reviewDraftProvider.notifier).loadFrom(result.extraction);
    context.push('/home/review');
  } finally {
    onBusy?.call(false);
  }
}

Future<void> _manualToReview(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final concept = TextEditingController();
  final amount = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.manualTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: concept,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.manualConcept,
              hintText: l10n.manualConceptHint,
            ),
          ),
          const SizedBox(height: TokenSpacing.md),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.manualAmount,
              suffixText: '€',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.commonContinue),
        ),
      ],
    ),
  );
  final money = parseUserMoney(amount.text);
  if (confirmed != true || concept.text.trim().isEmpty || money == null) {
    return;
  }
  if (!context.mounted) return;
  ref.read(lastScanImageProvider.notifier).set(null); // no hay foto
  ref
      .read(reviewDraftProvider.notifier)
      .loadFrom(
        manualExpenseExtraction(
          concept: concept.text.trim(),
          amount: money,
          date: DateTime.now(),
        ),
      );
  context.push('/home/review');
}
