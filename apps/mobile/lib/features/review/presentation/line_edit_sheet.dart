import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/review_draft.dart';

/// Hoja de edición de una línea. Con `index == null` crea una nueva.
/// Muestra el texto OCR original y las interpretaciones alternativas
/// (un toque las aplica) para que corregir sea rapidísimo.
Future<void> showLineEditSheet(
  BuildContext context,
  WidgetRef ref, {
  required int? index,
}) {
  final draft = ref.read(reviewDraftProvider);
  final line = index == null ? null : draft?.lines[index];
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _LineEditForm(index: index, line: line, ref: ref),
    ),
  );
}

class _LineEditForm extends StatefulWidget {
  const _LineEditForm({
    required this.index,
    required this.line,
    required this.ref,
  });

  final int? index;
  final DraftLine? line;
  final WidgetRef ref;

  @override
  State<_LineEditForm> createState() => _LineEditFormState();
}

class _LineEditFormState extends State<_LineEditForm> {
  late final _name = TextEditingController(text: widget.line?.name ?? '');
  late final _quantity = TextEditingController(
    text: widget.line == null
        ? '1'
        : (widget.line!.quantityMilli / 1000)
              .toStringAsFixed(widget.line!.quantityMilli % 1000 == 0 ? 0 : 3)
              .replaceAll('.', ','),
  );
  late final _unit = TextEditingController(
    text: widget.line?.unitPrice == null
        ? ''
        : formatMoney(widget.line!.unitPrice!).replaceAll(' €', ''),
  );
  late final _total = TextEditingController(
    text: widget.line == null
        ? ''
        : formatMoney(widget.line!.totalPrice).replaceAll(' €', ''),
  );

  @override
  void dispose() {
    for (final c in [_name, _quantity, _unit, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final total = parseUserMoney(_total.text);
    if (_name.text.trim().isEmpty || total == null) return;
    final quantity = double.tryParse(_quantity.text.replaceAll(',', '.'));
    final quantityMilli = quantity == null ? 1000 : (quantity * 1000).round();
    final line = DraftLine(
      name: _name.text.trim(),
      quantityMilli: quantityMilli,
      unitPrice: unitPriceAfterEdit(
        widget.line,
        quantityMilli: quantityMilli,
        total: total,
        typed: parseUserMoney(_unit.text),
      ),
      totalPrice: total,
      sourceText: widget.line?.sourceText ?? '',
    );
    final notifier = widget.ref.read(reviewDraftProvider.notifier);
    if (widget.index == null) {
      notifier.addLine(line);
    } else {
      notifier.updateLine(widget.index!, line);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final line = widget.line;
    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.lineEditTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: TokenSpacing.lg),
          TextField(
            controller: _name,
            autofocus: line == null,
            decoration: InputDecoration(labelText: l10n.lineName),
          ),
          const SizedBox(height: TokenSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.lineQuantity),
                ),
              ),
              const SizedBox(width: TokenSpacing.md),
              Expanded(
                child: TextField(
                  controller: _unit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.lineUnitPrice,
                    suffixText: '€',
                  ),
                ),
              ),
              const SizedBox(width: TokenSpacing.md),
              Expanded(
                child: TextField(
                  controller: _total,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.lineTotalPrice,
                    suffixText: '€',
                  ),
                ),
              ),
            ],
          ),
          if (line != null && line.alternatives.isNotEmpty) ...[
            const SizedBox(height: TokenSpacing.md),
            Text(
              l10n.lineAlternatives,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Wrap(
              spacing: TokenSpacing.sm,
              children: [
                for (final alt in line.alternatives)
                  ActionChip(
                    label: Text('${alt.name} · ${formatMoney(alt.totalPrice)}'),
                    onPressed: () {
                      widget.ref
                          .read(reviewDraftProvider.notifier)
                          .updateLine(
                            widget.index!,
                            DraftLine(
                              name: alt.name,
                              quantityMilli: alt.quantityMilli,
                              unitPrice: alt.unitPrice,
                              totalPrice: alt.totalPrice,
                            ),
                          );
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ],
          if (line != null && line.sourceText.isNotEmpty) ...[
            const SizedBox(height: TokenSpacing.sm),
            Text(
              l10n.lineSource(line.sourceText),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: TokenSpacing.lg),
          Row(
            children: [
              if (widget.index != null)
                TextButton.icon(
                  onPressed: () {
                    widget.ref
                        .read(reviewDraftProvider.notifier)
                        .removeLine(widget.index!);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.lineDelete),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: TokenSpacing.sm),
              FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
            ],
          ),
          const SizedBox(height: TokenSpacing.sm),
        ],
      ),
    );
  }
}
