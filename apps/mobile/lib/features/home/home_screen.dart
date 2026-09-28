import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/action_banner.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/states.dart';
import '../../core/ui/surfaces.dart';
import '../../core/ui/wordmark.dart';
import '../../core/utils/money_format.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/data/auth_repository.dart';
import '../auth/data/guest_identity_repository.dart';
import '../spaces/data/manual_link_repository.dart';
import '../economy/data/economic_repository.dart';
import '../economy/domain/economic_models.dart';
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
import '../spaces/presentation/space_title_text.dart';
import '../spaces/presentation/spaces_screen.dart';
import 'balance_hero.dart';
import '../profile/presentation/profile_avatar.dart';
import '../scan/presentation/scan_flow.dart';
import 'presentation/home_space_row.dart';

/// Inicio: centro operativo. La jerarquía es deliberada —balance, acción y
/// contextos— y no una sucesión de tarjetas del mismo peso.
///
/// La barra superior es intencionadamente compacta: wordmark e identidad.
/// Las acciones viven en el contexto donde se usan, sin menú de desbordamiento.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentAppUserProvider);
    final fullAccount = user?.isFullAccount ?? false;
    final guestDisplayName = user?.isAnonymous == true
        ? ref.watch(myGuestIdentityProvider).value?.displayName
        : null;
    // Un INVITADO con nombre PARTICIPA (ADR-034): ve sus grupos y sus
    // invitaciones igual que una cuenta. Lo que sigue siendo exclusivo de
    // una cuenta es CREAR contextos, que es lo que gobierna el FAB.
    final participates = fullAccount || ref.watch(isOperationalGuestProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: TokenLayout.screenMargin,
        title: const SaldaWordmark(),
        actions: [
          // Unirse por enlace no exige cuenta: es la puerta de entrada del
          // invitado (ADR-035), así que está siempre visible.
          IconButton(
            tooltip: l10n.accountHubTitle,
            onPressed: () => context.push('/home/account'),
            icon: ProfileAvatar(
              seed: user?.uid ?? '',
              displayName: guestDisplayName ?? user?.displayName ?? '',
              radius: 16,
            ),
          ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref, fullAccount: fullAccount),
        icon: const Icon(Icons.add, size: 20),
        label: Text(l10n.homeAdd),
      ),
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

class _ContextsHome extends ConsumerStatefulWidget {
  const _ContextsHome();

  @override
  ConsumerState<_ContextsHome> createState() => _ContextsHomeState();
}

class _ContextsHomeState extends ConsumerState<_ContextsHome> {
  static const _searchThreshold = 10;
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spaces = ref.watch(mySpacesProvider);
    final invites = ref.watch(mySpaceInvitesProvider);
    final manualLinks = ref.watch(myPendingManualLinksProvider);
    final economy = ref.watch(participantEconomicOverviewProvider);
    final all = spaces.value ?? const <Space>[];
    final active = [
      for (final space in all)
        if (space.isActive) space,
    ];
    final archived = [
      for (final space in all)
        if (!space.isActive) space,
    ];
    // El umbral 10 evita un control superfluo en el caso cotidiano y mantiene
    // la lista de 50+ contextos navegable sin otra pantalla intermedia.
    final pendingBySpace = _pendingBySpace(manualLinks.value ?? const []);
    final balancesBySpace = economy.value == null
        ? const <String, Map<String, int>>{}
        : _balancesBySpace(economy.value!, active);
    final inviteRows = invites.value ?? const <SpaceInvite>[];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            TokenLayout.screenMargin,
            TokenSpacing.lg,
            TokenLayout.screenMargin,
            0,
          ),
          sliver: const SliverToBoxAdapter(child: BalanceHero()),
        ),
        if (invites.isLoading || manualLinks.isLoading)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              TokenLayout.screenMargin,
              TokenSpacing.md,
              TokenLayout.screenMargin,
              0,
            ),
            sliver: SliverToBoxAdapter(child: SkeletonList(rows: 1)),
          ),
        if (invites.hasError || manualLinks.hasError)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              TokenLayout.screenMargin,
              TokenSpacing.md,
              TokenLayout.screenMargin,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: ErrorStateView(
                message: l10n.spacesLoadError,
                onRetry: () {
                  ref.invalidate(mySpaceInvitesProvider);
                  ref.invalidate(myPendingManualLinksProvider);
                },
              ),
            ),
          ),
        if (inviteRows.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              TokenLayout.screenMargin,
              TokenSpacing.lg,
              TokenLayout.screenMargin,
              TokenSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(title: l10n.contextInvitations),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: TokenLayout.screenMargin,
            ),
            sliver: SliverList.builder(
              itemCount: inviteRows.length,
              itemBuilder: (context, index) =>
                  _HomeInviteCard(invite: inviteRows[index]),
            ),
          ),
        ],
        if (spaces.isLoading)
          const SliverPadding(
            padding: EdgeInsets.all(TokenLayout.screenMargin),
            sliver: SliverToBoxAdapter(child: SkeletonList(rows: 3)),
          )
        else if (spaces.hasError)
          SliverPadding(
            padding: const EdgeInsets.all(TokenLayout.screenMargin),
            sliver: SliverToBoxAdapter(
              child: ErrorStateView(
                message: l10n.spacesLoadError,
                onRetry: () => ref.invalidate(mySpacesProvider),
              ),
            ),
          )
        else if (active.isEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.all(TokenLayout.screenMargin),
            sliver: SliverToBoxAdapter(
              child: archived.isEmpty
                  ? EmptyState(
                      icon: Icons.groups_outlined,
                      title: l10n.homeNoSpacesTitle,
                      body: l10n.homeNoSpacesBody,
                    )
                  : ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: Text(l10n.spacesArchivedSection(archived.length)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/home/spaces'),
                    ),
            ),
          ),
        ] else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              TokenLayout.screenMargin,
              TokenSpacing.lg,
              TokenLayout.screenMargin,
              TokenSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(title: l10n.spacesTitle),
            ),
          ),
          if (active.length >= _searchThreshold || _query.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: TokenLayout.screenMargin,
              ),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.homeSearchSpaces,
                  ),
                ),
              ),
            ),
          if (_query.trim().isEmpty)
            _HomeSpaceSliver(
              spaces: active,
              balancesBySpace: balancesBySpace,
              pendingBySpace: pendingBySpace,
              attentionKnown: manualLinks.hasValue,
            )
          else
            _HomeSearchSpaceSliver(
              spaces: active,
              query: _query,
              balancesBySpace: balancesBySpace,
              pendingBySpace: pendingBySpace,
              attentionKnown: manualLinks.hasValue,
            ),
          if (archived.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                TokenLayout.screenMargin,
                TokenSpacing.md,
                TokenLayout.screenMargin,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(l10n.spacesArchivedSection(archived.length)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/home/spaces'),
                ),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 104)),
      ],
    );
  }
}

class _HomeSpaceSliver extends StatelessWidget {
  const _HomeSpaceSliver({
    required this.spaces,
    required this.balancesBySpace,
    required this.pendingBySpace,
    required this.attentionKnown,
  });

  final List<Space> spaces;
  final Map<String, Map<String, int>> balancesBySpace;
  final Map<String, int> pendingBySpace;
  final bool attentionKnown;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      TokenLayout.screenMargin,
      TokenSpacing.sm,
      TokenLayout.screenMargin,
      0,
    ),
    sliver: SliverList.builder(
      itemCount: spaces.length,
      itemBuilder: (context, index) => _homeSpaceRow(
        spaces[index],
        balancesBySpace,
        pendingBySpace,
        attentionKnown,
      ),
    ),
  );
}

/// Se monta únicamente durante una búsqueda: es entonces cuando resolver los
/// títulos de relaciones para todos los candidatos es necesario y esperado.
class _HomeSearchSpaceSliver extends ConsumerWidget {
  const _HomeSearchSpaceSliver({
    required this.spaces,
    required this.query,
    required this.balancesBySpace,
    required this.pendingBySpace,
    required this.attentionKnown,
  });

  final List<Space> spaces;
  final String query;
  final Map<String, Map<String, int>> balancesBySpace;
  final Map<String, int> pendingBySpace;
  final bool attentionKnown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final normalized = query.trim().toLowerCase();
    final matched = [
      for (final space in spaces)
        if (spaceTitleLabel(
          ref.watch(spaceTitleProvider(space.id)),
          l10n,
          space.name,
        ).toLowerCase().contains(normalized))
          space,
    ];
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        TokenLayout.screenMargin,
        TokenSpacing.sm,
        TokenLayout.screenMargin,
        0,
      ),
      sliver: matched.isEmpty
          ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(TokenLayout.screenMargin),
                child: Text(l10n.homeNoSearchResults),
              ),
            )
          : SliverList.builder(
              itemCount: matched.length,
              itemBuilder: (context, index) => _homeSpaceRow(
                matched[index],
                balancesBySpace,
                pendingBySpace,
                attentionKnown,
              ),
            ),
    );
  }
}

Widget _homeSpaceRow(
  Space space,
  Map<String, Map<String, int>> balancesBySpace,
  Map<String, int> pendingBySpace,
  bool attentionKnown,
) => HomeSpaceRow(
  space: space,
  currencyBalances: balancesBySpace[space.id] ?? const {},
  pendingManualLinks: pendingBySpace[space.id] ?? 0,
  attentionKnown: attentionKnown,
);

Map<String, int> _pendingBySpace(List<ManualLinkRequest> requests) {
  final result = <String, int>{};
  for (final request in requests) {
    if (request.isPending && request.spaceId.isNotEmpty) {
      result.update(request.spaceId, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return result;
}

/// Conserva [EconomicOverview.withinSpace]: los pagos se asignan a entradas
/// concretas, así que agrupar balances ya consolidados en un único pase
/// perdería esa pertenencia. La optimización requiere una proyección por
/// espacio autoritativa, no una suma local aproximada.
Map<String, Map<String, int>> _balancesBySpace(
  EconomicOverview overview,
  List<Space> spaces,
) => {
  for (final space in spaces)
    space.id: _currencyBalances(overview.withinSpace(space.id)),
};

Map<String, int> _currencyBalances(EconomicOverview overview) {
  final result = <String, int>{};
  for (final balance in overview.balances) {
    if (balance.signedOutstandingCents == 0) continue;
    final signed = balance.debtorUid == overview.viewerUid
        ? -balance.outstanding.cents
        : balance.outstanding.cents;
    result.update(
      balance.currency,
      (value) => value + signed,
      ifAbsent: () => signed,
    );
  }
  result.removeWhere((_, value) => value == 0);
  return result;
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
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).spaceActionError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(spacesRepositoryProvider);
    return ActionBanner(
      padding: const EdgeInsets.fromLTRB(
        TokenSpacing.lg,
        TokenSpacing.md,
        TokenSpacing.lg,
        TokenSpacing.md,
      ),
      title: SpaceInviteTitle(invite: widget.invite),
      badge: StatusBadge(
        l10n.contextInvitationPending,
        tone: BadgeTone.pending,
      ),
      actions: [
        // Rechazar deja de ser una «X» sin rótulo: con dos acciones en la
        // misma línea, un icono desnudo obliga a adivinar cuál es cuál.
        TextButton(
          onPressed: busy
              ? null
              : () => resolve(() => repo.rejectInvite(widget.invite.id)),
          child: Text(l10n.spaceInviteReject),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () => resolve(() => repo.acceptInvite(widget.invite)),
          child: Text(l10n.spaceInviteAccept),
        ),
      ],
    );
  }
}

Future<void> _showAddSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool fullAccount,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fullAccount)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(l10n.homeAddExpense),
              onTap: () async {
                Navigator.pop(sheetContext);
                final spaces = ref.read(mySpacesProvider);
                if (!spaces.hasValue) {
                  final message = spaces.hasError
                      ? l10n.homeSpacesUnavailable
                      : l10n.homeSpacesLoading;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                  return;
                }
                final active = spaces.requireValue
                    .where((space) => space.isActive)
                    .toList();
                if (active.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.homeNoActiveSpaces)),
                  );
                  return;
                }
                final selected = active.length == 1
                    ? active.single
                    : await showDialog<Space>(
                        context: context,
                        builder: (dialogContext) => SimpleDialog(
                          title: Text(l10n.contextChoose),
                          children: [
                            for (final space in active)
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
                showScanEntrySheet(context, ref);
              },
            ),
          if (fullAccount)
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: Text(l10n.homeAddRelationship),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/home/relationship/new');
              },
            ),
          if (fullAccount)
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: Text(l10n.homeAddGroup),
              onTap: () {
                Navigator.pop(sheetContext);
                showCreateSpaceDialog(context, ref);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_link_outlined),
            title: Text(l10n.homeAddJoin),
            onTap: () {
              Navigator.pop(sheetContext);
              context.push('/join');
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

    // Dos acciones (descartar / retomar), asi que no encaja en `Notice`:
    // usa el aviso con acciones, que las apila cuando no caben.
    return Material(
      color: context.salda.primaryMuted,
      child: ActionBanner(
        padding: const EdgeInsets.fromLTRB(
          TokenLayout.screenMargin,
          TokenSpacing.sm,
          TokenLayout.screenMargin,
          TokenSpacing.sm,
        ),
        icon: Icons.receipt_long_outlined,
        title: Text(l10n.draftResumeTitle),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(draftStoreProvider).clear();
              ref.invalidate(savedDraftProvider);
            },
            child: Text(l10n.draftDiscard),
          ),
          if (fullAccount)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
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
