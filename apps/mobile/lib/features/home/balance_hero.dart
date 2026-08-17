import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/money_text.dart';
import '../../core/ui/states.dart';
import '../../core/ui/surfaces.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/data/auth_repository.dart';
import '../economy/data/economic_repository.dart';
import '../economy/domain/economic_models.dart';

/// Resumen económico por moneda. Te deben y Debes son coprincipales: nunca se
/// compensa ni se convierte moneda para fabricar un neto protagonista.
class BalanceHero extends ConsumerWidget {
  const BalanceHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(participantEconomicOverviewProvider)
        .when(
          loading: () => const _HeroSkeleton(),
          error: (_, _) => ErrorStateView(
            message: l10n.economyLoadError,
            onRetry: () => retryParticipantEconomicOverview(ref),
          ),
          data: (overview) {
            final summaries = overview.summaries
                .where((s) => s.owedToMe.cents != 0 || s.iOwe.cents != 0)
                .toList();
            if (summaries.isEmpty) {
              final isGuest =
                  ref.watch(currentAppUserProvider)?.isAnonymous ?? false;
              return isGuest ? const _GuestEconomyHero() : const _SettledHero();
            }
            return _CurrencyHero(summaries: summaries);
          },
        );
  }
}

class _CurrencyHero extends StatelessWidget {
  const _CurrencyHero({required this.summaries});
  final List<CurrencyEconomicSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.salda;
    return SaldaCard(
      onTap: () => context.push('/home/economy'),
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.balanceHeroTitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final summary in summaries) ...[
            const SizedBox(height: TokenSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _Leg(
                    label: l10n.balanceTheyOweYou,
                    amount: summary.owedToMe,
                    currency: summary.currency,
                    tone: MoneyTone.positive,
                  ),
                ),
                Container(width: 1, height: 46, color: c.border),
                Expanded(
                  child: _Leg(
                    label: l10n.balanceYouOwe,
                    amount: summary.iOwe,
                    currency: summary.currency,
                    tone: MoneyTone.negative,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({
    required this.label,
    required this.amount,
    required this.currency,
    required this.tone,
    this.alignEnd = false,
  });

  final String label;
  final Money amount;
  final String currency;
  final MoneyTone tone;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: alignEnd ? TokenSpacing.md : 0,
      right: alignEnd ? 0 : TokenSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: TokenSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: MoneyText(
            amount,
            size: MoneySize.medium,
            currency: currency,
            tone: tone,
          ),
        ),
      ],
    ),
  );
}

class _SettledHero extends StatelessWidget {
  const _SettledHero();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      onTap: () => context.push('/home/economy'),
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: TokenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.balanceSettled,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  l10n.balanceSettledBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestEconomyHero extends StatelessWidget {
  const _GuestEconomyHero();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeGuestEconomyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: TokenSpacing.xs),
          Text(
            l10n.homeGuestEconomyBody,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: AppLocalizations.of(context).scanProcessing,
    child: const ExcludeSemantics(
      child: SaldaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton.line(width: 80, height: 12),
            SizedBox(height: TokenSpacing.md),
            Skeleton.line(width: 190, height: 28),
          ],
        ),
      ),
    ),
  );
}
