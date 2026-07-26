import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../data/economic_repository.dart';

class SpaceEconomicSummary extends ConsumerWidget {
  const SpaceEconomicSummary({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(economicOverviewProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.spaceEconomicTitle),
        overview.when(
          loading: () => const SkeletonList(rows: 2, leading: false),
          error: (_, _) => ErrorStateView(message: l10n.economyLoadError),
          data: (global) {
            final scoped = global.withinSpace(spaceId);
            final open = scoped.balances
                .where((balance) => balance.signedOutstandingCents != 0)
                .toList();
            // Cero deudas abiertas es una BUENA noticia, no un vacío: se
            // dice con el mismo tono verde que el resto de lo saldado.
            if (open.isEmpty) {
              return SaldaCard(
                color: context.salda.positiveMuted,
                borderColor: context.salda.positive.withValues(alpha: 0.25),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: context.salda.positive,
                    ),
                    const SizedBox(width: TokenSpacing.md),
                    Expanded(child: Text(l10n.spaceEconomicEmpty)),
                  ],
                ),
              );
            }
            return SaldaCardList(
              children: [
                for (final balance in open)
                  _SpaceBalanceTile(
                    balance: balance,
                    viewerUid: scoped.viewerUid,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SpaceBalanceTile extends ConsumerWidget {
  const _SpaceBalanceTile({required this.balance, required this.viewerUid});

  final BilateralEconomicBalance balance;
  final String viewerUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final otherUid = balance.firstUid == viewerUid
        ? balance.secondUid
        : balance.firstUid;
    final profile = ref.watch(publicProfileProvider(otherUid)).value;
    final name = profile?.displayName ?? otherUid;
    final iOwe = balance.debtorUid == viewerUid;
    return ListTile(
      onTap: () => context.push('/home/economy/$otherUid'),
      leading: SaldaAvatar(seed: otherUid, label: name, radius: 17),
      title: Text(
        iOwe ? l10n.economyYouOwe(name) : l10n.economyOwesYou(name),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: MoneyText(
        balance.outstanding,
        size: MoneySize.small,
        currency: balance.currency,
        tone: iOwe ? MoneyTone.negative : MoneyTone.positive,
      ),
    );
  }
}
