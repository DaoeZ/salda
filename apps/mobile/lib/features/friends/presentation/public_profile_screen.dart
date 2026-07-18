import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../data/friendship_repository.dart';
import '../domain/friendship.dart';

class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({required this.profileUid, super.key});

  final String profileUid;

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).friendActionError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.friendRemoveTitle),
        content: Text(l10n.friendRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.friendRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        () => ref
            .read(friendshipRepositoryProvider)
            .removeFriend(widget.profileUid),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUid = ref.watch(currentUserIdProvider);
    final profile = ref.watch(publicProfileProvider(widget.profileUid));
    final relationship = ref.watch(friendshipWithProvider(widget.profileUid));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ProfileError(
          onRetry: () =>
              ref.invalidate(publicProfileProvider(widget.profileUid)),
        ),
        data: (resolved) {
          if (resolved == null) return const _MissingProfile();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(TokenSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileAvatar(
                    seed: resolved.uid,
                    displayName: resolved.displayName,
                    radius: 48,
                  ),
                  const SizedBox(height: TokenSpacing.lg),
                  Text(
                    resolved.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: TokenSpacing.xs),
                  Text(
                    '@${resolved.username}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TokenSpacing.xl),
                  if (widget.profileUid == currentUid)
                    FilledButton.icon(
                      onPressed: () => context.push('/home/profile'),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(l10n.friendEditOwnProfile),
                    )
                  else if (relationship.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (relationship.hasError)
                    _InlineError(
                      onRetry: () => ref.invalidate(friendshipsProvider),
                    )
                  else
                    _RelationshipActions(
                      relationship: relationship.value,
                      currentUid: currentUid,
                      busy: _busy,
                      onAdd: () => _run(
                        () => ref
                            .read(friendshipRepositoryProvider)
                            .sendRequest(widget.profileUid),
                      ),
                      onAccept: () => _run(
                        () => ref
                            .read(friendshipRepositoryProvider)
                            .acceptRequest(widget.profileUid),
                      ),
                      onReject: () => _run(
                        () => ref
                            .read(friendshipRepositoryProvider)
                            .rejectRequest(widget.profileUid),
                      ),
                      onCancel: () => _run(
                        () => ref
                            .read(friendshipRepositoryProvider)
                            .cancelRequest(widget.profileUid),
                      ),
                      onRemove: _confirmRemove,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RelationshipActions extends StatelessWidget {
  const _RelationshipActions({
    required this.relationship,
    required this.currentUid,
    required this.busy,
    required this.onAdd,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
    required this.onRemove,
  });

  final Friendship? relationship;
  final String currentUid;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (busy) {
      return const Center(child: CircularProgressIndicator());
    }
    final relation =
        relationship?.relationFor(currentUid) ?? FriendshipRelationState.none;
    return switch (relation) {
      FriendshipRelationState.none => FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(l10n.friendAdd),
      ),
      FriendshipRelationState.outgoing => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(l10n.friendRequestSent),
          ),
          TextButton(
            onPressed: onCancel,
            child: Text(l10n.friendCancelRequest),
          ),
        ],
      ),
      FriendshipRelationState.incoming => Wrap(
        alignment: WrapAlignment.center,
        spacing: TokenSpacing.sm,
        runSpacing: TokenSpacing.sm,
        children: [
          OutlinedButton(onPressed: onReject, child: Text(l10n.friendReject)),
          FilledButton.icon(
            onPressed: onAccept,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(l10n.friendAccept),
          ),
        ],
      ),
      FriendshipRelationState.friends => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: null,
            icon: const Icon(Icons.people_outline),
            label: Text(l10n.friendFriendsStatus),
          ),
          TextButton(onPressed: onRemove, child: Text(l10n.friendRemove)),
        ],
      ),
    };
  }
}

class _MissingProfile extends StatelessWidget {
  const _MissingProfile();

  @override
  Widget build(BuildContext context) => Center(
    child: Text(AppLocalizations.of(context).friendProfileUnavailable),
  );
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _InlineError(onRetry: onRetry);
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.friendActionError, textAlign: TextAlign.center),
        const SizedBox(height: TokenSpacing.sm),
        OutlinedButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
      ],
    );
  }
}
