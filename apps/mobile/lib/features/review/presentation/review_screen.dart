import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart' show Money;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../ai/application/ai_analysis_controller.dart';
import '../../ai/presentation/ai_providers_screen.dart' show aiErrorText;
import '../../sessions/application/add_ticket_controller.dart';
import '../../sessions/presentation/payer_picker.dart';
import '../../sessions/presentation/people_sheet.dart';
import '../application/review_draft.dart';
import 'line_edit_sheet.dart';

/// Pantalla de revisión del ticket (ESPECIFICACION.md §2.1 paso 3):
/// todo editable, validación de cuadre en vivo, banner con las tres
/// opciones en orden cuando hay dudas (DC-4: la IA siempre la última).
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// "Editar a mano" descarta el aviso: el usuario toma el control.
  bool _bannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reviewDraftProvider);
    final l10n = AppLocalizations.of(context);
    if (draft == null) {
      // Deep link sin estado: volver al inicio.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: ScreenBody(
        children: [
          if (draft.needsAttention && !_bannerDismissed)
            _AttentionBanner(
              l10n: l10n,
              onEditManually: () => setState(() => _bannerDismissed = true),
            ),
          _AmountHero(draft: draft),
          // A15: revisar con IA NO es un recurso de emergencia. Vivía dentro
          // del aviso de baja confianza, así que un ticket que cuadraba
          // —o pulsar «Editar a mano»— hacía desaparecer el botón justo
          // cuando el usuario sospechaba que algo estaba mal leído.
          const _AiReviewAction(),
          const SectionGap(),
          SectionHeader(title: l10n.reviewTicketData),
          _HeaderCard(draft: draft),
          const SectionGap(),
          SectionHeader(
            title: l10n.reviewLines,
            action: l10n.reviewAddLine,
            onAction: () => showLineEditSheet(context, ref, index: null),
          ),
          if (draft.lines.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.reviewNoLinesTitle,
              body: l10n.reviewNoLinesBody,
              action: l10n.reviewAddLine,
              onAction: () => showLineEditSheet(context, ref, index: null),
            )
          else
            SaldaCardList(
              children: [
                for (var i = 0; i < draft.lines.length; i++)
                  _LineTile(index: i, line: draft.lines[i]),
              ],
            ),
          const SectionGap(),
          SectionHeader(title: l10n.reviewTotalsTitle),
          _TotalsCard(draft: draft),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: context.salda.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TokenLayout.screenMargin,
              TokenSpacing.md,
              TokenLayout.screenMargin,
              TokenSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: draft.lines.isEmpty
                    ? null
                    : () async {
                        final target = ref.read(addTicketTargetProvider);
                        if (target == null) {
                          // Flujo normal: crear sesión nueva.
                          await showPeopleSheet(
                            context,
                            suggestedName: draft.merchantName,
                          );
                          return;
                        }
                        // Añadir a sesión existente: solo falta el pagador.
                        final payer = await showPayerPicker(
                          context,
                          ref,
                          target,
                        );
                        if (payer == null || !context.mounted) return;
                        final added = await ref
                            .read(addTicketControllerProvider.notifier)
                            .addToSession(target, payerPid: payer);
                        if (added && context.mounted) {
                          context.go('/home/session/$target');
                        }
                      },
                child: Text(l10n.commonContinue),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El importe, protagonista. Estaba al final de la pagina, detras de todas
/// las lineas: lo primero que hay que comprobar de un ticket es cuanto suma.
class _AmountHero extends StatelessWidget {
  const _AmountHero({required this.draft});

  final ReviewDraftState draft;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final delta = draft.delta;
    final total = draft.grandTotal;
    return SaldaCard(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reviewGrandTotal.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: c.textMuted,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: TokenSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: total == null
                ? Text('—', style: theme.textTheme.displayMedium)
                : MoneyText(total, size: MoneySize.large),
          ),
          const SizedBox(height: TokenSpacing.md),
          // El cuadre no depende solo del color: lleva icono y frase.
          StatusBadge(
            draft.balanced
                ? l10n.reviewBalanced
                : l10n.reviewMismatch(
                    delta == null ? '—' : formatMoney(delta.abs()),
                  ),
            tone: draft.balanced ? BadgeTone.positive : BadgeTone.warning,
            icon: draft.balanced
                ? Icons.check_rounded
                : Icons.error_outline_rounded,
          ),
          // El verde solo certifica ARITMÉTICA. Un ticket puede cuadrar al
          // céntimo con el establecimiento mal leído, un producto inventado
          // o una cantidad equivocada — se midió con tickets reales.
          if (draft.balanced) ...[
            const SizedBox(height: TokenSpacing.xs),
            Text(
              l10n.reviewBalancedHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionBanner extends ConsumerWidget {
  const _AttentionBanner({required this.l10n, required this.onEditManually});

  final AppLocalizations l10n;
  final VoidCallback onEditManually;

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
            Row(
              children: [
                Icon(Icons.help_outline, color: scheme.onSecondaryContainer),
                const SizedBox(width: TokenSpacing.sm),
                Expanded(child: Text(l10n.reviewBannerLowConfidence)),
              ],
            ),
            const SizedBox(height: TokenSpacing.sm),
            // Orden DC-4: ① repetir foto ② editar ③ IA (último recurso).
            Wrap(
              spacing: TokenSpacing.sm,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(l10n.reviewRetake),
                ),
                FilledButton.tonalIcon(
                  onPressed: onEditManually, // descarta el aviso (bug 3 MVP)
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.reviewEditManually),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Revisar con IA: acción CONSCIENTE y siempre disponible (DC-13 sigue
/// vigente en lo que importa —nunca se lanza sola—, pero deja de esconderse
/// cuando las cuentas salen: que un ticket cuadre no dice nada de si está
/// bien leído).
class _AiReviewAction extends ConsumerWidget {
  const _AiReviewAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(aiAvailableProvider).value ?? false;
    final analyzingWith = ref.watch(aiAnalysisControllerProvider).value;
    final draft = ref.watch(reviewDraftProvider);
    // Sin la foto original la IA revisa el texto ya extraído: es una
    // revisión distinta y peor, y se dice en vez de disimularlo.
    final withoutPhoto = ref.watch(lastScanImageProvider) == null;

    return Padding(
      padding: const EdgeInsets.only(top: TokenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: available ? '' : l10n.reviewAiUnavailable,
            child: FilledButton.tonalIcon(
              onPressed: !available || analyzingWith != null
                  ? null
                  : () => _run(context, ref, l10n, draft),
              icon: analyzingWith != null
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                analyzingWith != null
                    ? l10n.aiAnalyzing(analyzingWith)
                    : l10n.reviewAnalyzeWithAi,
              ),
            ),
          ),
          if (available && withoutPhoto) ...[
            const SizedBox(height: TokenSpacing.xs),
            Text(
              l10n.reviewAiWithoutPhoto,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ReviewDraftState? draft,
  ) async {
    // La IA devuelve el ticket ENTERO y sustituye el borrador: no hay merge
    // ni lo va a haber (un diff de líneas sin identidad estable sería
    // adivinar). Lo que sí puede hacerse es no perder trabajo en silencio.
    if (draft?.manuallyEdited ?? false) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.reviewAiOverwriteTitle),
          content: Text(l10n.reviewAiOverwriteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.reviewAiOverwriteConfirm),
            ),
          ],
        ),
      );
      if (seguir != true || !context.mounted) return;
    }

    final result = await ref
        .read(aiAnalysisControllerProvider.notifier)
        .analyze();
    if (!context.mounted) return;
    if (!result.ok && result.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(aiErrorText(l10n, result.error!))));
    }
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.draft});

  final ReviewDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(reviewDraftProvider.notifier);
    return SaldaCardList(
      children: [
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
      ],
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
        final controller = TextEditingController(
          text: value == '—' ? '' : value,
        );
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
            : Text(
                [
                  ?quantity,
                  if (line.unitPrice != null) formatMoney(line.unitPrice!),
                ].join('  ·  '),
              ),
        leading: line.lowConfidence
            ? Icon(Icons.warning_amber_outlined, color: scheme.settlementMarked)
            : null,
        trailing: Text(
          formatMoney(line.totalPrice),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        onTap: () => showLineEditSheet(context, ref, index: index),
      ),
    );
  }
}

class _TotalsCard extends ConsumerWidget {
  const _TotalsCard({required this.draft});

  final ReviewDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      child: Column(
        children: [
          _totalRow(
            context,
            l10n.reviewComputedTotal,
            formatMoney(draft.computedTotal),
          ),
          if (draft.tip != null)
            _totalRow(context, l10n.reviewTip, formatMoney(draft.tip!)),
          for (final d in draft.discounts)
            _totalRow(context, d.label, '−${formatMoney(d.amount)}'),
          const Divider(),
          // El TOTAL es lo único que no se podía corregir antes de guardar,
          // y es el dato que manda: el reparto se hace sobre él. A11c ya
          // permite corregirlo DESPUÉS; no tenía sentido que fuese imposible
          // antes. Cambiarlo no toca los productos: no se inventa ninguna
          // línea de ajuste para hacer que cuadre.
          _totalRow(
            context,
            l10n.reviewGrandTotal,
            draft.grandTotal == null ? '—' : formatMoney(draft.grandTotal!),
            emphasized: true,
            onEdit: () => _editTotal(context, ref, l10n),
          ),
        ],
      ),
    );
  }

  Future<void> _editTotal(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final controller = TextEditingController(
      text: draft.grandTotal == null
          ? ''
          : formatMoney(draft.grandTotal!).replaceAll(' €', ''),
    );
    final result = await showDialog<Money>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.reviewEditTotalTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: '€'),
            ),
            const SizedBox(height: TokenSpacing.sm),
            Text(
              l10n.reviewEditTotalHint,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = parseUserMoney(controller.text);
              if (parsed == null || parsed.cents < 0) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (result != null) {
      ref.read(reviewDraftProvider.notifier).updateGrandTotal(result);
    }
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    String amount, {
    bool emphasized = false,
    VoidCallback? onEdit,
  }) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyMedium;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
          Text(
            amount,
            style: style?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: TokenSpacing.sm),
            const Icon(Icons.edit_outlined, size: 18),
          ],
        ],
      ),
    );
    if (onEdit == null) return row;
    return InkWell(onTap: onEdit, child: row);
  }
}
