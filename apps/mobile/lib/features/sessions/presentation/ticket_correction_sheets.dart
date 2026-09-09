import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';
import '../domain/ticket_correction.dart';

/// Corregir un gasto ya registrado (A11c): el creador y quien administra el
/// grupo usan ESTA misma superficie. No hay pantalla administrativa aparte —
/// corregir un precio mal leído es lo mismo lo firme quien lo firme.
///
/// La hoja no calcula dinero: escribe el contenido y deja que la function
/// autoritativa rehaga obligaciones y balances. Los pagos ya registrados no
/// se tocan: son hechos, no consecuencias del gasto.
Future<void> showTicketHeaderCorrection(
  BuildContext context,
  WidgetRef ref, {
  required String ticketPath,
  required String merchantName,
  required String? date,
  required Money grandTotal,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
    ),
    child: _HeaderForm(
      ref: ref,
      ticketPath: ticketPath,
      merchantName: merchantName,
      date: date,
      grandTotal: grandTotal,
    ),
  ),
);

class _HeaderForm extends StatefulWidget {
  const _HeaderForm({
    required this.ref,
    required this.ticketPath,
    required this.merchantName,
    required this.date,
    required this.grandTotal,
  });

  final WidgetRef ref;
  final String ticketPath;
  final String merchantName;
  final String? date;
  final Money grandTotal;

  @override
  State<_HeaderForm> createState() => _HeaderFormState();
}

class _HeaderFormState extends State<_HeaderForm> {
  late final _merchant = TextEditingController(text: widget.merchantName);
  late final _date = TextEditingController(text: widget.date ?? '');
  late final _total = TextEditingController(
    text: formatMoney(widget.grandTotal).replaceAll(' €', ''),
  );

  @override
  void dispose() {
    for (final c in [_merchant, _date, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final total = parseUserMoney(_total.text);
    if (_merchant.text.trim().isEmpty || total == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await widget.ref
          .read(sessionRepositoryProvider)
          .correctTicketHeader(
            widget.ticketPath,
            merchantName: _merchant.text.trim(),
            date: _date.text.trim().isEmpty ? null : _date.text.trim(),
            grandTotal: total,
          );
      navigator.pop();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketCorrectError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.ticketCorrectHeaderTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: TokenSpacing.lg),
          TextField(
            controller: _merchant,
            decoration: InputDecoration(labelText: l10n.reviewMerchant),
          ),
          const SizedBox(height: TokenSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _date,
                  decoration: InputDecoration(labelText: l10n.reviewDate),
                ),
              ),
              const SizedBox(width: TokenSpacing.md),
              Expanded(
                child: TextField(
                  controller: _total,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.reviewGrandTotal,
                    suffixText: '€',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TokenSpacing.lg),
          Row(
            children: [
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

/// Corregir un producto del ticket. Reducir la cantidad o retirarlo puede
/// destruir consumo ajeno: eso NUNCA ocurre en silencio — se dice quién lo
/// pierde y hace falta confirmarlo.
Future<void> showLineCorrection(
  BuildContext context,
  WidgetRef ref, {
  required TicketLine line,
  required Map<String, String> names,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
    ),
    child: _LineForm(ref: ref, line: line, names: names),
  ),
);

class _LineForm extends StatefulWidget {
  const _LineForm({
    required this.ref,
    required this.line,
    required this.names,
  });

  final WidgetRef ref;
  final TicketLine line;
  final Map<String, String> names;

  @override
  State<_LineForm> createState() => _LineFormState();
}

class _LineFormState extends State<_LineForm> {
  late final _name = TextEditingController(text: widget.line.name);
  late final _quantity = TextEditingController(
    text: (widget.line.quantityMilli / 1000)
        .toStringAsFixed(widget.line.quantityMilli % 1000 == 0 ? 0 : 3)
        .replaceAll('.', ','),
  );
  late final _total = TextEditingController(
    text: formatMoney(widget.line.totalPrice).replaceAll(' €', ''),
  );

  @override
  void dispose() {
    for (final c in [_name, _quantity, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Nombres legibles de quienes pierden consumo. Sin esto la advertencia
  /// sería un aviso genérico y nadie sabría a quién está afectando.
  String _affected(CorrectionImpact impact) => impact.affectedPids
      .map((pid) => widget.names[pid] ?? pid)
      .join(', ');

  Future<bool> _confirm(CorrectionImpact impact, String action) async {
    if (!impact.isDestructive) return true;
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.ticketCorrectImpactTitle),
            content: Text(l10n.ticketCorrectImpactBody(_affected(impact))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    final total = parseUserMoney(_total.text);
    final quantity = double.tryParse(_quantity.text.replaceAll(',', '.'));
    if (_name.text.trim().isEmpty || total == null || quantity == null) return;
    final quantityMilli = (quantity * 1000).round();
    if (quantityMilli <= 0) return;

    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final line = widget.line;
    final impact = impactOfQuantityChange(line, quantityMilli);
    if (!await _confirm(impact, l10n.commonSave)) return;
    if (!mounted) return;

    // El reparto solo se toca cuando de verdad desaparecen unidades: una
    // corrección de precio o de nombre lo deja intacto.
    try {
      await widget.ref
          .read(sessionRepositoryProvider)
          .correctLine(
            line.path,
            name: _name.text.trim(),
            quantityMilli: quantityMilli,
            totalPrice: total,
            removedUnitIds: line.usesUnitModel
                ? impact.removedUnitIds
                : const [],
            unitIds: line.usesUnitModel ? unitIdsFor(quantityMilli) : null,
          );
      navigator.pop();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketCorrectError)));
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(impactOfRemovingLine(widget.line), l10n.lineDelete)) {
      return;
    }
    if (!mounted) return;
    try {
      await widget.ref
          .read(sessionRepositoryProvider)
          .removeLine(widget.line.path);
      navigator.pop();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketCorrectError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          const SizedBox(height: TokenSpacing.lg),
          Row(
            children: [
              TextButton.icon(
                onPressed: _remove,
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
