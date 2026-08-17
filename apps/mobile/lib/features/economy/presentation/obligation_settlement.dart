import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../sessions/presentation/ticket_navigation.dart';
import '../../spaces/data/spaces_repository.dart';
import '../data/economic_repository.dart';
import '../domain/economic_models.dart';
import 'economic_names.dart';

/// Gestión de las deudas que EXPLICAN un saldo (ADR-038).
///
/// El saldo agregado —«Test te debe 14,73»— es un resumen y nunca se
/// convierte en una obligación nueva: aquí se cobra cada deuda contra su
/// ticket. Marcar varias es comodidad de la interfaz; económicamente salen N
/// liquidaciones independientes, cada una con su origen.
///
/// Esta hoja es el ÚNICO sitio donde se confirma un cobro, y por eso todas
/// las superficies que enseñan un saldo accionable llegan a ella: Economía,
/// la portada de una relación o de un grupo, y «Balance con X».
/// [spaceId] acota la gestión a un contexto: además de lo propio incluye lo
/// de las identidades sin cuenta que ese espacio permite representar.
///
/// La pareja va EXPLÍCITA porque quien mira no siempre es el acreedor: al
/// representar a alguien sin cuenta se cobra por él, y dar por hecho que el
/// acreedor es uno mismo pintaba esas deudas como propias.
Future<void> openObligationSettlement(
  BuildContext context, {
  required String debtorActor,
  required String creditorActor,
  String? currency,
  String? spaceId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ObligationSettlementSheet(
    debtorActor: debtorActor,
    creditorActor: creditorActor,
    currency: currency,
    spaceId: spaceId,
  ),
);

/// ¿Puede quien mira confirmar un cobro dirigido a [creditorActor]?
///
/// Espejo en la interfaz del predicado autoritativo de `packages/domain`: el
/// receptor manda, y solo se representa a quien NO tiene cuenta. Las Rules y
/// la Function lo vuelven a comprobar — esto solo evita ofrecer un botón que
/// terminaría en «no autorizado».
bool canViewerConfirmReceipt(
  WidgetRef ref, {
  required String creditorActor,
  String? spaceId,
}) {
  final viewerUid = ref.watch(currentAppUserProvider)?.uid ?? '';
  final manualId = manualIdOf(creditorActor);
  final linkedUid = manualId == null || spaceId == null
      ? null
      : ref
            .watch(spaceManualParticipantsProvider(spaceId))
            .value
            ?.where((manual) => manual.id == manualId)
            .firstOrNull
            ?.linkedUid;
  return canConfirmReceipt(
    creditorActor: creditorActor,
    viewerUid: viewerUid,
    viewerIsSpaceAdmin:
        spaceId != null && ref.watch(iAdministerSpaceProvider(spaceId)),
    linkedUid: linkedUid,
  );
}

class _ObligationSettlementSheet extends ConsumerStatefulWidget {
  const _ObligationSettlementSheet({
    required this.debtorActor,
    required this.creditorActor,
    this.currency,
    this.spaceId,
  });

  final String debtorActor;
  final String creditorActor;
  final String? currency;
  final String? spaceId;

  @override
  ConsumerState<_ObligationSettlementSheet> createState() =>
      _ObligationSettlementSheetState();
}

class _ObligationSettlementSheetState
    extends ConsumerState<_ObligationSettlementSheet> {
  final selected = <String>{};
  var busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final debtorName = economicNameText(ref, l10n, widget.debtorActor);
    final creditorName = economicNameText(ref, l10n, widget.creditorActor);
    final representing = isManualActor(widget.creditorActor);
    // Se lee del stream, no de una foto: confirmar una deuda hace
    // desaparecer su fila sin cerrar la hoja, y una confirmación hecha desde
    // otro dispositivo llega igual.
    final overview = widget.spaceId == null
        ? ref.watch(participantEconomicOverviewProvider).value
        : ref
              .watch(spaceManageableEconomicOverviewProvider(widget.spaceId!))
              .value;
    if (overview == null) {
      return const Padding(
        padding: EdgeInsets.all(TokenSpacing.xl),
        child: SkeletonList(rows: 3, leading: false),
      );
    }
    final obligations = overview.openObligations(
      debtorActor: widget.debtorActor,
      creditorActor: widget.creditorActor,
      currency: widget.currency,
    );
    selected.removeWhere(
      (id) => !obligations.any((obligation) => obligation.id == id),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TokenSpacing.lg,
          0,
          TokenSpacing.lg,
          TokenSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.economySettleTitle(debtorName),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TokenSpacing.xs),
            Text(
              l10n.economySettleHint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.salda.textMuted),
            ),
            // Cobrar POR otra persona se dice: sin esto, la deuda de alguien
            // sin cuenta parecería propia.
            if (representing) ...[
              const SizedBox(height: TokenSpacing.sm),
              StatusBadge(l10n.economyRepresentingNotice(creditorName)),
            ],
            const SizedBox(height: TokenSpacing.md),
            if (obligations.isEmpty)
              EmptyState(
                icon: Icons.check_rounded,
                title: l10n.economyNoOpenObligations,
                body: l10n.economyEmptyBody,
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final obligation in obligations)
                      _ObligationRow(
                        obligation: obligation,
                        checked: selected.contains(obligation.id),
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                if (value) {
                                  selected.add(obligation.id);
                                } else {
                                  selected.remove(obligation.id);
                                }
                              }),
                        onPartial: busy
                            ? null
                            : () => _registerPartial(obligation),
                      ),
                  ],
                ),
              ),
            if (obligations.isNotEmpty) ...[
              const SizedBox(height: TokenSpacing.md),
              FilledButton(
                onPressed: busy || selected.isEmpty ? null : _confirmSelected,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.economySettleSelected(selected.length)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSelected() =>
      _run([for (final id in selected) EntrySettlementRequest(id)]);

  Future<void> _registerPartial(EconomicObligationView obligation) async {
    final l10n = AppLocalizations.of(context);
    // El camino normal NO pide importe: solo el parcial, que es la excepción
    // y pertenece a ESTA deuda, no al saldo global.
    var input = formatMoney(obligation.remaining);
    final amount = await showDialog<Money>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.economyPartialPayment),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              obligation.entry.ticketName,
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: TokenSpacing.sm),
            TextFormField(
              initialValue: input,
              onChanged: (value) => input = value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.economyPartialAmount,
                suffixText: obligation.entry.currency,
              ),
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
              final parsed = parseUserMoney(input);
              if (parsed == null ||
                  parsed.cents <= 0 ||
                  parsed.cents > obligation.remaining.cents) {
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: Text(l10n.economyConfirmPayment),
          ),
        ],
      ),
    );
    if (amount == null) return;
    await _run([EntrySettlementRequest(obligation.id, amount: amount)]);
  }

  Future<void> _run(List<EntrySettlementRequest> requests) async {
    if (requests.isEmpty) return;
    setState(() => busy = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(economicRepositoryProvider).settleEntries(requests);
      if (!mounted) return;
      setState(selected.clear);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.economySettleSuccess)),
      );
    } on Object catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(economicErrorText(l10n, error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _ObligationRow extends StatelessWidget {
  const _ObligationRow({
    required this.obligation,
    required this.checked,
    required this.onChanged,
    required this.onPartial,
  });

  final EconomicObligationView obligation;
  final bool checked;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onPartial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entry = obligation.entry;
    return CheckboxListTile(
      value: checked,
      onChanged: onChanged == null
          ? null
          : (value) => onChanged!(value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        entry.ticketName.isEmpty ? l10n.spaceTicketUntitled : entry.ticketName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.ticketDate != null) Text(entry.ticketDate!),
          // Una declaración del pagador es un AVISO, no un requisito: sin
          // ella la deuda se confirma igual.
          if (obligation.declaration != null)
            StatusBadge(l10n.economyDeclaredByPayer, tone: BadgeTone.pending),
        ],
      ),
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(
            obligation.remaining,
            size: MoneySize.small,
            currency: entry.currency,
            tone: MoneyTone.positive,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'partial') onPartial?.call();
              if (value == 'ticket') {
                openTicket(
                  context,
                  sessionId: entry.sessionId,
                  ticketId: entry.ticketId,
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'partial',
                enabled: onPartial != null,
                child: Text(l10n.economyPartialPayment),
              ),
              PopupMenuItem(
                value: 'ticket',
                child: Text(l10n.economyOpenDetail),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String economicErrorText(AppLocalizations l10n, Object error) {
  if (error is! EconomicFailure) return l10n.economyPaymentErrorUnexpected;
  return switch (error.code) {
    EconomicFailureCode.exceedsBalance ||
    EconomicFailureCode.invalidAmount => l10n.economyPaymentErrorOver,
    EconomicFailureCode.notAllowed ||
    EconomicFailureCode.accountRequired => l10n.economyPaymentErrorPermission,
    EconomicFailureCode.network ||
    EconomicFailureCode.serviceUnavailable => l10n.economyPaymentErrorNetwork,
    EconomicFailureCode.alreadyResolved ||
    EconomicFailureCode.unexpected => l10n.economyPaymentErrorUnexpected,
  };
}
