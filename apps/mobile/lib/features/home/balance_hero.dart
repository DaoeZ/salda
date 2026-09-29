import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money_format.dart';
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

/// El saldo global es la cifra que manda en Inicio: por eso es la ÚNICA
/// superficie de tinta de la pantalla. Dos columnas, como el debe y el haber
/// de un libro, una fila por moneda.
class _CurrencyHero extends StatelessWidget {
  const _CurrencyHero({required this.summaries});
  final List<CurrencyEconomicSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.salda;
    return InkPanel(
      onTap: () => context.push('/home/economy'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(l10n.balanceHeroTitle, color: c.onInkMuted),
              ),
              Icon(Icons.arrow_forward, size: 18, color: c.onInkMuted),
            ],
          ),
          for (final summary in summaries) ...[
            const SizedBox(height: TokenSpacing.md),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Leg(
                      label: l10n.balanceTheyOweYou,
                      amount: summary.owedToMe,
                      currency: summary.currency,
                      color: c.inkPositive,
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: c.inkRule),
                  Expanded(
                    child: _Leg(
                      label: l10n.balanceYouOwe,
                      amount: summary.iOwe,
                      currency: summary.currency,
                      color: c.inkNegative,
                      alignEnd: true,
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
    // Un cero no es «a favor» ni «en contra»: va en tinta apagada, para que
    // el verde y el rojo solo aparezcan cuando significan algo.
    final zero = amount.cents == 0;
    return Padding(
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.onInkMuted),
          ),
          const SizedBox(height: TokenSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              formatCurrencyMoney(amount, currency),
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: zero ? c.onInkMuted : color,
                fontSize: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// En paz: el único estado de Inicio que es un HECHO cerrado, y por eso el
/// único que lleva sello. En papel, no en tinta: no hay cifra que destacar.
class _SettledHero extends StatelessWidget {
  const _SettledHero();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SaldaCard(
      onTap: () => context.push('/home/economy'),
      padding: const EdgeInsets.fromLTRB(
        TokenSpacing.xl,
        TokenSpacing.lg,
        TokenSpacing.lg,
        TokenSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(l10n.balanceHeroTitle),
                const SizedBox(height: TokenSpacing.xs),
                Text(
                  l10n.balanceSettled,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 2),
                Text(l10n.balanceSettledBody, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: TokenSpacing.md),
          Stamp(l10n.settledState),
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
        padding: EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton.line(width: 80, height: 12),
            SizedBox(height: TokenSpacing.md),
            Skeleton.line(width: 190, height: 30),
          ],
        ),
      ),
    ),
  );
}
