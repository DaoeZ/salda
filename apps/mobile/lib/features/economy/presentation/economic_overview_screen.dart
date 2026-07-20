import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../data/economic_repository.dart';
import '../domain/economic_models.dart';

class EconomicOverviewScreen extends ConsumerWidget {
  const EconomicOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(economicOverviewProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.economyTitle)),
      body: overview.when(
        loading: () => const _EconomicSkeleton(),
        error: (_, _) => _EconomicError(
          onRetry: () {
            ref.invalidate(economicEntriesProvider);
            ref.invalidate(economicPaymentsProvider);
          },
        ),
        data: (data) => _OverviewBody(overview: data),
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
    final overview = ref.watch(economicOverviewProvider);
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
  const _OverviewBody({required this.overview});

  final EconomicOverview overview;

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
    return ListView(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      children: [
        for (final summary in overview.summaries)
          Card(child: _SummaryRow(summary: summary)),
        if (pendingToMe.isNotEmpty) ...[
          const SizedBox(height: TokenSpacing.lg),
          Text(
            l10n.economyPendingConfirmations,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: TokenSpacing.sm),
          for (final payment in pendingToMe)
            _PendingConfirmation(payment: payment),
        ],
        if (open.isNotEmpty) ...[
          const SizedBox(height: TokenSpacing.lg),
          Text(
            l10n.economyRelationsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: TokenSpacing.sm),
          for (final balance in open)
            _RelationshipTile(balance: balance, viewerUid: overview.viewerUid),
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
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    Widget amount(String label, Money money) => Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(formatCurrencyMoney(money, summary.currency), style: style),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.md),
      child: Row(
        children: [
          amount(l10n.economyOwedToMe, summary.owedToMe),
          amount(l10n.economyIOwe, summary.iOwe),
          amount(l10n.economyNet, summary.net),
        ],
      ),
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
    final profile = ref.watch(publicProfileProvider(otherUid)).value;
    final name = profile?.displayName ?? _shortUid(otherUid);
    final iOwe = balance.debtorUid == viewerUid;
    return Card(
      child: ListTile(
        onTap: () => context.push('/home/economy/$otherUid'),
        leading: ProfileAvatar(seed: otherUid, displayName: name),
        title: Text(
          iOwe ? l10n.economyYouOwe(name) : l10n.economyOwesYou(name),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(balance.currency),
        trailing: Text(
          formatCurrencyMoney(balance.outstanding, balance.currency),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _PendingConfirmation extends ConsumerStatefulWidget {
  const _PendingConfirmation({required this.payment});

  final EconomicPaymentView payment;

  @override
  ConsumerState<_PendingConfirmation> createState() =>
      _PendingConfirmationState();
}

class _PendingConfirmationState extends ConsumerState<_PendingConfirmation> {
  var busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref
        .watch(publicProfileProvider(widget.payment.payerUid))
        .value;
    final name = profile?.displayName ?? _shortUid(widget.payment.payerUid);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    formatCurrencyMoney(
                      widget.payment.amount,
                      widget.payment.currency,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await ref
                            .read(economicRepositoryProvider)
                            .confirmPayment(widget.payment.id);
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.economyConfirmPayment),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyEconomy extends StatelessWidget {
  const _EmptyEconomy({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 64),
          const SizedBox(height: TokenSpacing.md),
          Text(l10n.economyEmptyTitle),
          const SizedBox(height: TokenSpacing.xs),
          Text(l10n.economyEmptyBody, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _EconomicError extends StatelessWidget {
  const _EconomicError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).economyLoadError,
          textAlign: TextAlign.center,
        ),
        OutlinedButton(
          onPressed: onRetry,
          child: Text(AppLocalizations.of(context).commonRetry),
        ),
      ],
    ),
  );
}

class _EconomicSkeleton extends StatelessWidget {
  const _EconomicSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(TokenSpacing.lg),
    children: [
      for (var i = 0; i < 4; i++)
        const Card(
          child: SizedBox(height: 76, child: LinearProgressIndicator()),
        ),
    ],
  );
}

String _shortUid(String uid) =>
    uid.length <= 10 ? uid : '${uid.substring(0, 8)}…';
