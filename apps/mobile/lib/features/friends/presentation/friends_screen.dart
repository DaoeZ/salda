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
import 'friendship_error_text.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider);
    if (profile.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.friendsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (profile.value == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.friendsTitle)),
        body: _ProfileRequired(l10n: l10n),
      );
    }

    final relationships = ref.watch(friendshipsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.friendsTitle),
          actions: [
            IconButton(
              tooltip: l10n.searchPeopleTitle,
              onPressed: () => context.push('/home/people'),
              icon: const Icon(Icons.person_search_outlined),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.friendsTabFriends),
              Tab(text: l10n.friendsTabReceived),
              Tab(text: l10n.friendsTabSent),
            ],
          ),
        ),
        body: relationships.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ErrorState(
            onRetry: () => ref.invalidate(friendshipsProvider),
            l10n: l10n,
          ),
          data: (items) {
            final currentUid = ref.read(currentUserIdProvider);
            final friends = items
                .where((item) => item.status == FriendshipStatus.friends)
                .toList();
            final received = items
                .where(
                  (item) =>
                      item.status == FriendshipStatus.pending &&
                      item.receiverUid == currentUid,
                )
                .toList();
            final sent = items
                .where(
                  (item) =>
                      item.status == FriendshipStatus.pending &&
                      item.requesterUid == currentUid,
                )
                .toList();
            return TabBarView(
              children: [
                _RelationshipList(
                  items: friends,
                  currentUid: currentUid,
                  emptyTitle: l10n.friendsEmpty,
                  emptyBody: l10n.friendsEmptyBody,
                  showSearchAction: true,
                ),
                _RelationshipList(
                  items: received,
                  currentUid: currentUid,
                  emptyTitle: l10n.friendRequestsReceivedEmpty,
                ),
                _RelationshipList(
                  items: sent,
                  currentUid: currentUid,
                  emptyTitle: l10n.friendRequestsSentEmpty,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileRequired extends StatelessWidget {
  const _ProfileRequired({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle_outlined, size: 56),
          const SizedBox(height: TokenSpacing.md),
          Text(l10n.friendProfileRequired, textAlign: TextAlign.center),
          const SizedBox(height: TokenSpacing.lg),
          FilledButton(
            onPressed: () => context.push('/home/profile'),
            child: Text(l10n.friendProfileRequiredAction),
          ),
        ],
      ),
    ),
  );
}

class _RelationshipList extends StatelessWidget {
  const _RelationshipList({
    required this.items,
    required this.currentUid,
    required this.emptyTitle,
    this.emptyBody,
    this.showSearchAction = false,
  });

  final List<Friendship> items;
  final String currentUid;
  final String emptyTitle;
  final String? emptyBody;
  final bool showSearchAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: TokenSpacing.md),
              Text(emptyTitle, textAlign: TextAlign.center),
              if (emptyBody != null) ...[
                const SizedBox(height: TokenSpacing.xs),
                Text(
                  emptyBody!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (showSearchAction) ...[
                const SizedBox(height: TokenSpacing.lg),
                OutlinedButton.icon(
                  onPressed: () => context.push('/home/people'),
                  icon: const Icon(Icons.person_search_outlined),
                  label: Text(l10n.searchPeopleTitle),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(TokenSpacing.md),
      itemCount: items.length,
      itemBuilder: (_, index) =>
          _RelationshipCard(relationship: items[index], currentUid: currentUid),
    );
  }
}

class _RelationshipCard extends ConsumerStatefulWidget {
  const _RelationshipCard({
    required this.relationship,
    required this.currentUid,
  });

  final Friendship relationship;
  final String currentUid;

  @override
  ConsumerState<_RelationshipCard> createState() => _RelationshipCardState();
}

class _RelationshipCardState extends ConsumerState<_RelationshipCard> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendshipErrorText(AppLocalizations.of(context), error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String otherUid) async {
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
        () => ref.read(friendshipRepositoryProvider).removeFriend(otherUid),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final otherUid = widget.relationship.otherUid(widget.currentUid);
    final profile = ref.watch(publicProfileProvider(otherUid));
    final relation = widget.relationship.relationFor(widget.currentUid);
    final resolved = profile.value;
    return Card(
      child: InkWell(
        onTap: resolved == null
            ? null
            : () => context.push('/home/person/$otherUid'),
        borderRadius: BorderRadius.circular(TokenRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    seed: otherUid,
                    displayName: resolved?.displayName ?? '',
                  ),
                  const SizedBox(width: TokenSpacing.md),
                  Expanded(
                    child: profile.isLoading
                        ? const LinearProgressIndicator()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resolved?.displayName ??
                                    l10n.friendProfileUnavailable,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (resolved != null)
                                Text(
                                  '@${resolved.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(TokenSpacing.sm),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              if (!_busy && resolved != null) ...[
                const SizedBox(height: TokenSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: TokenSpacing.sm,
                  runSpacing: TokenSpacing.xs,
                  children: switch (relation) {
                    FriendshipRelationState.incoming => [
                      TextButton(
                        onPressed: () => _run(
                          () => ref
                              .read(friendshipRepositoryProvider)
                              .rejectRequest(otherUid),
                        ),
                        child: Text(l10n.friendReject),
                      ),
                      FilledButton(
                        onPressed: () => _run(
                          () => ref
                              .read(friendshipRepositoryProvider)
                              .acceptRequest(otherUid),
                        ),
                        child: Text(l10n.friendAccept),
                      ),
                    ],
                    FriendshipRelationState.outgoing => [
                      OutlinedButton(
                        onPressed: () => _run(
                          () => ref
                              .read(friendshipRepositoryProvider)
                              .cancelRequest(otherUid),
                        ),
                        child: Text(l10n.friendCancelRequest),
                      ),
                    ],
                    FriendshipRelationState.friends => [
                      TextButton(
                        onPressed: () => _remove(otherUid),
                        child: Text(l10n.friendRemove),
                      ),
                    ],
                    FriendshipRelationState.none => const [],
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.l10n});

  final VoidCallback onRetry;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 56),
          const SizedBox(height: TokenSpacing.md),
          Text(l10n.friendActionError, textAlign: TextAlign.center),
          const SizedBox(height: TokenSpacing.lg),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    ),
  );
}
