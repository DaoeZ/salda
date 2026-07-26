import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/states.dart';
import '../../core/ui/surfaces.dart';
import '../../core/ui/wordmark.dart';
import '../../core/utils/money_format.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/data/auth_repository.dart';
import '../auth/data/guest_identity_repository.dart';
import '../spaces/data/manual_link_repository.dart';
import '../economy/presentation/economic_overview_screen.dart';
import '../profile/data/profile_repository.dart';
import '../review/application/draft_store.dart';
import '../review/application/review_draft.dart';
import '../sessions/application/session_providers.dart';
import '../sessions/domain/session_models.dart';
import '../sessions/presentation/settlement_progress_bar.dart';
import '../spaces/data/spaces_repository.dart';
import '../spaces/domain/space_models.dart';
import '../../core/ui/badges.dart';
import '../spaces/presentation/space_row.dart';
import '../spaces/presentation/space_title_text.dart';
import '../spaces/presentation/spaces_screen.dart';
import 'balance_hero.dart';
import 'home_shell.dart';

/// Inicio: centro operativo. La jerarquía es deliberada —balance, acción,
/// contextos, actividad— y no una sucesión de tarjetas del mismo peso.
///
/// La barra superior llevaba OCHO iconos: una fila de accesos indistinguibles
/// que obligaba a leerlos todos. Ahora quedan el wordmark, el enlace de
/// entrada y un menú; el resto vive donde se usa.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fullAccount =
        ref.watch(currentAppUserProvider)?.isFullAccount ?? false;
    // Un INVITADO con nombre PARTICIPA (ADR-034): ve sus grupos y sus
    // invitaciones igual que una cuenta. Lo que sigue siendo exclusivo de
    // una cuenta es CREAR contextos, que es lo que gobierna el FAB.
    final participates = fullAccount || ref.watch(isOperationalGuestProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: TokenLayout.screenMargin,
        title: const SaldaWordmark(),
        actions: [
          if (fullAccount) const _ManualLinkBadge(),
          // Unirse por enlace no exige cuenta: es la puerta de entrada del
          // invitado (ADR-035), así que está siempre visible.
          IconButton(
            tooltip: l10n.joinEntry,
            onPressed: () => context.push('/join'),
            icon: const Icon(Icons.add_link),
          ),
          HomeMenuButton(participates: participates, fullAccount: fullAccount),
          const SizedBox(width: TokenSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          const _GuestNameBanner(),
          const _ProfileBanner(),
          const _DraftBanner(),
          Expanded(
            child: participates
                ? const _ContextsHome()
                : const _AccountRequiredHome(),
          ),
        ],
      ),
      floatingActionButton: fullAccount
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateContextSheet(context, ref),
              icon: const Icon(Icons.add, size: 20),
              label: Text(l10n.contextCreate),
            )
          : null,
    );
  }
}

/// Historial económico anterior al modelo contextual. Es deliberadamente
/// solo lectura desde esta entrada: nunca inventa una relación o grupo.
class LegacySessionsScreen extends ConsumerWidget {
  const LegacySessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: ref
          .watch(sessionsProvider)
          .when(
            loading: () => const _SessionsSkeleton(),
            error: (error, _) => Center(child: Text('$error')),
            data: (sessions) => sessions.isEmpty
                ? _EmptyState(l10n: l10n)
                : _SessionsList(sessions: sessions),
          ),
    );
  }
}

class _AccountRequiredHome extends StatelessWidget {
  const _AccountRequiredHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ScreenBody(
      children: [
        EmptyState(
          icon: Icons.lock_person_outlined,
          title: l10n.contextAccountRequiredTitle,
          body: l10n.contextAccountRequired,
          action: l10n.authProtectGuestAction,
          onAction: () => context.push('/register'),
        ),
      ],
    );
  }
}

class _ContextsHome extends ConsumerWidget {
  const _ContextsHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final spaces = ref.watch(mySpacesProvider);
    final invites = ref.watch(mySpaceInvitesProvider).value ?? const [];
    return spaces.when(
      loading: () => const ScreenBody(
        children: [BalanceHero(), SectionGap(), SkeletonList()],
      ),
      error: (_, _) =>
          ScreenBody(children: [ErrorStateView(message: l10n.spacesLoadError)]),
      data: (all) {
        final active = all.where((space) => space.isActive).toList();
        final relationships = active
            .where((space) => space.isRelationship)
            .toList();
        final groups = active.where((space) => !space.isRelationship).toList();
        return ScreenBody(
          children: [
            const BalanceHero(),
            if (invites.isNotEmpty) ...[
              const SectionGap(),
              SectionHeader(title: l10n.contextInvitations),
              SaldaCardList(
                children: [
                  for (final invite in invites) _HomeInviteCard(invite: invite),
                ],
              ),
            ],
            const SectionGap(),
            if (relationships.isEmpty && groups.isEmpty)
              EmptyState(
                icon: Icons.groups_outlined,
                title: l10n.homeNoSpacesTitle,
                body: l10n.homeNoSpacesBody,
              )
            else ...[
              if (relationships.isNotEmpty) ...[
                SectionHeader(title: l10n.relationshipsTitle),
                SaldaCardList(
                  children: [
                    for (final space in relationships) SpaceRow(space: space),
                  ],
                ),
              ],
              if (relationships.isNotEmpty && groups.isNotEmpty)
                const SectionGap(),
              if (groups.isNotEmpty) ...[
                SectionHeader(title: l10n.groupsTitle),
                SaldaCardList(
                  children: [
                    for (final space in groups) SpaceRow(space: space),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 72),
          ],
        );
      },
    );
  }
}

class _HomeInviteCard extends ConsumerStatefulWidget {
  const _HomeInviteCard({required this.invite});
  final SpaceInvite invite;

  @override
  ConsumerState<_HomeInviteCard> createState() => _HomeInviteCardState();
}

class _HomeInviteCardState extends ConsumerState<_HomeInviteCard> {
  var busy = false;

  Future<void> resolve(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(spacesRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TokenSpacing.lg,
        TokenSpacing.md,
        TokenSpacing.md,
        TokenSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpaceInviteTitle(invite: widget.invite),
                const SizedBox(height: 3),
                StatusBadge(
                  l10n.contextInvitationPending,
                  tone: BadgeTone.pending,
                ),
              ],
            ),
          ),
          const SizedBox(width: TokenSpacing.sm),
          IconButton(
            tooltip: l10n.spaceInviteReject,
            onPressed: busy
                ? null
                : () => resolve(() => repo.rejectInvite(widget.invite.id)),
            icon: const Icon(Icons.close, size: 20),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => resolve(() => repo.acceptInvite(widget.invite)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.lg),
            ),
            child: Text(l10n.spaceInviteAccept),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCreateContextSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: Text(l10n.relationshipCreate),
                subtitle: Text(l10n.relationshipCreateHelp),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/home/relationship/new');
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: Text(l10n.groupCreate),
                subtitle: Text(l10n.groupCreateHelp),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showCreateSpaceDialog(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );

/// Aviso al INVITADO que aún no ha elegido nombre (ADR-034). Sin nombre no
/// puede participar: es lo único que necesita, sin crear ninguna cuenta.
class _GuestNameBanner extends ConsumerWidget {
  const _GuestNameBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentAppUserProvider);
    if (user == null || !user.isAnonymous) return const SizedBox.shrink();
    final identity = ref.watch(myGuestIdentityProvider);
    // Solo cuando SABEMOS que no hay identidad (no mientras carga).
    if (identity.isLoading || identity.value != null) {
      return const SizedBox.shrink();
    }
    return Notice(
      icon: Icons.person_pin_circle_outlined,
      message: l10n.guestNameBannerTitle,
      actionLabel: l10n.guestNameBannerAction,
      onAction: () => context.push('/home/guest-name'),
    );
  }
}

/// Aviso de perfil público pendiente (P2): las cuentas completas sin perfil
/// lo crean desde aquí (cubre registro por email, Google y conversiones de
/// invitado por igual; la pantalla propone el username automáticamente).
class _ProfileBanner extends ConsumerWidget {
  const _ProfileBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isFullAccount =
        ref.watch(currentAppUserProvider)?.isFullAccount ?? false;
    final profile = ref.watch(myProfileProvider);
    // Solo cuando SABEMOS que no hay perfil (no mientras carga).
    if (!isFullAccount || profile.isLoading || profile.value != null) {
      return const SizedBox.shrink();
    }
    return Notice(
      icon: Icons.account_circle_outlined,
      message: l10n.profileBannerTitle,
      actionLabel: l10n.profileBannerAction,
      onAction: () => context.push('/home/profile'),
    );
  }
}

/// Banner de borrador recuperado (draft persistente del wizard, spec §4.3).
class _DraftBanner extends ConsumerWidget {
  const _DraftBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(savedDraftProvider).value;
    final alreadyEditing = ref.watch(reviewDraftProvider) != null;
    final fullAccount =
        ref.watch(currentAppUserProvider)?.isFullAccount ?? false;
    if (saved == null || alreadyEditing) return const SizedBox.shrink();

    // Dos acciones (descartar / retomar), así que no encaja en `Notice`;
    // conserva su forma pero con la superficie y el ritmo del sistema.
    return Material(
      color: context.salda.primaryMuted,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TokenLayout.screenMargin,
          TokenSpacing.sm,
          TokenSpacing.sm,
          TokenSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: context.salda.primary,
            ),
            const SizedBox(width: TokenSpacing.md),
            Expanded(
              child: Text(
                l10n.draftResumeTitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(draftStoreProvider).clear();
                ref.invalidate(savedDraftProvider);
              },
              child: Text(l10n.draftDiscard),
            ),
            if (fullAccount)
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TokenSpacing.lg,
                  ),
                ),
                onPressed: () async {
                  if (ref.read(pendingSpaceLinkProvider) == null) {
                    final spaces =
                        ref
                            .read(mySpacesProvider)
                            .value
                            ?.where((space) => space.isActive)
                            .toList() ??
                        const <Space>[];
                    final selected = await showDialog<Space>(
                      context: context,
                      builder: (dialogContext) => SimpleDialog(
                        title: Text(l10n.contextChoose),
                        children: [
                          for (final space in spaces)
                            SimpleDialogOption(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, space),
                              child: SpaceTitleText(
                                spaceId: space.id,
                                storedName: space.name,
                              ),
                            ),
                        ],
                      ),
                    );
                    if (selected == null || !context.mounted) return;
                    ref
                        .read(pendingSpaceLinkProvider.notifier)
                        .set(selected.id, selected.name, selected.kind);
                  }
                  ref.read(reviewDraftProvider.notifier).loadFrom(saved);
                  if (context.mounted) context.push('/home/review');
                },
                child: Text(l10n.draftResume),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionsList extends ConsumerWidget {
  const _SessionsList({required this.sessions});

  final List<SessionSummary> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Archivadas al final (spec §4.1).
    final visible = [
      ...sessions.where((s) => s.status != SessionStatus.archived),
      ...sessions.where((s) => s.status == SessionStatus.archived),
    ];
    final owedToMe = sessions
        .where(
          (s) => s.status == SessionStatus.open && s.myOutstanding.cents > 0,
        )
        .fold(0, (a, s) => a + s.myOutstanding.cents);
    final iOwe = sessions
        .where(
          (s) => s.status == SessionStatus.open && s.myOutstanding.cents < 0,
        )
        .fold(0, (a, s) => a - s.myOutstanding.cents);

    return ListView(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      children: [
        if (ref.watch(currentAppUserProvider)?.isFullAccount ?? false) ...[
          const EconomicHomeCard(),
          const SizedBox(height: TokenSpacing.md),
        ] else if (owedToMe > 0 || iOwe > 0) ...[
          _TotalsHeader(owedToMe: Money(owedToMe), iOwe: Money(iOwe)),
          const SizedBox(height: TokenSpacing.md),
        ],
        for (final session in visible)
          _SessionCard(session: session, l10n: l10n),
        const SizedBox(height: 88), // aire para el FAB
      ],
    );
  }
}

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.owedToMe, required this.iOwe});

  final Money owedToMe;
  final Money iOwe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget cell(String label, Money amount) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(
            formatMoney(amount),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        child: Row(
          children: [
            cell(l10n.summaryOwedToMe, owedToMe),
            Container(
              width: 1,
              height: 36,
              color: theme.colorScheme.outlineVariant,
            ),
            cell(l10n.summaryIOwe, iOwe),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.l10n});

  final SessionSummary session;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final archived = session.status == SessionStatus.archived;
    return Opacity(
      opacity: archived ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(TokenRadius.card),
          onTap: () => context.push('/home/session/${session.id}'),
          child: Padding(
            padding: const EdgeInsets.all(TokenSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      formatMoney(session.grandTotal),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TokenSpacing.xs),
                Wrap(
                  spacing: TokenSpacing.sm,
                  runSpacing: TokenSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.sessionPeople(session.participantsCount),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (session.status == SessionStatus.closed)
                      _chip(theme, l10n.statusClosed, Icons.lock_outline),
                    if (archived)
                      _chip(theme, l10n.statusArchived, Icons.archive_outlined),
                  ],
                ),
                const SizedBox(height: TokenSpacing.sm),
                SettlementProgressBar(
                  progress: session.settlementProgress,
                  semanticLabel: l10n.settlementProgressSemantics,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, IconData icon) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 2),
      Text(label, style: theme.textTheme.labelSmall),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: TokenSpacing.lg),
            Text(l10n.sessionsEmptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: TokenSpacing.xs),
            Text(
              l10n.sessionsEmptyBody,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton del historial (spec §3.8): tarjetas fantasma, nunca spinner.
class _SessionsSkeleton extends StatelessWidget {
  const _SessionsSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      children: [
        for (var i = 0; i < 4; i++)
          Card(
            margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(TokenSpacing.lg),
              child: Column(
                children: [
                  Container(height: 16, color: color),
                  const SizedBox(height: TokenSpacing.sm),
                  Container(height: 10, color: color),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Indicador global de solicitudes de vinculación (M4).
///
/// Solo aparece si hay alguna: un contador a cero es ruido. La consulta es un
/// collection group acotado por `spaceOwnerUid`, así que quien no es
/// anfitrión no puede enumerar nada.
class _ManualLinkBadge extends ConsumerWidget {
  const _ManualLinkBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(myPendingManualLinksProvider).value ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();

    // Agrupadas por espacio: al anfitrión le importa dónde tiene que decidir.
    final bySpace = <String, int>{};
    for (final request in pending) {
      bySpace[request.spaceId] = (bySpace[request.spaceId] ?? 0) + 1;
    }
    return IconButton(
      tooltip: l10n.manualLinkRequestsTitle,
      onPressed: () => _open(context, bySpace),
      icon: Badge.count(
        count: pending.length,
        child: const Icon(Icons.person_add_alt),
      ),
    );
  }

  void _open(BuildContext context, Map<String, int> bySpace) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.manualLinkRequestsTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              subtitle: Text(l10n.manualLinkRequestHelp),
            ),
            for (final entry in bySpace.entries)
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(l10n.manualLinkPendingInSpace(entry.value)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/home/spaces/${entry.key}');
                },
              ),
          ],
        ),
      ),
    );
  }
}
