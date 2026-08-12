import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../economy/data/economic_repository.dart';
import '../../economy/presentation/economic_names.dart';
import '../application/home_balance_selector.dart';

/// Preview constante de los balances; la lista económica conserva el total.
class HomeBalancePreviewSection extends ConsumerWidget {
  const HomeBalancePreviewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(economicOverviewProvider)
        .when(
          loading: () =>
              const Column(children: [SectionGap(), SkeletonList(rows: 2)]),
          error: (_, _) => Column(
            children: [
              const SectionGap(),
              ErrorStateView(message: l10n.economyLoadError),
            ],
          ),
          data: (overview) {
            final preview = selectHomeBalancePreview(overview);
            if (preview.rows.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                const SectionGap(),
                SectionHeader(
                  title: l10n.homeBalances,
                  action: l10n.homeSeeBalances(preview.totalCount),
                  onAction: () => context.push('/home/economy'),
                ),
                SaldaCardList(
                  children: [for (final row in preview.rows) _Row(row: row)],
                ),
              ],
            );
          },
        );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.row});
  final HomeBalanceRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final name = economicNameText(ref, l10n, row.personUid);
    final owed = row.direction == HomeBalanceDirection.owedToMe;
    return ListTile(
      title: Text(name),
      subtitle: Text(owed ? l10n.balanceTheyOweYou : l10n.balanceYouOwe),
      trailing: SizedBox(
        width: 88,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: MoneyText(
            row.amount,
            currency: row.currency,
            tone: owed ? MoneyTone.positive : MoneyTone.negative,
          ),
        ),
      ),
      onTap: () => context.push('/home/economy/${row.personUid}'),
    );
  }
}
