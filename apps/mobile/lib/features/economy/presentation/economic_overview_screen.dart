import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../application/identity_names.dart';
import 'economic_names.dart';
import 'obligation_settlement.dart';
import '../data/economic_repository.dart';
import '../domain/economic_models.dart';

class EconomicOverviewScreen extends ConsumerWidget {
  const EconomicOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(participantEconomicOverviewProvider);
    final canMutate = ref.watch(currentAppUserProvider)?.isFullAccount ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.economyTitle)),
      body: overview.when(
        loading: () => const _EconomicSkeleton(),
        error: (_, _) => _EconomicError(
          onRetry: () {
            retryParticipantEconomicOverview(ref);
          },
        ),
        data: (data) => _OverviewBody(overview: data, canMutate: canMutate),
      ),
    );
  }
}

/// Tarjeta reutilizada en Home. Sustituye la suma antigua limitada a
/// sesiones propias y deja siempre visible la moneda de cada total.
class EconomicHomeCard extends ConsumerWidget {
  const EconomicHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(participantEconomicOverviewProvider);
    return overview.maybeWhen(
      data: (data) {
        if (data.summaries.isEmpty) return const SizedBox.shrink();
        return Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: InkWell(
            borderRadius: BorderRadius.circular(TokenRadius.card),
            onTap: () => context.push('/home/economy'),
            child: Padding(
              padding: const EdgeInsets.all(TokenSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.economySummaryTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  for (final summary in data.summaries)
                    _SummaryRow(summary: summary),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.overview, required this.canMutate});

  final EconomicOverview overview;
  final bool canMutate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final open = overview.balances
        .where((balance) => balance.signedOutstandingCents != 0)
        .toList();
    final pendingToMe = overview.payments
        .where(
          (payment) =>
              payment.receiverUid == overview.viewerUid &&
              payment.status == EconomicPaymentStatus.pending,
        )
        .toList();
    if (open.isEmpty && pendingToMe.isEmpty) {
      return _EmptyEconomy(l10n: l10n);
    }
    return ScreenBody(
      children: [
        for (final summary in overview.summaries)
          Padding(
            padding: const EdgeInsets.only(bottom: TokenSpacing.md),
            child: SaldaCard(
              padding: const EdgeInsets.all(TokenSpacing.xl),
              child: _SummaryRow(summary: summary),
            ),
          ),
        if (pendingToMe.isNotEmpty) ...[
          const SectionGap(),
          SectionHeader(title: l10n.economyPendingConfirmations),
          SaldaCardList(
            children: [
              for (final payment in pendingToMe)
                _PendingConfirmation(payment: payment, canMutate: canMutate),
            ],
          ),
        ],
        if (open.isNotEmpty) ...[
          const SectionGap(),
          SectionHeader(title: l10n.economyRelationsTitle),
          SaldaCardList(
            children: [
              for (final balance in open)
                _RelationshipTile(
                  balance: balance,
                  viewerUid: overview.viewerUid,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final CurrencyEconomicSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.salda;
    Widget amount(String label, Money money, MoneyTone tone) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              money,
              size: MoneySize.small,
              currency: summary.currency,
              tone: tone,
            ),
          ),
        ],
      ),
    );
    final net = summary.net;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        amount(l10n.economyOwedToMe, summary.owedToMe, MoneyTone.positive),
        amount(l10n.economyIOwe, summary.iOwe, MoneyTone.negative),
        amount(
          l10n.economyNet,
          net,
          net.cents == 0
              ? MoneyTone.muted
              : net.cents > 0
              ? MoneyTone.positive
              : MoneyTone.negative,
        ),
      ],
    );
  }
}

class _RelationshipTile extends ConsumerWidget {
  const _RelationshipTile({required this.balance, required this.viewerUid});

  final BilateralEconomicBalance balance;
  final String viewerUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final otherUid = balance.firstUid == viewerUid
        ? balance.secondUid
        : balance.firstUid;
    final name = economicNameText(ref, l10n, otherUid);
    final iOwe = balance.debtorUid == viewerUid;
    return ListTile(
      onTap: () => context.push('/home/economy/$otherUid'),
      leading: SaldaAvatar(
        seed: economicAvatarSeed(otherUid),
        label: name,
        radius: 18,
      ),
      title: Text(
        iOwe ? l10n.economyYouOwe(name) : l10n.economyOwesYou(name),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(
            balance.outstanding,
            size: MoneySize.small,
            currency: balance.currency,
            tone: iOwe ? MoneyTone.negative : MoneyTone.positive,
          ),
          // Cobrar se alcanza desde el propio saldo, sin pasar por el
          // detalle: es la misma acción y el mismo sistema en todas partes.
          if (!iOwe && balance.debtorUid != null)
            IconButton(
              tooltip: l10n.economyConfirmPayment,
              icon: const Icon(Icons.check_rounded, size: 20),
              onPressed: () => openObligationSettlement(
                context,
                debtorActor: balance.debtorUid!,
                creditorActor: viewerUid,
                currency: balance.currency,
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingConfirmation extends ConsumerStatefulWidget {
  const _PendingConfirmation({required this.payment, required this.canMutate});

  final EconomicPaymentView payment;
  final bool canMutate;

  @override
  ConsumerState<_PendingConfirmation> createState() =>
      _PendingConfirmationState();
}

class _PendingConfirmationState extends ConsumerState<_PendingConfirmation> {
  var busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = economicNameText(ref, l10n, widget.payment.payerUid);
    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            formatCurrencyMoney(widget.payment.amount, widget.payment.currency),
          ),
          if (widget.canMutate) ...[
            const SizedBox(height: TokenSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: busy ? null : _confirm,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.economyConfirmPayment),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(economicRepositoryProvider).confirmPayment(widget.payment);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_paymentErrorText(l10n, error))));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
}

String _paymentErrorText(AppLocalizations l10n, Object error) {
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

class _EmptyEconomy extends StatelessWidget {
  const _EmptyEconomy({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => ScreenBody(
    children: [
      EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.economyEmptyTitle,
        body: l10n.economyEmptyBody,
      ),
    ],
  );
}

class _EconomicError extends StatelessWidget {
  const _EconomicError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ScreenBody(
    children: [
      ErrorStateView(
        message: AppLocalizations.of(context).economyLoadError,
        onRetry: onRetry,
      ),
    ],
  );
}

class _EconomicSkeleton extends StatelessWidget {
  const _EconomicSkeleton();

  @override
  // Barras de progreso apiladas no dicen nada; un esqueleto con la forma de
  // lo que llega evita además que el contenido salte al aparecer.
  Widget build(BuildContext context) =>
      const ScreenBody(children: [SkeletonList(rows: 4)]);
}
