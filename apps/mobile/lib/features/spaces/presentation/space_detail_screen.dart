import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../friends/data/friendship_repository.dart';
import '../../friends/domain/friendship.dart';
import '../../economy/presentation/space_economic_summary.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../../scan/presentation/scan_flow.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';
import 'space_avatar.dart';

/// Detalle de un espacio (P4): miembros, invitaciones, tickets vinculados y
/// acciones según rol. La membresía es social: nada de lo que se haga aquí
/// (salir, expulsar, archivar) toca tickets, balances ni pagos históricos.
class SpaceDetailScreen extends ConsumerStatefulWidget {
  const SpaceDetailScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<SpaceDetailScreen> createState() => _SpaceDetailScreenState();
}

class _SpaceDetailScreenState extends ConsumerState<SpaceDetailScreen> {
  var _scanning = false;

  Future<void> _guarded(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spaceAsync = ref.watch(spaceProvider(widget.spaceId));
    final space = spaceAsync.value;
    final members =
        ref.watch(spaceMembersProvider(widget.spaceId)).value ?? const [];
    final myUid = ref.watch(currentUserIdFromSpacesProvider);
    final amOwner = space?.ownerUid == myUid;
    final repo = ref.read(spacesRepositoryProvider);

    if (spaceAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (space == null) {
      // Expulsado, ha salido o el espacio ya no es visible.
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.spaceGone)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(space.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) => switch (action) {
              'edit' => _editName(space),
              'archive' => _guarded(
                () => repo.setStatus(space.id, SpaceStatus.archived),
              ),
              'reactivate' => _guarded(
                () => repo.setStatus(space.id, SpaceStatus.active),
              ),
              'leave' => _leave(),
              _ => null,
            },
            itemBuilder: (_) => [
              if (amOwner) ...[
                PopupMenuItem(value: 'edit', child: Text(l10n.spaceEditName)),
                if (space.isActive)
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(l10n.spaceArchive),
                  )
                else
                  PopupMenuItem(
                    value: 'reactivate',
                    child: Text(l10n.spaceReactivate),
                  ),
              ] else
                PopupMenuItem(value: 'leave', child: Text(l10n.spaceLeave)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        children: [
          Row(
            children: [
              SpaceAvatar(space: space, radius: 28),
              const SizedBox(width: TokenSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(space.name, style: theme.textTheme.titleLarge),
                    Text(
                      l10n.spaceMembersCount(members.length),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!space.isActive)
                Chip(
                  label: Text(l10n.statusArchived),
                  avatar: const Icon(Icons.archive_outlined, size: 16),
                ),
            ],
          ),
          const SizedBox(height: TokenSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.spaceMembersTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (amOwner && space.isActive)
                TextButton.icon(
                  onPressed: () => _showInviteSheet(space),
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: Text(l10n.spaceInviteAction),
                ),
            ],
          ),
          Card(
            child: Column(
              children: [
                for (final member in members)
                  _MemberTile(
                    spaceId: space.id,
                    spaceActive: space.isActive,
                    member: member,
                    isOwnerMember: member.uid == space.ownerUid,
                    amOwner: amOwner,
                    isMe: member.uid == myUid,
                    onTransfer: () => _guarded(
                      () => repo.transferOwnership(space.id, member.uid),
                    ),
                    onRemove: () =>
                        _guarded(() => repo.removeMember(space.id, member.uid)),
                  ),
              ],
            ),
          ),
          if (amOwner) _PendingInvites(spaceId: space.id),
          const SizedBox(height: TokenSpacing.xl),
          SpaceEconomicSummary(spaceId: space.id),
          const SizedBox(height: TokenSpacing.xl),
          Text(l10n.spaceTicketsTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: TokenSpacing.sm),
          _SpaceTickets(spaceId: space.id),
          const SizedBox(height: 88),
        ],
      ),
      floatingActionButton: space.isActive
          ? FloatingActionButton.extended(
              onPressed: _scanning
                  ? null
                  : () {
                      // El próximo ticket guardado se vincula a ESTE espacio
                      // (lo consume el controlador de creación).
                      ref
                          .read(pendingSpaceLinkProvider.notifier)
                          .set(space.id, space.name);
                      showScanEntrySheet(
                        context,
                        ref,
                        onBusy: (busy) {
                          if (mounted) setState(() => _scanning = busy);
                        },
                      );
                    },
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(l10n.spaceAddTicket),
            )
          : null,
    );
  }

  Future<void> _editName(Space space) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: space.name);
    final emoji = TextEditingController(text: space.avatarEmoji ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.spaceEditName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              decoration: InputDecoration(labelText: l10n.spaceNameLabel),
            ),
            TextField(
              controller: emoji,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: l10n.spaceEmojiLabel,
                hintText: '🏖️',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.length < 2) return;
              Navigator.of(dialogContext).pop();
              _guarded(
                () => ref
                    .read(spacesRepositoryProvider)
                    .rename(space.id, name, avatarEmoji: emoji.text.trim()),
              );
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.spaceLeave),
        content: Text(l10n.spaceLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.spaceLeave),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final router = GoRouter.of(context);
    await _guarded(
      () => ref.read(spacesRepositoryProvider).leave(widget.spaceId),
    );
    if (mounted) router.go('/home/spaces');
  }

  Future<void> _showInviteSheet(Space space) async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _InviteFriendsSheet(space: space, l10n: l10n),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.spaceId,
    required this.spaceActive,
    required this.member,
    required this.isOwnerMember,
    required this.amOwner,
    required this.isMe,
    required this.onTransfer,
    required this.onRemove,
  });

  final String spaceId;
  final bool spaceActive;
  final SpaceMember member;

  /// Derivado de space.ownerUid (el rol no se persiste).
  final bool isOwnerMember;
  final bool amOwner;
  final bool isMe;
  final VoidCallback onTransfer;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(publicProfileProvider(member.uid)).value;
    return ListTile(
      leading: profile == null
          ? const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16))
          : ProfileAvatar(
              seed: member.uid,
              displayName: profile.displayName,
              radius: 16,
            ),
      title: Text(
        profile?.displayName ?? '…',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isOwnerMember
            ? l10n.spaceOwnerBadge
            : profile == null
            ? ''
            : '@${profile.username}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: amOwner && !isMe && !isOwnerMember && spaceActive
          ? PopupMenuButton<String>(
              onSelected: (action) => switch (action) {
                'transfer' => _confirm(
                  context,
                  l10n.spaceTransferTitle,
                  l10n.spaceTransferBody(profile?.displayName ?? ''),
                  onTransfer,
                ),
                'remove' => _confirm(
                  context,
                  l10n.spaceRemoveMemberTitle,
                  l10n.spaceRemoveMemberBody(profile?.displayName ?? ''),
                  onRemove,
                ),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'transfer',
                  child: Text(l10n.spaceTransferTitle),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(l10n.spaceRemoveMemberTitle),
                ),
              ],
            )
          : null,
      onTap: () => context.push('/home/person/${member.uid}'),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String body,
    VoidCallback action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (confirmed == true) action();
  }
}

class _PendingInvites extends ConsumerWidget {
  const _PendingInvites({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final invites = ref.watch(spaceInvitesProvider(spaceId)).value ?? const [];
    if (invites.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: TokenSpacing.md),
        Text(l10n.spacePendingInvites, style: theme.textTheme.titleSmall),
        Card(
          child: Column(
            children: [
              for (final invite in invites) _PendingInviteTile(invite: invite),
            ],
          ),
        ),
      ],
    );
  }
}

class _PendingInviteTile extends ConsumerWidget {
  const _PendingInviteTile({required this.invite});

  final SpaceInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(publicProfileProvider(invite.toUid)).value;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.schedule_outlined, size: 20),
      title: Text(profile?.displayName ?? '…'),
      trailing: IconButton(
        tooltip: l10n.spaceInviteCancel,
        icon: const Icon(Icons.close, size: 18),
        onPressed: () =>
            ref.read(spacesRepositoryProvider).cancelInvite(invite.id),
      ),
    );
  }
}

/// Invitar priorizando AMIGOS (P3); el modelo no acopla amistad y membresía,
/// así que cualquier flujo futuro (invitar por username) encaja sin cambios.
class _InviteFriendsSheet extends ConsumerWidget {
  const _InviteFriendsSheet({required this.space, required this.l10n});

  final Space space;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendships = ref.watch(friendshipsProvider).value ?? const [];
    final myUid = ref.watch(currentUserIdFromSpacesProvider);
    final members = ref.watch(spaceMembersProvider(space.id)).value ?? const [];
    final invites = ref.watch(spaceInvitesProvider(space.id)).value ?? const [];
    final memberUids = {for (final m in members) m.uid};
    final invitedUids = {for (final i in invites) i.toUid};
    final friends = [
      for (final f in friendships)
        if (f.status == FriendshipStatus.friends) f.otherUid(myUid),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.spaceInviteSheetTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TokenSpacing.sm),
            if (friends.isEmpty)
              Padding(
                padding: const EdgeInsets.all(TokenSpacing.lg),
                child: Text(
                  l10n.spaceInviteNoFriends,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final friendUid in friends)
                      _InviteCandidateTile(
                        space: space,
                        friendUid: friendUid,
                        alreadyMember: memberUids.contains(friendUid),
                        alreadyInvited: invitedUids.contains(friendUid),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InviteCandidateTile extends ConsumerWidget {
  const _InviteCandidateTile({
    required this.space,
    required this.friendUid,
    required this.alreadyMember,
    required this.alreadyInvited,
  });

  final Space space;
  final String friendUid;
  final bool alreadyMember;
  final bool alreadyInvited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(publicProfileProvider(friendUid)).value;
    return ListTile(
      leading: profile == null
          ? const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16))
          : ProfileAvatar(
              seed: friendUid,
              displayName: profile.displayName,
              radius: 16,
            ),
      title: Text(profile?.displayName ?? '…'),
      subtitle: profile == null ? null : Text('@${profile.username}'),
      trailing: alreadyMember
          ? Text(l10n.spaceAlreadyMember)
          : alreadyInvited
          ? Text(l10n.spaceAlreadyInvited)
          : FilledButton.tonal(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(spacesRepositoryProvider)
                      .invite(space.id, space.name, friendUid);
                } on Object {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.spaceActionError)),
                  );
                }
              },
              child: Text(l10n.spaceInviteAction),
            ),
    );
  }
}

class _SpaceTickets extends ConsumerWidget {
  const _SpaceTickets({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tickets = ref.watch(spaceTicketsProvider(spaceId));
    return tickets.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(TokenSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          child: Text(l10n.spacesLoadError, style: theme.textTheme.bodySmall),
        ),
      ),
      data: (list) => list.isEmpty
          ? Card(
              child: Padding(
                padding: const EdgeInsets.all(TokenSpacing.lg),
                child: Text(
                  l10n.spaceTicketsEmpty,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          : Card(
              child: Column(
                children: [
                  for (final ticket in list)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        ticket.merchantName.isEmpty
                            ? l10n.spaceTicketUntitled
                            : ticket.merchantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: ticket.date == null ? null : Text(ticket.date!),
                      trailing: Text(
                        formatMoney(Money(ticket.grandTotalCents)),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
