import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/session_export.dart';
import '../application/session_providers.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';
import 'ticket_navigation.dart';
import 'settlement_progress_bar.dart';

/// Detalle de sesión: Resumen (balances + liquidaciones) · Cuentas · Actividad.
/// Los importes vienen de los agregados autoritativos de la function; la app
/// los pinta en tiempo real vía streams.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _deleting = false;

  Future<void> _deleteSession() async {
    if (_deleting) return;

    // El router y el messenger pertenecen a la ruta, no al PopupMenu que se
    // desmonta en cuanto el stream deja de encontrar la sesión eliminada.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final deleteError = AppLocalizations.of(context).deleteError;
    setState(() => _deleting = true);
    try {
      await ref.read(sessionRepositoryProvider).deleteSession(widget.sessionId);
      router.go('/home');
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(deleteError)));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(sessionDetailProvider(widget.sessionId));
    final detail = detailAsync.value;

    if (detail == null) {
      if (!_deleting && detailAsync.hasValue) {
        // El documento también puede desaparecer desde otro dispositivo. La
        // ruta ya no es válida y debe abandonarse sin dejar un stream huérfano.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) GoRouter.of(context).go('/home');
        });
      }
      return Scaffold(
        body: Center(
          child: Semantics(
            label: _deleting ? l10n.deleteInProgress : null,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    final closed = detail.summary.status != SessionStatus.open;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(detail.summary.name),
          actions: [
            _Menu(
              sessionId: widget.sessionId,
              detail: detail,
              deleting: _deleting,
              onDelete: _deleteSession,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.detailTabSummary),
              Tab(text: l10n.detailTabAccounts),
              Tab(text: l10n.detailTabActivity),
            ],
          ),
        ),
        body: Column(
          children: [
            if (closed)
              MaterialBanner(
                content: Text(l10n.closedBanner),
                leading: const Icon(Icons.lock_outline),
                actions: const [SizedBox.shrink()],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _SummaryTab(sessionId: widget.sessionId, detail: detail),
                  _AccountsTab(sessionId: widget.sessionId),
                  _ActivityTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({
    required this.sessionId,
    required this.detail,
    required this.deleting,
    required this.onDelete,
  });

  final String sessionId;
  final SessionDetail detail;
  final bool deleting;
  final Future<void> Function() onDelete;

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
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.commonContinue),
              ),
            ],
          ),
        ) ??
        false;

    return PopupMenuButton<String>(
      enabled: !deleting,
      onSelected: (action) async {
        switch (action) {
          case 'share':
            context.go('/home/session/$sessionId/share');
          case 'export_pdf':
            final bytes = await buildSessionPdf(
              detail: detail,
              participants:
                  ref.read(participantsProvider(sessionId)).value ?? const [],
              settlements:
                  ref.read(settlementsProvider(sessionId)).value ?? const [],
              accounts: await repo.fetchFullTree(sessionId),
            );
            await SharePlus.instance.share(
              ShareParams(
                files: [
                  XFile.fromData(
                    bytes,
                    mimeType: 'application/pdf',
                    name: '${detail.summary.name}.pdf',
                  ),
                ],
              ),
            );
          case 'share_image':
            final bytes = await buildSummaryImage(
              detail: detail,
              participants:
                  ref.read(participantsProvider(sessionId)).value ?? const [],
            );
            await SharePlus.instance.share(
              ShareParams(
                files: [
                  XFile.fromData(
                    bytes,
                    mimeType: 'image/png',
                    name: '${detail.summary.name}.png',
                  ),
                ],
              ),
            );
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
              await onDelete();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'share', child: Text(l10n.menuShare)),
        PopupMenuItem(value: 'export_pdf', child: Text(l10n.menuExportPdf)),
        PopupMenuItem(value: 'share_image', child: Text(l10n.menuShareImage)),
        if (open) PopupMenuItem(value: 'close', child: Text(l10n.menuClose)),
        if (!open) PopupMenuItem(value: 'reopen', child: Text(l10n.menuReopen)),
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
    final progress = detail.summary.settlementProgress;

    // Confirmar la recepción es del RECEPTOR (P2.1): en la app, el owner
    // solo puede cuando el receptor es su propio participante o un nombre
    // sin reclamar (sin dispositivo, el owner actúa de representante).
    // Espejo exacto de la regla isReceiver() de Firestore.
    bool canConfirmFor(String toPid) {
      final receiver = participants.where((p) => p.id == toPid).firstOrNull;
      return receiver != null && receiver.claimedByDevice.isEmpty;
    }

    return ScreenBody(
      children: [
        SectionHeader(title: l10n.currentStateTitle),
        _CurrentStateCard(progress: progress),
        const SizedBox(height: TokenSpacing.md),
        SaldaCardList(
          children: [
            for (final p in participants)
              _CurrentBalanceRow(name: p.name, balance: detail.balances[p.id]),
          ],
        ),
        const SectionGap(),
        SectionHeader(title: l10n.settlementsTitle),
        // Pendientes/avisados arriba; los confirmados son HISTORIAL y van
        // aparte (bug 5 del MVP: mezclados parecían pagos duplicados).
        if (settlements
            .where((s) => s.state != SettlementState.confirmed)
            .isEmpty)
          SaldaCard(
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
                Expanded(child: Text(l10n.allSettled)),
              ],
            ),
          )
        else
          for (final settlement in settlements.where(
            (s) => s.state != SettlementState.confirmed,
          ))
            _SettlementCard(
              sessionId: sessionId,
              settlement: settlement,
              fromName: names[settlement.from] ?? settlement.from,
              toName: names[settlement.to] ?? settlement.to,
              open: detail.summary.status == SessionStatus.open,
              canConfirm: canConfirmFor(settlement.to),
            ),
        if (settlements.any((s) => s.state == SettlementState.confirmed)) ...[
          const SizedBox(height: TokenSpacing.md),
          SaldaCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(
                Icons.history,
                size: 20,
                color: context.salda.textMuted,
              ),
              title: Text(
                l10n.historyConfirmedTitle(
                  settlements
                      .where((s) => s.state == SettlementState.confirmed)
                      .length,
                ),
                style: theme.textTheme.titleSmall,
              ),
              children: [
                for (final settlement in settlements.where(
                  (s) => s.state == SettlementState.confirmed,
                ))
                  ListTile(
                    dense: true,
                    title: Text(
                      l10n.settlementRow(
                        names[settlement.from] ?? settlement.from,
                        names[settlement.to] ?? settlement.to,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(l10n.stateConfirmed),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MoneyText(
                          settlement.amount,
                          size: MoneySize.small,
                          tone: MoneyTone.muted,
                        ),
                        // Deshacer una confirmación también es del receptor.
                        if (detail.summary.status == SessionStatus.open &&
                            canConfirmFor(settlement.to))
                          IconButton(
                            tooltip: l10n.actionBackToPending,
                            onPressed: () => ref
                                .read(sessionRepositoryProvider)
                                .updateSettlementState(
                                  sessionId,
                                  settlement.id,
                                  SettlementState.pending,
                                ),
                            icon: const Icon(Icons.undo, size: 18),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SectionGap(),
        SectionHeader(title: l10n.economicHistoryTitle),
        SaldaCardList(
          children: [
            for (final p in participants)
              _HistoricalBalanceRow(
                name: p.name,
                balance: detail.balances[p.id],
              ),
          ],
        ),
      ],
    );
  }
}

class _CurrentStateCard extends StatelessWidget {
  const _CurrentStateCard({required this.progress});

  final SettlementProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final confirmed = formatMoney(progress.confirmed);
    final required = formatMoney(progress.required);
    final c = context.salda;
    return SaldaCard(
      color: progress.isSettled ? c.positiveMuted : c.surface,
      borderColor: progress.isSettled
          ? c.positive.withValues(alpha: 0.25)
          : c.border,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  progress.isSettled
                      ? Icons.check_rounded
                      : Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: progress.isSettled ? c.positive : c.primary,
                ),
                const SizedBox(width: TokenSpacing.sm),
                Expanded(
                  child: Text(
                    progress.isSettled
                        ? l10n.settledState
                        : l10n.settlementRemaining(
                            formatMoney(progress.remaining),
                          ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TokenSpacing.md),
            SettlementProgressBar(
              progress: progress,
              semanticLabel: l10n.settlementProgressSemantics,
              height: 8,
            ),
            const SizedBox(height: TokenSpacing.xs),
            Text(
              progress.required.isZero
                  ? l10n.noSettlementsRequired
                  : l10n.settlementProgressAmount(confirmed, required),
              style: theme.textTheme.bodySmall,
            ),
            if (!progress.marked.isZero) ...[
              const SizedBox(height: TokenSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: theme.colorScheme.settlementMarked,
                  ),
                  const SizedBox(width: TokenSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.settlementMarkedAmount(formatMoney(progress.marked)),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrentBalanceRow extends StatelessWidget {
  const _CurrentBalanceRow({required this.name, required this.balance});

  final String name;
  final ParticipantBalanceView? balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final outstanding = balance?.outstanding.cents ?? 0;
    final label = outstanding == 0
        ? l10n.settledState
        : outstanding > 0
        ? l10n.currentToReceive
        : l10n.currentToPay;
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        child: Text(name.isEmpty ? '?' : name[0]),
      ),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(label),
      trailing: Text(
        '${outstanding > 0 ? '+' : ''}${formatMoney(Money(outstanding))}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: outstanding == 0
              ? scheme.onSurfaceVariant
              : outstanding > 0
              ? scheme.balancePositive
              : scheme.balanceNegative,
        ),
      ),
    );
  }
}

class _HistoricalBalanceRow extends StatelessWidget {
  const _HistoricalBalanceRow({required this.name, required this.balance});

  final String name;
  final ParticipantBalanceView? balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final net = balance?.net.cents ?? 0;
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        child: Text(name.isEmpty ? '?' : name[0]),
      ),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: balance == null
          ? null
          : Text(
              '${l10n.balancePaidLabel(formatMoney(balance!.paid))} · '
              '${l10n.balanceConsumedLabel(formatMoney(balance!.consumed))}',
            ),
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
    required this.canConfirm,
  });

  final String sessionId;
  final Settlement settlement;
  final String fromName;
  final String toName;
  final bool open;

  /// El owner solo confirma si el receptor es suyo o está sin reclamar
  /// (P2.1); si no, confirma el receptor desde la web.
  final bool canConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final repo = ref.read(sessionRepositoryProvider);

    final (label, color) = switch (settlement.state) {
      SettlementState.pending => (l10n.statePending, scheme.settlementPending),
      SettlementState.marked => (l10n.stateMarked, scheme.settlementMarked),
      SettlementState.confirmed => (
        l10n.stateConfirmed,
        scheme.settlementConfirmed,
      ),
    };

    final tone = switch (settlement.state) {
      SettlementState.pending => BadgeTone.pending,
      SettlementState.marked => BadgeTone.warning,
      SettlementState.confirmed => BadgeTone.positive,
    };
    return SaldaCard(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settlementRow(fromName, toName),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: TokenSpacing.md),
                MoneyText(settlement.amount, size: MoneySize.medium),
              ],
            ),
            const SizedBox(height: TokenSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(label, tone: tone),
            ),
            if (open && settlement.state != SettlementState.confirmed) ...[
              const SizedBox(height: TokenSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: TokenSpacing.xs,
                  runSpacing: TokenSpacing.xs,
                  children: [
                    if (settlement.state == SettlementState.marked)
                      IconButton(
                        tooltip: l10n.actionBackToPending,
                        onPressed: () => repo.updateSettlementState(
                          sessionId,
                          settlement.id,
                          SettlementState.pending,
                        ),
                        icon: const Icon(Icons.undo, size: 18),
                      ),
                    if (canConfirm)
                      FilledButton.tonal(
                        onPressed: () => repo.updateSettlementState(
                          sessionId,
                          settlement.id,
                          SettlementState.confirmed,
                        ),
                        child: Text(l10n.actionConfirm),
                      )
                    else
                      // El receptor reclamó su nombre: confirma él desde la
                      // web. El creador no puede dar el dinero por recibido.
                      Text(
                        l10n.settlementAwaitsReceiver(toName),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
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
    final participants =
        ref.watch(participantsProvider(sessionId)).value ?? const [];
    final names = {for (final p in participants) p.id: p.name};
    if (accounts.isEmpty) {
      return ScreenBody(
        children: [
          EmptyState(
            icon: Icons.folder_outlined,
            title: l10n.accountsEmpty,
            body: l10n.emptyTicketsBody,
          ),
        ],
      );
    }
    return ScreenBody(
      children: [
        for (final account in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: TokenSpacing.md),
            child: _AccountCard(
              sessionId: sessionId,
              account: account,
              names: names,
            ),
          ),
      ],
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({
    required this.sessionId,
    required this.account,
    required this.names,
  });

  final String sessionId;
  final SessionAccount account;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tickets =
        ref
            .watch(accountTicketsProvider((sid: sessionId, aid: account.id)))
            .value ??
        const <SessionTicket>[];
    return Card(
      margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        initiallyExpanded: true,
        title: Text(account.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: Text(
            formatMoney(account.grandTotal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        children: [
          for (final ticket in tickets)
            ListTile(
              dense: true,
              leading: Icon(
                ticket.kind == 'manual'
                    ? Icons.edit_note_outlined
                    : Icons.photo_camera_outlined,
              ),
              title: Text(
                ticket.merchantName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (ticket.date != null) ticket.date!,
                  l10n.ticketPaidBy(names[ticket.paidBy] ?? '—'),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                formatMoney(ticket.grandTotal),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              // Misma ruta que el resto de superficies: una sola forma de
              // abrir un ticket en toda la app.
              onTap: () => openTicket(
                context,
                sessionId: sessionId,
                ticketId: ticket.id,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // El feed detallado llega con la web de invitados (M4): de momento los
    // eventos existen en Firestore pero no se listan aquí.
    return Center(child: Text(AppLocalizations.of(context).activityEmpty));
  }
}
