import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/data/auth_repository.dart';
import '../auth/data/guest_identity_repository.dart';
import '../economy/presentation/economic_overview_screen.dart';
import '../profile/data/profile_repository.dart';
import '../review/application/draft_store.dart';
import '../review/application/review_draft.dart';
import '../sessions/application/session_providers.dart';
import '../sessions/domain/session_models.dart';
import '../sessions/presentation/settlement_progress_bar.dart';
import '../spaces/data/spaces_repository.dart';
import '../spaces/domain/space_models.dart';
import '../spaces/presentation/space_avatar.dart';
import '../spaces/presentation/spaces_screen.dart';

/// Historial de sesiones (RF-80/82) + FAB de escaneo.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(Brand.appName),
        actions: [
          // GUEST (ADR-034): participa, así que ve cronología y balances;
          // el resto de accesos siguen siendo de cuenta.
          if (ref.watch(isOperationalGuestProvider)) ...[
            IconButton(
              tooltip: l10n.activityTitle,
              onPressed: () => context.push('/home/activity'),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: l10n.economyTitle,
              onPressed: () => context.push('/home/economy'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          ],
          if (ref.watch(currentAppUserProvider)?.isFullAccount ?? false) ...[
            IconButton(
              tooltip: l10n.activityTitle,
              onPressed: () => context.push('/home/activity'),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: l10n.economyTitle,
              onPressed: () => context.push('/home/economy'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
            IconButton(
              tooltip: l10n.historyTitle,
              onPressed: () => context.push('/home/history'),
              icon: const Icon(Icons.history_outlined),
            ),
            IconButton(
              tooltip: l10n.friendsTitle,
              onPressed: () => context.push('/home/friends'),
              icon: const Icon(Icons.people_outline),
            ),
          ],
          IconButton(
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push('/home/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          const _GuestNameBanner(),
          const _ProfileBanner(),
          const _DraftBanner(),
          Expanded(
            child: fullAccount
                ? const _ContextsHome()
                : const _AccountRequiredHome(),
          ),
        ],
      ),
      floatingActionButton: fullAccount
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateContextSheet(context, ref),
              icon: const Icon(Icons.add),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_person_outlined, size: 64),
            const SizedBox(height: TokenSpacing.md),
            Text(l10n.contextAccountRequired, textAlign: TextAlign.center),
            const SizedBox(height: TokenSpacing.md),
            FilledButton(
              onPressed: () => context.push('/register'),
              child: Text(l10n.authProtectGuestAction),
            ),
          ],
        ),
      ),
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
      loading: () => const _SessionsSkeleton(),
      error: (_, _) => Center(child: Text(l10n.spacesLoadError)),
      data: (all) {
        final active = all.where((space) => space.isActive).toList();
        final relationships = active
            .where((space) => space.isRelationship)
            .toList();
        final groups = active.where((space) => !space.isRelationship).toList();
        return ListView(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          children: [
            const EconomicHomeCard(),
            if (invites.isNotEmpty) ...[
              const SizedBox(height: TokenSpacing.lg),
              Text(
                l10n.contextInvitations,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: TokenSpacing.sm),
              for (final invite in invites) _HomeInviteCard(invite: invite),
            ],
            const SizedBox(height: TokenSpacing.lg),
            _ContextSection(
              title: l10n.relationshipsTitle,
              empty: l10n.relationshipsEmpty,
              spaces: relationships,
              icon: Icons.person_outline,
            ),
            const SizedBox(height: TokenSpacing.lg),
            _ContextSection(
              title: l10n.groupsTitle,
              empty: l10n.groupsEmpty,
              spaces: groups,
              icon: Icons.groups_outlined,
            ),
            const SizedBox(height: 88),
          ],
        );
      },
    );
  }
}

class _ContextSection extends StatelessWidget {
  const _ContextSection({
    required this.title,
    required this.empty,
    required this.spaces,
    required this.icon,
  });

  final String title;
  final String empty;
  final List<Space> spaces;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: TokenSpacing.sm),
      if (spaces.isEmpty)
        Card(
          child: ListTile(leading: Icon(icon), title: Text(empty)),
        )
      else
        for (final space in spaces)
          Card(
            child: ListTile(
              leading: SpaceAvatar(space: space),
              title: Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/home/spaces/${space.id}'),
            ),
          ),
    ],
  );
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
    return Card(
      child: ListTile(
        title: Text(
          widget.invite.spaceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(l10n.contextInvitationPending),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: l10n.spaceInviteReject,
              onPressed: busy
                  ? null
                  : () => resolve(() => repo.rejectInvite(widget.invite.id)),
              icon: const Icon(Icons.close),
            ),
            IconButton.filled(
              tooltip: l10n.spaceInviteAccept,
              onPressed: busy
                  ? null
                  : () => resolve(() => repo.acceptInvite(widget.invite)),
              icon: const Icon(Icons.check),
            ),
          ],
        ),
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
    return MaterialBanner(
      leading: const Icon(Icons.person_pin_circle_outlined),
      content: Text(l10n.guestNameBannerTitle),
      actions: [
        FilledButton.tonal(
          onPressed: () => context.push('/home/guest-name'),
          child: Text(l10n.guestNameBannerAction),
        ),
      ],
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
    return MaterialBanner(
      leading: const Icon(Icons.account_circle_outlined),
      content: Text(l10n.profileBannerTitle),
      actions: [
        FilledButton.tonal(
          onPressed: () => context.push('/home/profile'),
          child: Text(l10n.profileBannerAction),
        ),
      ],
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

    return MaterialBanner(
      leading: const Icon(Icons.receipt_long_outlined),
      content: Text(l10n.draftResumeTitle),
      actions: [
        TextButton(
          onPressed: () async {
            await ref.read(draftStoreProvider).clear();
            ref.invalidate(savedDraftProvider);
          },
          child: Text(l10n.draftDiscard),
        ),
        if (fullAccount)
          FilledButton.tonal(
            onPressed: () async {
              if (ref.read(pendingSpaceLinkProvider) == null) {
                final spaces = ref.read(mySpacesProvider).value
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
                          child: Text(space.name),
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
