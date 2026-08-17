import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/money_text.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../economy/data/economic_repository.dart';
import '../../economy/application/identity_names.dart';
import '../../economy/presentation/economic_names.dart';
import '../../sessions/presentation/ticket_navigation.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';

/// Economy projected strictly inside one context.  This is intentionally not
/// a link to the global relation: its rows always describe this space.
class SpaceBalances extends ConsumerWidget {
  const SpaceBalances({super.key, required this.spaceId, this.compact = false});

  final String spaceId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(participantEconomicOverviewProvider)
        .when(
          loading: () => const SkeletonList(rows: 2, leading: false),
          error: (_, _) => ErrorStateView(
            message: l10n.economyLoadError,
            onRetry: () => retryParticipantEconomicOverview(ref),
          ),
          data: (overview) {
            final scoped = overview.withinSpace(spaceId);
            final balances = scoped.balances
                .where((balance) => balance.signedOutstandingCents != 0)
                .toList();
            if (balances.isEmpty) {
              return ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l10n.spaceEconomicSettled),
              );
            }
            final visible = compact ? balances.take(2).toList() : balances;
            return Column(
              children: [
                for (final balance in visible)
                  _SpaceBalanceRow(
                    spaceId: spaceId,
                    balance: balance,
                    viewerUid: scoped.viewerUid,
                  ),
              ],
            );
          },
        );
  }
}

class _SpaceBalanceRow extends ConsumerWidget {
  const _SpaceBalanceRow({
    required this.spaceId,
    required this.balance,
    required this.viewerUid,
    this.linkEnabled = true,
  });

  final String spaceId;
  final BilateralEconomicBalance balance;
  final String viewerUid;
  final bool linkEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final otherUid = balance.firstUid == viewerUid
        ? balance.secondUid
        : balance.firstUid;
    final name = economicNameText(ref, l10n, otherUid);
    final iOwe = balance.debtorUid == viewerUid;
    return ListTile(
      minTileHeight: 48,
      leading: SaldaAvatar(
        seed: economicAvatarSeed(otherUid),
        label: name,
        radius: 17,
      ),
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
      onTap: linkEnabled
          ? () => context.push('/home/spaces/$spaceId/balances/$otherUid')
          : null,
    );
  }
}

class SpaceTicketsPreview extends ConsumerWidget {
  const SpaceTicketsPreview({super.key, required this.spaceId, this.limit = 3});

  final String spaceId;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(spaceTicketsProvider(spaceId))
        .when(
          loading: () => const SkeletonList(rows: 2, leading: false),
          error: (_, _) => ErrorStateView(
            message: l10n.spacesLoadError,
            onRetry: () => ref.invalidate(spaceTicketsProvider(spaceId)),
          ),
          data: (tickets) {
            if (tickets.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: l10n.emptyTicketsTitle,
                body: l10n.spaceTicketsEmpty,
              );
            }
            final visible = tickets.take(limit).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SaldaCardList(
                  children: [
                    for (final ticket in visible) TicketRow(ticket: ticket),
                  ],
                ),
              ],
            );
          },
        );
  }
}

class TicketRow extends StatelessWidget {
  const TicketRow({super.key, required this.ticket});

  final SpaceTicket ticket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      minTileHeight: 48,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(
        ticket.merchantName.isEmpty
            ? l10n.spaceTicketUntitled
            : ticket.merchantName,
      ),
      subtitle: ticket.date == null ? null : Text(ticket.date!),
      trailing: MoneyText(Money(ticket.grandTotalCents), size: MoneySize.small),
      onTap: () =>
          openTicket(context, sessionId: ticket.sessionId, ticketId: ticket.id),
    );
  }
}

class SpaceTicketsScreen extends ConsumerWidget {
  const SpaceTicketsScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tickets = ref.watch(spaceTicketsProvider(spaceId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.spaceTicketsAllTitle)),
      body: tickets.when(
        loading: () =>
            const ScreenBody(children: [SkeletonList(rows: 4, leading: false)]),
        error: (_, _) => ScreenBody(
          children: [
            ErrorStateView(
              message: l10n.spacesLoadError,
              onRetry: () => ref.invalidate(spaceTicketsProvider(spaceId)),
            ),
          ],
        ),
        data: (items) => items.isEmpty
            ? ScreenBody(
                children: [
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: l10n.emptyTicketsTitle,
                    body: l10n.spaceTicketsEmpty,
                  ),
                ],
              )
            : ListView.separated(
                itemCount: items.length,
                itemBuilder: (_, index) => TicketRow(ticket: items[index]),
                separatorBuilder: (_, _) => const Divider(height: 1),
              ),
      ),
    );
  }
}

class SpaceBalancesScreen extends StatelessWidget {
  const SpaceBalancesScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).spaceBalancesAllTitle),
    ),
    body: ScreenBody(children: [SpaceBalances(spaceId: spaceId)]),
  );
}

/// Detail constrained by both the context and counterpart.  It deliberately
/// never links back to a global economic relation, where entries from another
/// space would be mixed into the explanation.
class SpaceBalanceDetailScreen extends ConsumerWidget {
  const SpaceBalanceDetailScreen({
    super.key,
    required this.spaceId,
    required this.otherUid,
  });

  final String spaceId;
  final String otherUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final name = economicNameText(ref, l10n, otherUid);
    final overview = ref.watch(participantEconomicOverviewProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.economyDetailTitle(name))),
      body: overview.when(
        loading: () => const ScreenBody(children: [SkeletonList(rows: 2)]),
        error: (_, _) => ScreenBody(
          children: [
            ErrorStateView(
              message: l10n.economyLoadError,
              onRetry: () => retryParticipantEconomicOverview(ref),
            ),
          ],
        ),
        data: (data) {
          final balances = data.withinSpace(spaceId).withUser(otherUid);
          if (balances.isEmpty) {
            return ScreenBody(
              children: [
                EmptyState(
                  icon: Icons.check_circle_outline,
                  title: l10n.spaceEconomicSettled,
                  body: l10n.spaceEconomicEmpty,
                ),
              ],
            );
          }
          return ScreenBody(
            children: [
              for (final balance in balances)
                _SpaceBalanceRow(
                  spaceId: spaceId,
                  balance: balance,
                  viewerUid: data.viewerUid,
                  linkEnabled: false,
                ),
            ],
          );
        },
      ),
    );
  }
}

class CoverSection extends StatelessWidget {
  const CoverSection({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
      const SizedBox(height: TokenSpacing.sm),
      child,
    ],
  );
}
