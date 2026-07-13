import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../sessions/application/add_ticket_controller.dart';
import '../../sessions/presentation/payer_picker.dart';
import '../../sessions/presentation/people_sheet.dart';
import '../application/review_draft.dart';
import 'line_edit_sheet.dart';

/// Pantalla de revisión del ticket (ESPECIFICACION.md §2.1 paso 3):
/// todo editable, validación de cuadre en vivo, banner con las tres
/// opciones en orden cuando hay dudas (DC-4: la IA siempre la última).
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reviewDraftProvider);
    final l10n = AppLocalizations.of(context);
    if (draft == null) {
      // Deep link sin estado: volver al inicio.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: ListView(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        children: [
          if (draft.needsAttention) _AttentionBanner(l10n: l10n),
          _HeaderCard(draft: draft),
          const SizedBox(height: TokenSpacing.lg),
          Text(l10n.reviewLines, style: theme.textTheme.titleMedium),
          const SizedBox(height: TokenSpacing.sm),
          for (var i = 0; i < draft.lines.length; i++)
            _LineTile(index: i, line: draft.lines[i]),
          TextButton.icon(
            onPressed: () => showLineEditSheet(context, ref, index: null),
            icon: const Icon(Icons.add),
            label: Text(l10n.reviewAddLine),
          ),
          const SizedBox(height: TokenSpacing.lg),
          _TotalsCard(draft: draft),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          child: FilledButton(
            onPressed: draft.lines.isEmpty
                ? null
                : () async {
                    final target = ref.read(addTicketTargetProvider);
                    if (target == null) {
                      // Flujo normal: crear sesión nueva.
                      await showPeopleSheet(context,
                          suggestedName: draft.merchantName);
                      return;
                    }
                    // Añadir a sesión existente: solo falta el pagador.
                    final payer =
                        await showPayerPicker(context, ref, target);
                    if (payer == null || !context.mounted) return;
                    final added = await ref
                        .read(addTicketControllerProvider.notifier)
                        .addToSession(target, payerPid: payer);
                    if (added && context.mounted) {
                      context.go('/session/$target');
                    }
                  },
            child: Text(l10n.commonContinue),
          ),
        ),
      ),
    );
  }
}

class _AttentionBanner extends ConsumerWidget {
  const _AttentionBanner({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: TokenSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.help_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: TokenSpacing.sm),
              Expanded(child: Text(l10n.reviewBannerLowConfidence)),
            ]),
            const SizedBox(height: TokenSpacing.sm),
            // Orden DC-4: ① repetir foto ② editar ③ IA (último recurso).
            Wrap(spacing: TokenSpacing.sm, children: [
              FilledButton.tonalIcon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(l10n.reviewRetake),
              ),
              FilledButton.tonalIcon(
                onPressed: () {}, // editar = esta misma pantalla
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.reviewEditManually),
              ),
              Tooltip(
                message: l10n.reviewAiUnavailable,
                child: FilledButton.tonalIcon(
                  onPressed: null, // se habilita en M6 con proveedor
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.reviewAnalyzeWithAi),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.draft});

  final ReviewDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(reviewDraftProvider.notifier);
    return Card(
      child: Column(children: [
        _EditableTile(
          icon: Icons.storefront_outlined,
          label: l10n.reviewMerchant,
          value: draft.merchantName ?? '—',
          onChanged: notifier.updateMerchant,
        ),
        _EditableTile(
          icon: Icons.event_outlined,
          label: l10n.reviewDate,
          value: draft.date ?? '—',
          onChanged: notifier.updateDate,
        ),
        _EditableTile(
          icon: Icons.schedule_outlined,
          label: l10n.reviewTime,
          value: draft.time ?? '—',
          onChanged: notifier.updateTime,
        ),
      ]),
    );
  }
}

class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(value),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final controller = TextEditingController(text: value == '—' ? '' : value);
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(label),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        );
        if (result != null && result.isNotEmpty) onChanged(result);
      },
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.index, required this.line});

  final int index;
  final DraftLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final quantity = line.quantityMilli == 1000
        ? null
        : line.quantityMilli % 1000 == 0
            ? '${line.quantityMilli ~/ 1000} ×'
            : '${(line.quantityMilli / 1000).toStringAsFixed(3)} kg';
    return Card(
      margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
      child: ListTile(
        title: Text(line.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: quantity == null && line.unitPrice == null
            ? null
            : Text([
                ?quantity,
                if (line.unitPrice != null) formatMoney(line.unitPrice!),
              ].join('  ·  ')),
        leading: line.lowConfidence
            ? Icon(Icons.warning_amber_outlined,
                color: scheme.settlementMarked)
            : null,
        trailing: Text(
          formatMoney(line.totalPrice),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        onTap: () => showLineEditSheet(context, ref, index: index),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.draft});

  final ReviewDraftState draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final delta = draft.delta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        child: Column(children: [
          _totalRow(context, l10n.reviewComputedTotal,
              formatMoney(draft.computedTotal)),
          if (draft.tip != null)
            _totalRow(context, l10n.reviewTip, formatMoney(draft.tip!)),
          for (final d in draft.discounts)
            _totalRow(context, d.label, '−${formatMoney(d.amount)}'),
          const Divider(),
          _totalRow(context, l10n.reviewGrandTotal,
              draft.grandTotal == null ? '—' : formatMoney(draft.grandTotal!),
              emphasized: true),
          const SizedBox(height: TokenSpacing.sm),
          Row(children: [
            Icon(
              draft.balanced ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: draft.balanced
                  ? scheme.settlementConfirmed
                  : scheme.error,
            ),
            const SizedBox(width: TokenSpacing.xs),
            Text(
              draft.balanced
                  ? l10n.reviewBalanced
                  : l10n.reviewMismatch(
                      delta == null ? '—' : formatMoney(delta.abs())),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, String amount,
      {bool emphasized = false}) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(amount,
              style: style
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
