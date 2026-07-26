import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../sessions/presentation/ticket_navigation.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../data/economic_repository.dart';
import '../domain/economic_models.dart';

class EconomicRelationScreen extends ConsumerWidget {
  const EconomicRelationScreen({required this.otherUid, super.key});

  final String otherUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(publicProfileProvider(otherUid)).value;
    final name = profile?.displayName ?? _shortUid(otherUid);
    final overview = ref.watch(economicOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.economyDetailTitle(name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: overview.when(
        loading: () => const ScreenBody(children: [SkeletonList(rows: 4)]),
        error: (_, _) => ScreenBody(
          children: [ErrorStateView(message: l10n.economyLoadError)],
        ),
        data: (data) =>
            _RelationBody(overview: data, otherUid: otherUid, otherName: name),
      ),
    );
  }
}

class _RelationBody extends ConsumerWidget {
  const _RelationBody({
    required this.overview,
    required this.otherUid,
    required this.otherName,
  });

  final EconomicOverview overview;
  final String otherUid;
  final String otherName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final balances = overview.withUser(otherUid);
    final entries = overview.entriesWith(otherUid)
      ..sort((a, b) => _millis(b.createdAt).compareTo(_millis(a.createdAt)));
    final payments = overview.paymentsWith(otherUid)
      ..sort((a, b) => _millis(b.createdAt).compareTo(_millis(a.createdAt)));
    if (balances.isEmpty && entries.isEmpty && payments.isEmpty) {
      return ScreenBody(
        children: [
          EmptyState(
            icon: Icons.check_rounded,
            title: l10n.economySettledWith(otherName),
            body: l10n.economyEmptyBody,
          ),
        ],
      );
    }
    return ScreenBody(
      children: [
        // La persona encabeza la pantalla en una fila, no un avatar suelto
        // centrado que no dice de quien es la deuda.
        Row(
          children: [
            SaldaAvatar(seed: otherUid, label: otherName, radius: 22),
            const SizedBox(width: TokenSpacing.lg),
            Expanded(
              child: Text(
                otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ],
        ),
        const SectionGap(height: TokenSpacing.lg),
        for (final balance in balances)
          _BalanceCard(
            balance: balance,
            viewerUid: overview.viewerUid,
            otherUid: otherUid,
            otherName: otherName,
          ),
        const SectionGap(),
        SectionHeader(title: l10n.economyTicketsTitle),
        if (entries.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: l10n.emptyTicketsTitle,
            body: l10n.economyEmptyBody,
          )
        else
          SaldaCardList(
            children: [
              for (final entry in entries)
                _EntryTile(
                  entry: entry,
                  viewerUid: overview.viewerUid,
                  otherName: otherName,
                ),
            ],
          ),
        const SectionGap(),
        SectionHeader(title: l10n.economyPaymentsTitle),
        if (payments.isEmpty)
          EmptyState(
            icon: Icons.payments_outlined,
            title: l10n.economyPaymentPending,
            body: l10n.economyNoPaymentsBody,
          )
        else
          SaldaCardList(
            children: [
              for (final payment in payments)
                _PaymentTile(payment: payment, viewerUid: overview.viewerUid),
            ],
          ),
      ],
    );
  }
}

class _BalanceCard extends ConsumerStatefulWidget {
  const _BalanceCard({
    required this.balance,
    required this.viewerUid,
    required this.otherUid,
    required this.otherName,
  });

  final BilateralEconomicBalance balance;
  final String viewerUid;
  final String otherUid;
  final String otherName;

  @override
  ConsumerState<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends ConsumerState<_BalanceCard> {
  var busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final balance = widget.balance;
    final iOwe = balance.debtorUid == widget.viewerUid;
    final title = balance.debtorUid == null
        ? l10n.economySettledWith(widget.otherName)
        : iOwe
        ? l10n.economyYouOwe(widget.otherName)
        : l10n.economyOwesYou(widget.otherName);
    final c = context.salda;
    final settled = balance.outstanding.cents == 0;
    return SaldaCard(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              StatusBadge(
                settled
                    ? l10n.economySettledBadge
                    : iOwe
                    ? l10n.balanceNetNegative
                    : l10n.balanceNetPositive,
                tone: settled
                    ? BadgeTone.neutral
                    : iOwe
                    ? BadgeTone.negative
                    : BadgeTone.positive,
              ),
            ],
          ),
          const SizedBox(height: TokenSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              balance.outstanding,
              size: MoneySize.large,
              currency: balance.currency,
              tone: settled
                  ? MoneyTone.muted
                  : iOwe
                  ? MoneyTone.negative
                  : MoneyTone.positive,
            ),
          ),
          const SizedBox(height: TokenSpacing.sm),
          Text(
            '${l10n.economyOriginalDebt}: '
            '${formatCurrencyMoney(_originalForViewer(balance), balance.currency)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
          if (iOwe && balance.outstanding.cents > 0) ...[
            const SizedBox(height: TokenSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _markPaid,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(l10n.economyMarkPaid),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Money _originalForViewer(BilateralEconomicBalance balance) =>
      widget.viewerUid == balance.firstUid
      ? balance.originalFirstToSecond
      : balance.originalSecondToFirst;

  Future<void> _markPaid() async {
    final l10n = AppLocalizations.of(context);
    var input = (widget.balance.outstanding.cents / 100)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    final amount = await showDialog<Money>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.economyMarkPaid),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.economyPaymentAmount,
            suffixText: widget.balance.currency,
          ),
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
                  parsed.cents > widget.balance.outstanding.cents) {
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: Text(l10n.commonContinue),
          ),
        ],
      ),
    );
    if (amount == null || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(economicRepositoryProvider)
          .markPaid(
            receiverUid: widget.otherUid,
            amount: amount,
            currency: widget.balance.currency,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.economyPaymentSuccess)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_economicErrorText(l10n, error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.viewerUid,
    required this.otherName,
  });

  final EconomicEntryView entry;
  final String viewerUid;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewerOwes = entry.debtorUid == viewerUid;
    return ListTile(
      // La fila describe UN ticket: llevaba a la sesión entera, donde
      // había que volver a buscarlo.
      onTap: () => openTicket(
        context,
        sessionId: entry.sessionId,
        ticketId: entry.ticketId,
      ),
      title: Text(
        entry.ticketName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${viewerOwes ? l10n.economyYouOwe(otherName) : l10n.economyOwesYou(otherName)}'
        ' · ${entry.spaceId == null ? l10n.economyOutsideSpace : l10n.economyInSpace}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: MoneyText(
        entry.amount,
        size: MoneySize.small,
        currency: entry.currency,
        tone: viewerOwes ? MoneyTone.negative : MoneyTone.positive,
      ),
    );
  }
}

class _PaymentTile extends ConsumerStatefulWidget {
  const _PaymentTile({required this.payment, required this.viewerUid});

  final EconomicPaymentView payment;
  final String viewerUid;

  @override
  ConsumerState<_PaymentTile> createState() => _PaymentTileState();
}

class _PaymentTileState extends ConsumerState<_PaymentTile> {
  var busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final payment = widget.payment;
    final label = switch (payment.status) {
      EconomicPaymentStatus.pending => l10n.economyPaymentPending,
      EconomicPaymentStatus.confirmed => l10n.economyPaymentConfirmed,
      EconomicPaymentStatus.cancelled => l10n.economyPaymentCancelled,
    };
    final canConfirm =
        payment.source == 'user' &&
        payment.status == EconomicPaymentStatus.pending &&
        payment.receiverUid == widget.viewerUid;
    final canCancel =
        payment.source == 'user' &&
        payment.status == EconomicPaymentStatus.pending &&
        payment.payerUid == widget.viewerUid;
    // El estado de un pago es una etiqueta, no una frase suelta: se lee de
    // un vistazo y no depende solo del color.
    final tone = switch (payment.status) {
      EconomicPaymentStatus.pending => BadgeTone.pending,
      EconomicPaymentStatus.confirmed => BadgeTone.positive,
      EconomicPaymentStatus.cancelled => BadgeTone.neutral,
    };
    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: StatusBadge(label, tone: tone)),
              const SizedBox(width: TokenSpacing.sm),
              MoneyText(
                payment.amount,
                size: MoneySize.small,
                currency: payment.currency,
              ),
            ],
          ),
          if (canConfirm || canCancel) ...[
            const SizedBox(height: TokenSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                children: [
                  if (canConfirm)
                    TextButton(
                      onPressed: busy ? null : () => _resolve('reject'),
                      child: Text(l10n.economyRejectPayment),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _resolve(canConfirm ? 'confirm' : 'cancel'),
                    child: Text(
                      canConfirm
                          ? l10n.economyConfirmPayment
                          : l10n.economyCancelPayment,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resolve(String action) async {
    setState(() => busy = true);
    try {
      final repository = ref.read(economicRepositoryProvider);
      if (action == 'confirm') {
        await repository.confirmPayment(widget.payment.id);
      } else if (action == 'reject') {
        await repository.rejectPayment(widget.payment.id);
      } else {
        await repository.cancelPayment(widget.payment.id);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _economicErrorText(AppLocalizations.of(context), error),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

String _economicErrorText(AppLocalizations l10n, Object error) {
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

int _millis(DateTime? date) => date?.millisecondsSinceEpoch ?? 0;

String _shortUid(String uid) =>
    uid.length <= 10 ? uid : '${uid.substring(0, 8)}…';
