import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../core/ui/action_banner.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../../friends/data/friendship_repository.dart';
import '../../friends/domain/friendship.dart';
import '../data/manual_link_repository.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';
import 'space_title_text.dart';
import 'space_cover_content.dart';

/// The intentionally compact second-level home for mutating context data.
/// Covers remain readable for guests; controls below are limited by the same
/// owner/account checks used by repository writes and Rules.
class SpaceManagementScreen extends ConsumerWidget {
  const SpaceManagementScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(spaceProvider(spaceId))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => Scaffold(
            appBar: AppBar(),
            body: ScreenBody(
              children: [
                ErrorStateView(
                  message: l10n.spacesLoadError,
                  onRetry: () => ref.invalidate(spaceProvider(spaceId)),
                ),
              ],
            ),
          ),
          data: (space) => space == null
              ? Scaffold(
                  appBar: AppBar(),
                  body: Center(child: Text(l10n.spaceGone)),
                )
              : _ManagementBody(space: space),
        );
  }
}

class _ManagementBody extends ConsumerWidget {
  const _ManagementBody({required this.space});
  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final myUid = ref.watch(currentUserIdFromSpacesProvider);
    final owner = space.ownerUid == myUid;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          space.isRelationship
              ? l10n.spaceManageTitle
              : l10n.spaceManageGroupTitle,
        ),
      ),
      body: ScreenBody(
        children: [
          if (space.isRelationship)
            _RelationshipManagement(space: space, owner: owner)
          else
            _GroupManagement(space: space, owner: owner),
          const SectionGap(),
          _Actions(space: space, owner: owner),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

class _GroupManagement extends ConsumerWidget {
  const _GroupManagement({required this.space, required this.owner});
  final Space space;
  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(spaceMembersProvider(space.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoverSection(
          title: l10n.spaceManagePeople,
          action: owner && space.isActive
              ? TextButton(
                  onPressed: () => _showInviteSheet(context),
                  child: Text(l10n.spaceInviteAction),
                )
              : null,
          child: members.when(
            loading: () => const SkeletonList(rows: 2),
            error: (_, _) => ErrorStateView(
              message: l10n.spacesLoadError,
              onRetry: () => ref.invalidate(spaceMembersProvider(space.id)),
            ),
            data: (data) => SaldaCardList(
              children: [
                for (final member in data)
                  _MemberRow(space: space, member: member, owner: owner),
                _ManagementManualParticipants(
                  spaceId: space.id,
                  canAdd: owner && space.isActive,
                  canRemove: owner && space.isActive,
                  canRename: owner && space.isActive,
                ),
              ],
            ),
          ),
        ),
        if (owner) ...[const SectionGap(), _GroupRequests(spaceId: space.id)],
        const SectionGap(),
        CoverSection(
          title: l10n.spaceManagePermissions,
          child: _GuestPolicyTile(space: space, owner: owner),
        ),
        const SectionGap(),
        CoverSection(
          title: l10n.spaceManageInformationHistory,
          child: SaldaCardList(
            children: [
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.link),
                title: Text(l10n.spaceLinkAction),
                onTap: owner && space.isActive
                    ? () => context.push('/home/spaces/${space.id}/link')
                    : null,
              ),
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.history),
                title: Text(l10n.spaceManageActivity),
                onTap: () => context.push('/home/spaces/${space.id}/activity'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showInviteSheet(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _InviteFriendsSheet(space: space),
      );
}

class _GuestPolicyTile extends ConsumerStatefulWidget {
  const _GuestPolicyTile({required this.space, required this.owner});

  final Space space;
  final bool owner;

  @override
  ConsumerState<_GuestPolicyTile> createState() => _GuestPolicyTileState();
}

class _GuestPolicyTileState extends ConsumerState<_GuestPolicyTile> {
  var _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      minTileHeight: 48,
      title: Text(l10n.guestPolicyTitle),
      subtitle: Text(l10n.guestPolicyBody),
      trailing: Switch(
        value: widget.space.guestsCanCreateExpenses,
        onChanged: widget.owner && widget.space.isActive && !_saving
            ? _setPolicy
            : null,
      ),
    );
  }

  Future<void> _setPolicy(bool value) async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(spacesRepositoryProvider)
          .setGuestsCanCreateExpenses(widget.space.id, value);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _RelationshipManagement extends ConsumerWidget {
  const _RelationshipManagement({required this.space, required this.owner});
  final Space space;
  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canChat = !(ref.watch(currentAppUserProvider)?.isAnonymous ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoverSection(
          title: AppLocalizations.of(context).spaceManageIdentity,
          child: SaldaCardList(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: SpaceTitleText(
                  spaceId: space.id,
                  storedName: space.name,
                ),
              ),
            ],
          ),
        ),
        _ManagementManualParticipants(
          spaceId: space.id,
          canAdd: false,
          canRemove: false,
          canRename: owner && space.isActive,
        ),
        const SectionGap(),
        CoverSection(
          title: AppLocalizations.of(context).spaceManageInvitationLink,
          child: SaldaCardList(
            children: [
              if (owner && space.isActive)
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(AppLocalizations.of(context).spaceInviteAction),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => _InviteFriendsSheet(space: space),
                  ),
                ),
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.history),
                title: Text(AppLocalizations.of(context).spaceManageActivity),
                onTap: () => context.push('/home/spaces/${space.id}/activity'),
              ),
            ],
          ),
        ),
        if (canChat) ...[
          const SectionGap(),
          CoverSection(
            title: AppLocalizations.of(context).spaceManageOptions,
            child: ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(AppLocalizations.of(context).spaceManageChat),
              onTap: () => context.push('/home/spaces/${space.id}/chat'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ManagementManualParticipants extends ConsumerStatefulWidget {
  const _ManagementManualParticipants({
    required this.spaceId,
    required this.canAdd,
    required this.canRemove,
    required this.canRename,
  });

  final String spaceId;
  final bool canAdd;
  final bool canRemove;
  final bool canRename;

  @override
  ConsumerState<_ManagementManualParticipants> createState() =>
      _ManagementManualParticipantsState();
}

class _ManagementManualParticipantsState
    extends ConsumerState<_ManagementManualParticipants> {
  final Set<String> _retrying = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manuals = ref.watch(spaceManualParticipantsProvider(widget.spaceId));
    if (manuals.isLoading) {
      return const SkeletonList(rows: 1);
    }
    if (manuals.hasError) {
      return ErrorStateView(
        message: l10n.spacesLoadError,
        onRetry: () =>
            ref.invalidate(spaceManualParticipantsProvider(widget.spaceId)),
      );
    }
    final data = manuals.requireValue;
    if (data.isEmpty && !widget.canAdd) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        for (final manual in data)
          ListTile(
            minTileHeight: 48,
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(manual.displayName),
            subtitle: Text(_subtitle(manual, l10n)),
            trailing: _menu(manual, l10n),
          ),
        if (widget.canAdd)
          ListTile(
            minTileHeight: 48,
            leading: const Icon(Icons.person_add_alt),
            title: Text(l10n.manualParticipantAdd),
            onTap: () => _edit(manual: null),
          ),
      ],
    );
  }

  Widget? _menu(ManualParticipant manual, AppLocalizations l10n) {
    final canRetry =
        widget.canRename &&
        manual.linkedUid != null &&
        (manual.effectiveLinkStatus == ManualLinkPropagationStatus.failed ||
            manual.effectiveLinkStatus ==
                ManualLinkPropagationStatus.processing);
    if (!widget.canRename && !widget.canRemove && !canRetry) {
      return null;
    }
    return PopupMenuButton<String>(
      onSelected: (action) {
        switch (action) {
          case 'rename':
            _edit(manual: manual);
            break;
          case 'retry':
            _retry(manual);
            break;
          case 'remove':
            _remove(manual);
            break;
        }
      },
      itemBuilder: (_) => [
        if (canRetry)
          PopupMenuItem(
            value: 'retry',
            enabled: !_retrying.contains(manual.id),
            child: Text(l10n.commonRetry),
          ),
        if (widget.canRename)
          PopupMenuItem(
            value: 'rename',
            child: Text(l10n.manualParticipantRename),
          ),
        if (widget.canRemove)
          PopupMenuItem(
            value: 'remove',
            child: Text(l10n.manualParticipantRemove),
          ),
      ],
    );
  }

  String _subtitle(ManualParticipant manual, AppLocalizations l10n) =>
      switch (manual.effectiveLinkStatus) {
        ManualLinkPropagationStatus.active => l10n.manualLinkLinked,
        ManualLinkPropagationStatus.processing => l10n.manualLinkProcessing,
        ManualLinkPropagationStatus.failed =>
          manual.linkError == 'legacy-sessions-without-context'
              ? l10n.manualLinkFailedLegacy
              : l10n.manualLinkFailed,
        null => l10n.manualParticipantHint,
      };

  Future<void> _edit({ManualParticipant? manual}) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: manual?.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          manual == null
              ? l10n.manualParticipantAdd
              : l10n.manualParticipantRename,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.manualParticipantName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    try {
      final repo = ref.read(spacesRepositoryProvider);
      if (manual == null) {
        await repo.addManualParticipant(widget.spaceId, name);
      } else {
        await repo.renameManualParticipant(widget.spaceId, manual.id, name);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    }
  }

  Future<void> _remove(ManualParticipant manual) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.manualParticipantRemove),
        content: Text(l10n.manualParticipantRemoveBody(manual.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.manualParticipantRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(spacesRepositoryProvider)
          .removeManualParticipant(widget.spaceId, manual.id);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    }
  }

  Future<void> _retry(ManualParticipant manual) async {
    if (!_retrying.add(manual.id)) {
      return;
    }
    setState(() {});
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref
          .read(manualLinkRepositoryProvider)
          .retryPropagation(widget.spaceId, manual.id);
      final message = switch (result.action) {
        ManualLinkRetryAction.claimed => switch (result.status) {
          ManualLinkPropagationStatus.active => l10n.manualLinkRetrySuccess,
          ManualLinkPropagationStatus.failed => l10n.manualLinkFailed,
          ManualLinkPropagationStatus.processing => l10n.manualLinkRetryStarted,
        },
        ManualLinkRetryAction.active => l10n.manualLinkLinked,
        ManualLinkRetryAction.inProgress => l10n.manualLinkRetryInProgress,
        ManualLinkRetryAction.cooldown => l10n.manualLinkRetryCooldown,
        ManualLinkRetryAction.unclassifiable => l10n.manualLinkRetryCheck,
      };
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
      }
    } finally {
      _retrying.remove(manual.id);
      if (mounted) {
        setState(() {});
      }
    }
  }
}

class _InviteFriendsSheet extends ConsumerWidget {
  const _InviteFriendsSheet({required this.space});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final friendships = ref.watch(friendshipsProvider);
    final myUid = ref.watch(currentUserIdFromSpacesProvider);
    final members = ref.watch(spaceMembersProvider(space.id));
    final invites = ref.watch(spaceInvitesProvider(space.id));
    if (friendships.isLoading || members.isLoading || invites.isLoading) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(TokenSpacing.lg),
          child: SkeletonList(rows: 3),
        ),
      );
    }
    if (friendships.hasError || members.hasError || invites.hasError) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          child: ErrorStateView(
            message: l10n.spacesLoadError,
            onRetry: () {
              ref.invalidate(friendshipsProvider);
              ref.invalidate(spaceMembersProvider(space.id));
              ref.invalidate(spaceInvitesProvider(space.id));
            },
          ),
        ),
      );
    }
    final friendshipData = friendships.requireValue;
    final memberData = members.requireValue;
    final inviteData = invites.requireValue;
    final memberUids = {for (final member in memberData) member.uid};
    final invitedUids = {for (final invite in inviteData) invite.toUid};
    final candidates = space.isRelationship
        ? [
            for (final uid in space.relationshipUids)
              if (uid != myUid) uid,
          ]
        : [
            for (final friendship in friendshipData)
              if (friendship.status == FriendshipStatus.friends)
                friendship.otherUid(myUid),
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
            if (candidates.isEmpty)
              Text(l10n.spaceInviteNoFriends)
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final uid in candidates)
                      _InviteCandidateTile(
                        space: space,
                        uid: uid,
                        member: memberUids.contains(uid),
                        invited: invitedUids.contains(uid),
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

class _InviteCandidateTile extends ConsumerStatefulWidget {
  const _InviteCandidateTile({
    required this.space,
    required this.uid,
    required this.member,
    required this.invited,
  });

  final Space space;
  final String uid;
  final bool member;
  final bool invited;

  @override
  ConsumerState<_InviteCandidateTile> createState() =>
      _InviteCandidateTileState();
}

class _InviteCandidateTileState extends ConsumerState<_InviteCandidateTile> {
  var _inviting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(publicProfileProvider(widget.uid)).value;
    return ListTile(
      minTileHeight: 48,
      leading: profile == null
          ? const CircleAvatar(child: Icon(Icons.person_outline))
          : ProfileAvatar(
              seed: widget.uid,
              displayName: profile.displayName,
              radius: 16,
            ),
      title: Text(profile?.displayName ?? '…'),
      subtitle: profile == null ? null : Text('@${profile.username}'),
      trailing: widget.member
          ? Text(l10n.spaceAlreadyMember)
          : widget.invited
          ? Text(l10n.spaceAlreadyInvited)
          : FilledButton.tonal(
              onPressed: !widget.space.isActive || _inviting ? null : _invite,
              child: _inviting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.spaceInviteAction),
            ),
    );
  }

  Future<void> _invite() async {
    if (_inviting) {
      return;
    }
    setState(() => _inviting = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(spacesRepositoryProvider)
          .invite(widget.space.id, widget.space.name, widget.uid);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }
}

class _PendingInviteTile extends ConsumerStatefulWidget {
  const _PendingInviteTile({required this.invite});

  final SpaceInvite invite;

  @override
  ConsumerState<_PendingInviteTile> createState() => _PendingInviteTileState();
}

class _PendingInviteTileState extends ConsumerState<_PendingInviteTile> {
  var _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      minTileHeight: 48,
      leading: const Icon(Icons.schedule_outlined),
      title: Text(l10n.spacePendingInvites),
      trailing: IconButton(
        tooltip: l10n.spaceInviteCancel,
        icon: _cancelling
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.close),
        onPressed: _cancelling ? null : _cancel,
      ),
    );
  }

  Future<void> _cancel() async {
    if (_cancelling) {
      return;
    }
    setState(() => _cancelling = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(spacesRepositoryProvider).cancelInvite(widget.invite.id);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    } finally {
      if (mounted) {
        setState(() => _cancelling = false);
      }
    }
  }
}

class _GroupRequests extends ConsumerStatefulWidget {
  const _GroupRequests({required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<_GroupRequests> createState() => _GroupRequestsState();
}

class _GroupRequestsState extends ConsumerState<_GroupRequests> {
  final Set<String> _deciding = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spaceId = widget.spaceId;
    final invites = ref.watch(spaceInvitesProvider(spaceId));
    final links = ref.watch(pendingManualLinksProvider(spaceId));
    final manuals = ref.watch(spaceManualParticipantsProvider(spaceId));
    if (invites.isLoading || links.isLoading || manuals.isLoading) {
      return CoverSection(
        title: l10n.spaceManageRequests,
        child: const SkeletonList(rows: 1),
      );
    }
    if (invites.hasError || links.hasError || manuals.hasError) {
      return CoverSection(
        title: l10n.spaceManageRequests,
        child: ErrorStateView(
          message: l10n.spacesLoadError,
          onRetry: () {
            ref.invalidate(spaceInvitesProvider(spaceId));
            ref.invalidate(pendingManualLinksProvider(spaceId));
            ref.invalidate(spaceManualParticipantsProvider(spaceId));
          },
        ),
      );
    }
    final inviteData = invites.requireValue;
    final linkData = links.requireValue;
    final manualData = manuals.requireValue;
    if (inviteData.isEmpty && linkData.isEmpty) {
      return const SizedBox.shrink();
    }
    String manualName(String manualId) {
      for (final manual in manualData) {
        if (manual.id == manualId && manual.displayName.trim().isNotEmpty) {
          return manual.displayName.trim();
        }
      }
      return l10n.personUnnamed;
    }

    return CoverSection(
      title: l10n.spaceManageRequests,
      child: SaldaCardList(
        children: [
          for (final invite in inviteData) _PendingInviteTile(invite: invite),
          for (final request in linkData)
            ActionBanner(
              icon: Icons.person_add_alt,
              title: Text(
                l10n.manualLinkRequestBody(
                  request.displayName.isEmpty
                      ? l10n.peopleYou
                      : request.displayName,
                  manualName(request.manualId),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _deciding.contains(request.id)
                      ? null
                      : () => _decide(context, request, false),
                  child: Text(l10n.manualLinkReject),
                ),
                FilledButton(
                  onPressed: _deciding.contains(request.id)
                      ? null
                      : () => _decide(context, request, true),
                  child: Text(l10n.manualLinkAccept),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    ManualLinkRequest request,
    bool accept,
  ) async {
    if (!_deciding.add(request.id)) return;
    setState(() {});
    final l10n = AppLocalizations.of(context);
    try {
      final repository = ref.read(manualLinkRepositoryProvider);
      if (accept) {
        await repository.approve(widget.spaceId, request);
      } else {
        await repository.reject(widget.spaceId, request.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? l10n.manualLinkProcessing : l10n.manualLinkRejected,
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
      }
    } finally {
      _deciding.remove(request.id);
      if (mounted) setState(() {});
    }
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  const _MemberRow({
    required this.space,
    required this.member,
    required this.owner,
  });
  final Space space;
  final SpaceMember member;
  final bool owner;

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  var _busy = false;

  Space get space => widget.space;
  SpaceMember get member => widget.member;
  bool get owner => widget.owner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(currentUserIdFromSpacesProvider);
    final profile = member.isGuest
        ? null
        : ref.watch(publicProfileProvider(member.uid)).value;
    final name = member.isGuest
        ? member.displayName ?? l10n.guestBadge
        : profile?.displayName ?? '…';
    return ListTile(
      minTileHeight: 48,
      leading: member.isGuest
          ? const CircleAvatar(child: Icon(Icons.person_outline))
          : ProfileAvatar(seed: member.uid, displayName: name, radius: 16),
      title: Text(name),
      subtitle: Text(
        member.uid == space.ownerUid
            ? l10n.spaceOwnerBadge
            : member.isGuest
            ? l10n.guestBadge
            : '',
      ),
      trailing:
          owner &&
              member.uid != me &&
              member.uid != space.ownerUid &&
              space.isActive
          ? PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (action) => _confirm(
                context,
                action == 'remove'
                    ? l10n.spaceRemoveMemberTitle
                    : l10n.spaceTransferTitle,
                action == 'remove'
                    ? l10n.spaceRemoveMemberBody(name)
                    : l10n.spaceTransferBody(name),
                () => action == 'remove'
                    ? ref
                          .read(spacesRepositoryProvider)
                          .removeMember(space.id, member.uid)
                    : ref
                          .read(spacesRepositoryProvider)
                          .transferOwnership(space.id, member.uid),
              ),
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
      onTap: member.isGuest
          ? null
          : () => context.push('/home/person/${member.uid}'),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String body,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.space, required this.owner});
  final Space space;
  final bool owner;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  var _busy = false;

  Space get space => widget.space;
  bool get owner => widget.owner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canLeave =
        !owner && (ref.watch(currentAppUserProvider)?.isFullAccount ?? false);
    return CoverSection(
      title: l10n.spaceManageActions,
      child: SaldaCardList(
        children: [
          if (owner && space.isActive && !space.isRelationship)
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.spaceEditName),
              onTap: _busy ? null : () => _rename(context),
            ),
          if (owner)
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.archive_outlined),
              title: Text(
                space.isActive ? l10n.spaceArchive : l10n.spaceReactivate,
              ),
              onTap: _busy ? null : () => _setStatus(context),
            ),
          if (canLeave)
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.exit_to_app),
              title: Text(l10n.spaceLeave),
              onTap: _busy ? null : () => _leave(context),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: space.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.spaceEditName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (name == null || name.length < 2) {
      return;
    }
    try {
      await _run(
        () => ref.read(spacesRepositoryProvider).rename(space.id, name),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    }
  }

  Future<void> _setStatus(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final label = space.isActive ? l10n.spaceArchive : l10n.spaceReactivate;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _run(
        () => ref
            .read(spacesRepositoryProvider)
            .setStatus(
              space.id,
              space.isActive ? SpaceStatus.archived : SpaceStatus.active,
            ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    }
  }

  Future<void> _leave(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.spaceLeave),
        content: Text(l10n.spaceLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.spaceLeave),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _run(() => ref.read(spacesRepositoryProvider).leave(space.id));
      if (context.mounted) {
        context.go('/home/spaces');
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
