import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';
import 'space_avatar.dart';

/// Lista de espacios (P4): invitaciones recibidas, activos y archivados.
class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spaces = ref.watch(mySpacesProvider);
    final invites = ref.watch(mySpaceInvitesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.spacesTitle)),
      body: spaces.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(TokenSpacing.xl),
            child: Text(l10n.spacesLoadError, textAlign: TextAlign.center),
          ),
        ),
        data: (list) {
          final active = [
            for (final s in list)
              if (s.isActive) s,
          ];
          final archived = [
            for (final s in list)
              if (!s.isActive) s,
          ];
          if (active.isEmpty && archived.isEmpty && invites.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(TokenSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_work_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: TokenSpacing.lg),
                    Text(
                      l10n.spacesEmptyTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: TokenSpacing.xs),
                    Text(
                      l10n.spacesEmptyBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(TokenSpacing.lg),
            children: [
              for (final invite in invites) _InviteCard(invite: invite),
              for (final space in active) _SpaceTile(space: space),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: TokenSpacing.md),
                ExpansionTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(l10n.spacesArchivedSection(archived.length)),
                  children: [
                    for (final space in archived) _SpaceTile(space: space),
                  ],
                ),
              ],
              const SizedBox(height: 88),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateSpaceDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.spacesCreate),
      ),
    );
  }
}

class _SpaceTile extends ConsumerWidget {
  const _SpaceTile({required this.space});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isOwner =
        space.ownerUid == ref.watch(currentUserIdFromSpacesProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
      child: ListTile(
        leading: SpaceAvatar(space: space),
        title: Text(space.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: isOwner ? Text(l10n.spaceOwnerBadge) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/home/spaces/${space.id}'),
      ),
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.invite});

  final SpaceInvite invite;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  var _busy = false;

  Future<void> _resolve(Future<void> Function() action) async {
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final from = ref.watch(publicProfileProvider(widget.invite.fromUid)).value;
    final repo = ref.read(spacesRepositoryProvider);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: TokenSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (from != null) ...[
                  ProfileAvatar(
                    seed: from.uid,
                    displayName: from.displayName,
                    radius: 16,
                  ),
                  const SizedBox(width: TokenSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    l10n.spaceInviteText(
                      from?.displayName ?? '…',
                      widget.invite.spaceName,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TokenSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            _resolve(() => repo.rejectInvite(widget.invite.id)),
                  child: Text(l10n.spaceInviteReject),
                ),
                const SizedBox(width: TokenSpacing.sm),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _resolve(() => repo.acceptInvite(widget.invite)),
                  child: Text(l10n.spaceInviteAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCreateSpaceDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.spacesCreate),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l10n.spaceNameLabel,
          hintText: l10n.spaceNameHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.length < 2) return;
            final navigator = Navigator.of(dialogContext);
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ref.read(spacesRepositoryProvider).createSpace(name);
              navigator.pop();
            } on Object {
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.spaceActionError)),
              );
            }
          },
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
}
