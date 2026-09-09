import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../core/ui/action_banner.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';
import 'space_row.dart';

/// Lista de espacios (P4): invitaciones recibidas, activos y archivados.
class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final spaces = ref.watch(mySpacesProvider);
    final invites = ref.watch(mySpaceInvitesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.spacesTitle)),
      body: spaces.when(
        loading: () => const ScreenBody(children: [SkeletonList(rows: 4)]),
        error: (error, _) => ScreenBody(
          children: [ErrorStateView(message: l10n.spacesLoadError)],
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
            return ScreenBody(
              children: [
                EmptyState(
                  icon: Icons.group_work_outlined,
                  title: l10n.spacesEmptyTitle,
                  body: l10n.spacesEmptyBody,
                ),
              ],
            );
          }
          final relationships = active
              .where((space) => space.isRelationship)
              .toList();
          final groups = active
              .where((space) => !space.isRelationship)
              .toList();
          return ScreenBody(
            children: [
              if (invites.isNotEmpty) ...[
                SectionHeader(title: l10n.contextInvitations),
                for (final invite in invites) _InviteCard(invite: invite),
                const SectionGap(),
              ],
              if (relationships.isNotEmpty) ...[
                SectionHeader(title: l10n.relationshipsTitle),
                SaldaCardList(
                  children: [
                    for (final space in relationships) SpaceRow(space: space),
                  ],
                ),
                const SectionGap(),
              ],
              if (groups.isNotEmpty) ...[
                SectionHeader(title: l10n.groupsTitle),
                SaldaCardList(
                  children: [
                    for (final space in groups) SpaceRow(space: space),
                  ],
                ),
              ],
              if (archived.isNotEmpty) ...[
                const SectionGap(),
                SectionHeader(
                  title: l10n.spacesArchivedSection(archived.length),
                ),
                SaldaCardList(
                  children: [
                    for (final space in archived) SpaceRow(space: space),
                  ],
                ),
              ],
              const SizedBox(height: 72),
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
      child: ActionBanner(
        // El avatar iba dentro de la fila del texto y le robaba ancho; como
        // icono del aviso queda arriba y el texto dispone de la línea entera.
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
              // Una RELACIÓN no tiene nombre propio que anunciar: el
              // contexto ES la otra persona. Nombrar aquí el espacio
              // enseñaba la concatenación «Edgar · Pedro» (BUG-5).
              child: Text(
                isRelationshipSpaceId(widget.invite.spaceId)
                    ? l10n.relationshipInviteText(from?.displayName ?? '…')
                    : l10n.spaceInviteText(
                        from?.displayName ?? '…',
                        widget.invite.spaceName,
                      ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => _resolve(() => repo.rejectInvite(widget.invite.id)),
            child: Text(l10n.spaceInviteReject),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _resolve(() => repo.acceptInvite(widget.invite)),
            child: Text(l10n.spaceInviteAccept),
          ),
        ],
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
