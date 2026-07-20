import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/money_format.dart';
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
        Text(
          l10n.spaceEconomicTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: TokenSpacing.sm),
        overview.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text(l10n.economyLoadError),
          data: (global) {
            final scoped = global.withinSpace(spaceId);
            final open = scoped.balances
                .where((balance) => balance.signedOutstandingCents != 0)
                .toList();
            if (open.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(TokenSpacing.md),
                  child: Text(l10n.spaceEconomicEmpty),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final balance in open)
                    _SpaceBalanceTile(
                      balance: balance,
                      viewerUid: scoped.viewerUid,
                    ),
                ],
              ),
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
      title: Text(
        iOwe ? l10n.economyYouOwe(name) : l10n.economyOwesYou(name),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(balance.currency),
      trailing: Text(
        formatCurrencyMoney(balance.outstanding, balance.currency),
      ),
    );
  }
}
