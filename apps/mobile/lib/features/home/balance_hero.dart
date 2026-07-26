import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/money_text.dart';
import '../../core/ui/states.dart';
import '../../core/ui/surfaces.dart';
import '../../l10n/generated/app_localizations.dart';
import '../economy/data/economic_repository.dart';
import '../economy/domain/economic_models.dart';

/// Lo primero que se ve al abrir la app: en qué situación estás.
///
/// El importe manda —tamaño display, cifras tabulares, una sola línea— y
/// debajo va el desglose «te deben / debes». El signo económico se transmite
/// por **rótulo, signo y color a la vez**: quien no distingue verde de rojo
/// lee «A tu favor» o «En tu contra» igual de rápido.
class BalanceHero extends ConsumerWidget {
  const BalanceHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(economicOverviewProvider)
        .when(
          loading: () => const _HeroSkeleton(),
          error: (_, _) => ErrorStateView(message: l10n.economyLoadError),
          data: (data) {
            final summaries = data.summaries
                .where((s) => s.owedToMe.cents != 0 || s.iOwe.cents != 0)
                .toList();
            if (summaries.isEmpty) return const _SettledHero();
            return Column(
              children: [
                for (final summary in summaries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TokenSpacing.md),
                    child: _CurrencyHero(summary: summary),
                  ),
              ],
            );
          },
        );
  }
}

class _CurrencyHero extends StatelessWidget {
  const _CurrencyHero({required this.summary});

  final CurrencyEconomicSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final net = summary.net;
    final positive = net.cents > 0;
    final tone = net.cents == 0
        ? MoneyTone.neutral
        : positive
        ? MoneyTone.positive
        : MoneyTone.negative;

    return SaldaCard(
      onTap: () => context.push('/home/economy'),
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.balanceHeroTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: c.textMuted,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (net.cents != 0)
                StatusBadge(
                  positive ? l10n.balanceNetPositive : l10n.balanceNetNegative,
                  tone: positive ? BadgeTone.positive : BadgeTone.negative,
                  icon: positive ? Icons.trending_up : Icons.trending_down,
                ),
            ],
          ),
          const SizedBox(height: TokenSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              // El neto se enseña en valor absoluto: el sentido lo dice el
              // rótulo, no un menos que se confunde con un guion.
              Money(net.cents.abs()),
              size: MoneySize.large,
              tone: tone,
              currency: summary.currency,
            ),
          ),
          const SizedBox(height: TokenSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _Leg(
                  label: l10n.balanceTheyOweYou,
                  amount: summary.owedToMe,
                  currency: summary.currency,
                  color: c.positive,
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _Leg(
                  label: l10n.balanceYouOwe,
                  amount: summary.iOwe,
                  currency: summary.currency,
                  color: c.negative,
                  alignEnd: true,
                ),
              ),
            ],
          ),
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
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final Money amount;
  final String currency;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!alignEnd) ...[
              ToneDot(color),
              const SizedBox(width: TokenSpacing.sm),
            ],
            // Con el texto ampliado el rótulo debe recortarse, no empujar
            // la fila fuera de la tarjeta.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
            if (alignEnd) ...[
              const SizedBox(width: TokenSpacing.sm),
              ToneDot(color),
            ],
          ],
        ),
        const SizedBox(height: 2),
        MoneyText(amount, size: MoneySize.small, currency: currency),
      ],
    );
  }
}

class _SettledHero extends StatelessWidget {
  const _SettledHero();

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.positiveMuted,
              borderRadius: BorderRadius.circular(TokenRadius.control),
            ),
            child: Icon(Icons.check_rounded, size: 20, color: c.positive),
          ),
          const SizedBox(width: TokenSpacing.lg),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SaldaCard(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton.line(width: 64, height: 11),
          const SizedBox(height: TokenSpacing.lg),
          const Skeleton.line(width: 176, height: 34),
          const SizedBox(height: TokenSpacing.xl),
          Row(
            children: const [
              Expanded(child: Skeleton.line(width: 92)),
              Expanded(child: Skeleton.line(width: 92)),
            ],
          ),
        ],
      ),
    ),
  );
}
