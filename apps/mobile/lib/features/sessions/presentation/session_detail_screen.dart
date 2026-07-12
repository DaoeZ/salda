import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/session_providers.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// Detalle de sesión: Resumen (balances + liquidaciones) · Cuentas · Actividad.
/// Los importes vienen de los agregados autoritativos de la function; la app
/// los pinta en tiempo real vía streams.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(sessionDetailProvider(sessionId)).value;

    if (detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final closed = detail.summary.status != SessionStatus.open;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(detail.summary.name),
          actions: [_Menu(sessionId: sessionId, detail: detail)],
          bottom: TabBar(tabs: [
            Tab(text: l10n.detailTabSummary),
            Tab(text: l10n.detailTabAccounts),
            Tab(text: l10n.detailTabActivity),
          ]),
        ),
        body: Column(children: [
          if (closed)
            MaterialBanner(
              content: Text(l10n.closedBanner),
              leading: const Icon(Icons.lock_outline),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: TabBarView(children: [
              _SummaryTab(sessionId: sessionId, detail: detail),
              _AccountsTab(sessionId: sessionId),
              _ActivityTab(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.sessionId, required this.detail});

  final String sessionId;
  final SessionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(sessionRepositoryProvider);
    final open = detail.summary.status == SessionStatus.open;

    Future<bool> confirm(String body) async =>
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(body),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.commonCancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.commonContinue)),
            ],
          ),
        ) ??
        false;

    return PopupMenuButton<String>(
      onSelected: (action) async {
        switch (action) {
          case 'share':
            context.go('/session/$sessionId/share');
          case 'close':
            if (await confirm(l10n.closeConfirmBody)) {
              await repo.setStatus(sessionId, SessionStatus.closed);
            }
          case 'reopen':
            await repo.setStatus(sessionId, SessionStatus.open);
          case 'archive':
            await repo.setStatus(sessionId, SessionStatus.archived);
          case 'delete':
            if (await confirm(l10n.deleteConfirmBody)) {
              await repo.deleteSession(sessionId);
              if (context.mounted) context.go('/home');
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'share', child: Text(l10n.menuShare)),
        if (open) PopupMenuItem(value: 'close', child: Text(l10n.menuClose)),
        if (!open)
          PopupMenuItem(value: 'reopen', child: Text(l10n.menuReopen)),
        if (!open)
          PopupMenuItem(value: 'archive', child: Text(l10n.menuArchive)),
        PopupMenuItem(value: 'delete', child: Text(l10n.menuDelete)),
      ],
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.sessionId, required this.detail});

  final String sessionId;
  final SessionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final participants =
        ref.watch(participantsProvider(sessionId)).value ?? const [];
    final settlements =
        ref.watch(settlementsProvider(sessionId)).value ?? const [];
    final names = {for (final p in participants) p.id: p.name};

    return ListView(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      children: [
        Text(l10n.balancesTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: TokenSpacing.sm),
        Card(
          child: Column(children: [
            for (final p in participants)
              _BalanceRow(
                name: p.name,
                balance: detail.balances[p.id],
              ),
          ]),
        ),
        const SizedBox(height: TokenSpacing.xl),
        Text(l10n.settlementsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: TokenSpacing.sm),
        if (settlements.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(TokenSpacing.lg),
              child: Row(children: [
                Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.settlementConfirmed),
                const SizedBox(width: TokenSpacing.sm),
                Text(l10n.allSettled),
              ]),
            ),
          )
        else
          for (final settlement in settlements)
            _SettlementCard(
              sessionId: sessionId,
              settlement: settlement,
              fromName: names[settlement.from] ?? settlement.from,
              toName: names[settlement.to] ?? settlement.to,
              open: detail.summary.status == SessionStatus.open,
            ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.name, required this.balance});

  final String name;
  final ParticipantBalanceView? balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final net = balance?.net.cents ?? 0;
    return ListTile(
      leading: CircleAvatar(
          radius: 16, child: Text(name.isEmpty ? '?' : name[0])),
      title: Text(name),
      subtitle: balance == null
          ? null
          : Text('${l10n.balancePaidLabel(formatMoney(balance!.paid))} · '
              '${l10n.balanceConsumedLabel(formatMoney(balance!.consumed))}'),
      trailing: Text(
        '${net > 0 ? '+' : ''}${formatMoney(Money(net))}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: net == 0
              ? scheme.onSurfaceVariant
              : net > 0
                  ? scheme.balancePositive
                  : scheme.balanceNegative,
        ),
      ),
    );
  }
}

class _SettlementCard extends ConsumerWidget {
  const _SettlementCard({
    required this.sessionId,
    required this.settlement,
    required this.fromName,
    required this.toName,
    required this.open,
  });

  final String sessionId;
  final Settlement settlement;
  final String fromName;
  final String toName;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final repo = ref.read(sessionRepositoryProvider);

    final (label, color) = switch (settlement.state) {
      SettlementState.pending => (l10n.statePending, scheme.settlementPending),
      SettlementState.marked => (l10n.stateMarked, scheme.settlementMarked),
      SettlementState.confirmed =>
        (l10n.stateConfirmed, scheme.settlementConfirmed),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
      child: ListTile(
        title: Text(l10n.settlementRow(fromName, toName)),
        subtitle: Row(children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: TokenSpacing.xs),
          Text(label),
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatMoney(settlement.amount),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (open && settlement.state != SettlementState.confirmed) ...[
              const SizedBox(width: TokenSpacing.sm),
              FilledButton.tonal(
                onPressed: () => repo.updateSettlementState(
                    sessionId, settlement.id, SettlementState.confirmed),
                child: Text(l10n.actionConfirm),
              ),
            ] else if (open) ...[
              const SizedBox(width: TokenSpacing.sm),
              IconButton(
                tooltip: l10n.actionBackToPending,
                onPressed: () => repo.updateSettlementState(
                    sessionId, settlement.id, SettlementState.pending),
                icon: const Icon(Icons.undo, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountsTab extends ConsumerWidget {
  const _AccountsTab({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider(sessionId)).value ?? const [];
    if (accounts.isEmpty) {
      return Center(child: Text(l10n.accountsEmpty));
    }
    return ListView(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      children: [
        for (final account in accounts)
          Card(
            margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(account.name),
              trailing: Text(
                formatMoney(account.grandTotal),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // El feed detallado llega con la web de invitados (M4): de momento los
    // eventos existen en Firestore pero no se listan aquí.
    return Center(
        child: Text(AppLocalizations.of(context).activityEmpty));
  }
}
