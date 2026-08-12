import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../sessions/presentation/ticket_navigation.dart';
import '../../../core/ui/action_banner.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../activity/presentation/space_activity_section.dart';
import '../../chat/presentation/space_chat_section.dart';
import '../../friends/data/friendship_repository.dart';
import '../../friends/domain/friendship.dart';
import '../../economy/presentation/space_economic_summary.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../../scan/presentation/scan_flow.dart';
import '../data/manual_link_repository.dart';
import '../data/spaces_repository.dart';
import '../domain/space_identities.dart';
import '../domain/space_models.dart';
import 'space_title_text.dart';

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
    final c = context.salda;
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
    final manualsAsync = ref.watch(
      spaceManualParticipantsProvider(widget.spaceId),
    );
    final manuals = manualsAsync.value ?? const <ManualParticipant>[];
    // Lo que hace a un contexto operativo son las IDENTIDADES ECONÓMICAS, no
    // las cuentas (BUG-6): un MANUAL pesa igual que quien tiene app, y un
    // manual ya vinculado no cuenta dos veces junto a su cuenta.
    final peopleCount = spaceEconomicIdentities(
      members: members,
      manuals: manuals,
    ).length;
    final contextReady = contextReadyForExpenses(space.kind, peopleCount);
    // Mientras faltan datos no se afirma que falte gente: con las listas
    // todavía vacías el resultado sería "no operativo" y la pantalla
    // parpadearía entre un aviso falso y el estado real.
    final countingPeople =
        !manualsAsync.hasValue ||
        !ref.watch(spaceMembersProvider(widget.spaceId)).hasValue;

    return Scaffold(
      appBar: AppBar(
        title: SpaceTitleText(spaceId: space.id, storedName: space.name),
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
              'link' => context.push('/home/spaces/${space.id}/link'),
              _ => null,
            },
            itemBuilder: (_) => [
              if (amOwner) ...[
                // Solo GRUPOS: el título de una relación es la otra persona,
                // resuelto al leer (BUG-5). Editar el nombre persistido no
                // cambiaría nada de lo que se ve — sería un menú que miente.
                // El nombre de un MANUAL sí se edita, en su propia ficha.
                if (!space.isRelationship)
                  PopupMenuItem(value: 'edit', child: Text(l10n.spaceEditName)),
                // Solo GRUPOS: una relación reserva una pareja canónica de
                // UID y no admite un tercero (ADR-030), así que un enlace no
                // tendría a quién admitir.
                if (space.isActive && !space.isRelationship)
                  PopupMenuItem(
                    value: 'link',
                    child: Text(l10n.spaceLinkAction),
                  ),
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
      body: ScreenBody(
        children: [
          // Cabecera: quien es esto, cuanta gente hay y en que estado.
          Row(
            children: [
              SaldaAvatar(
                seed: space.id,
                label: space.name,
                emoji: space.avatarEmoji,
                square: !space.isRelationship,
                radius: 24,
              ),
              const SizedBox(width: TokenSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SpaceTitleText(
                      spaceId: space.id,
                      storedName: space.name,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    // `Wrap` y no `Row`: con el texto ampliado «Grupo · 3
                    // personas» no cabe en 320 px y la fila desbordaba 98 px.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          space.isRelationship
                              ? l10n.spaceKindRelationship
                              : l10n.spaceKindGroup,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                        Text(
                          '  \u00b7  ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                        // PERSONAS, no miembros: decir «1 miembro» en un
                        // grupo con un manual contradecia que estuviera
                        // operativo (BUG-6).
                        if (countingPeople)
                          const Skeleton.line(width: 58, height: 11)
                        else
                          Text(
                            l10n.peopleCount(peopleCount),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!space.isActive)
                StatusBadge(l10n.statusArchived, icon: Icons.archive_outlined),
            ],
          ),
          if (!contextReady && !countingPeople) ...[
            const SectionGap(height: TokenSpacing.lg),
            EmptyState(
              icon: Icons.person_add_alt,
              title: space.isRelationship
                  ? l10n.relationshipNeedsAcceptance
                  : l10n.groupNeedsMembers,
              body: space.isRelationship
                  ? l10n.relationshipNeedsAcceptanceBody
                  : l10n.groupNeedsMembersBody,
            ),
          ],
          const SectionGap(),
          SpaceEconomicSummary(spaceId: space.id),
          const SectionGap(),
          SectionHeader(title: l10n.spaceTicketsTitle),
          _SpaceTickets(spaceId: space.id),
          const SectionGap(),

          // Personas
          SectionHeader(
            title: l10n.spaceMembersTitle,
            action: amOwner && space.isActive ? l10n.spaceInviteAction : null,
            onAction: amOwner && space.isActive
                ? () => _showInviteSheet(space)
                : null,
          ),
          SaldaCardList(
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
          if (amOwner) _PendingManualLinks(spaceId: space.id),
          if (amOwner) _PendingInvites(spaceId: space.id),
          _ManualParticipants(
            spaceId: space.id,
            // BUG-4: anadir personas a mano es de GRUPOS. Una relacion tiene
            // exactamente dos identidades y ya estan decididas: en v2 la
            // segunda plaza la reserva la invitacion, y en v3 la ocupa su
            // manual. Ofrecerlo aqui invitaba a crear un estado incoherente
            // que Rules rechaza - un boton que solo podia terminar en error.
            canAdd: amOwner && space.isActive && !space.isRelationship,
            // El manual de la segunda plaza de una relacion NO es un
            // participante retirable: quitarlo dejaria una sola identidad.
            canRemove: amOwner && space.isActive && !space.isRelationship,
            canRename: amOwner && space.isActive,
          ),
          if (amOwner) ...[
            const SectionGap(height: TokenSpacing.lg),
            SaldaCard(
              padding: const EdgeInsets.symmetric(
                horizontal: TokenSpacing.lg,
                vertical: TokenSpacing.xs,
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: space.guestsCanCreateExpenses,
                onChanged: space.isActive
                    ? (allowed) => _guarded(
                        () =>
                            repo.setGuestsCanCreateExpenses(space.id, allowed),
                      )
                    : null,
                title: Text(
                  l10n.guestPolicyTitle,
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  l10n.guestPolicyBody,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
          const SectionGap(),
          SpaceChatSection(spaceId: space.id, isActive: space.isActive),
          const SectionGap(),
          SpaceActivitySection(spaceId: space.id),
          const SizedBox(height: 88),
        ],
      ),
      floatingActionButton: space.isActive
          ? FloatingActionButton.extended(
              onPressed: _scanning || !contextReady || countingPeople
                  ? null
                  : () {
                      // El próximo ticket guardado se vincula a ESTE espacio
                      // (lo consume el controlador de creación).
                      ref
                          .read(pendingSpaceLinkProvider.notifier)
                          .set(space.id, space.name, space.kind);
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
    // Un INVITADO no tiene perfil público: su nombre es el snapshot que
    // congeló al unirse (ADR-034); las cuentas se resuelven en vivo.
    final profile = member.isGuest
        ? null
        : ref.watch(publicProfileProvider(member.uid)).value;
    final name = member.isGuest
        ? (member.displayName ?? l10n.guestBadge)
        : profile?.displayName;
    return ListTile(
      leading: name == null
          ? const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16))
          : ProfileAvatar(seed: member.uid, displayName: name, radius: 16),
      title: Text(name ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        isOwnerMember
            ? l10n.spaceOwnerBadge
            : member.isGuest
            ? l10n.guestBadge
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

/// Personas sin cuenta del contexto (ADR-033). Solo hace falta su nombre:
/// participan en gastos y balances como cualquier miembro registrado, pero
/// no reciben invitación ni acceso porque no tienen dispositivo.
class _ManualParticipants extends ConsumerStatefulWidget {
  const _ManualParticipants({
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
  ConsumerState<_ManualParticipants> createState() =>
      _ManualParticipantsState();
}

class _ManualParticipantsState extends ConsumerState<_ManualParticipants> {
  final Set<String> _retrying = <String>{};

  String get spaceId => widget.spaceId;
  bool get canAdd => widget.canAdd;
  bool get canRemove => widget.canRemove;
  bool get canRename => widget.canRename;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final manuals =
        ref.watch(spaceManualParticipantsProvider(spaceId)).value ??
        const <ManualParticipant>[];
    // Sin manuales y sin poder añadirlos —una relación v2— la sección no
    // pinta nada: no hay ningún control de grupo que enseñar.
    if (manuals.isEmpty && !canAdd) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: TokenSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.manualParticipantsTitle,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (canAdd)
              TextButton.icon(
                onPressed: () => _editName(context, ref),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: Text(l10n.manualParticipantAdd),
              ),
          ],
        ),
        Card(
          child: Column(
            children: [
              if (manuals.isEmpty)
                ListTile(
                  dense: true,
                  title: Text(
                    l10n.manualParticipantsEmpty,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                for (final manual in manuals)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        avatarInitials(manual.displayName),
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    title: Text(
                      manual.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_manualSubtitle(manual, l10n)),
                    trailing: canRename || canRemove || _canRetry(manual)
                        ? PopupMenuButton<String>(
                            onSelected: (action) => switch (action) {
                              'rename' => _editName(
                                context,
                                ref,
                                manual: manual,
                              ),
                              'retry' => _retryPropagation(context, manual),
                              _ => _confirmRemove(context, ref, manual),
                            },
                            itemBuilder: (_) => [
                              if (_canRetry(manual))
                                PopupMenuItem(
                                  value: 'retry',
                                  enabled: !_retrying.contains(manual.id),
                                  child: Text(l10n.commonRetry),
                                ),
                              if (canRename)
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(l10n.manualParticipantRename),
                                ),
                              // En una relación el manual ocupa la segunda
                              // plaza: retirarlo dejaría una sola identidad,
                              // así que la opción no existe.
                              if (canRemove)
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(l10n.manualParticipantRemove),
                                ),
                            ],
                          )
                        : null,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  bool _canRetry(ManualParticipant manual) {
    final status = manual.effectiveLinkStatus;
    return canRename &&
        manual.linkedUid != null &&
        (status == ManualLinkPropagationStatus.failed ||
            status == ManualLinkPropagationStatus.processing);
  }

  String _manualSubtitle(ManualParticipant manual, AppLocalizations l10n) {
    return switch (manual.effectiveLinkStatus) {
      ManualLinkPropagationStatus.active => l10n.manualLinkLinked,
      ManualLinkPropagationStatus.processing => l10n.manualLinkProcessing,
      ManualLinkPropagationStatus.failed =>
        manual.linkError == 'legacy-sessions-without-context'
            ? l10n.manualLinkFailedLegacy
            : l10n.manualLinkFailed,
      null => l10n.manualParticipantHint,
    };
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref, {
    ManualParticipant? manual,
  }) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: manual?.displayName ?? '');
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(spacesRepositoryProvider);
    await showDialog<void>(
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop();
              try {
                if (manual == null) {
                  await repo.addManualParticipant(spaceId, name);
                } else {
                  await repo.renameManualParticipant(spaceId, manual.id, name);
                }
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

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ManualParticipant manual,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(spacesRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.manualParticipantRemove),
        content: Text(l10n.manualParticipantRemoveBody(manual.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.manualParticipantRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.removeManualParticipant(spaceId, manual.id);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.spaceActionError)));
    }
  }

  Future<void> _retryPropagation(
    BuildContext context,
    ManualParticipant manual,
  ) async {
    if (!_retrying.add(manual.id)) return;
    setState(() {});
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(manualLinkRepositoryProvider)
          .retryPropagation(spaceId, manual.id);
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
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
      }
    } finally {
      _retrying.remove(manual.id);
      if (mounted) setState(() {});
    }
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
    final friends = space.isRelationship
        ? [
            for (final uid in space.relationshipUids)
              if (uid != myUid) uid,
          ]
        : [
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
    final tickets = ref.watch(spaceTicketsProvider(spaceId));
    return tickets.when(
      loading: () => const SkeletonList(rows: 2, leading: false),
      error: (error, _) => ErrorStateView(message: l10n.spacesLoadError),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.emptyTicketsTitle,
              body: l10n.emptyTicketsBody,
            )
          : SaldaCardList(
              children: [
                for (final ticket in list)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      ticket.merchantName.isEmpty
                          ? l10n.spaceTicketUntitled
                          : ticket.merchantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: ticket.date == null ? null : Text(ticket.date!),
                    trailing: MoneyText(
                      Money(ticket.grandTotalCents),
                      size: MoneySize.small,
                    ),
                    // El ticket se veía pero no se abría: la fila nunca tuvo
                    // acción. `dense` además dejaba el alto por debajo del
                    // objetivo táctil mínimo.
                    onTap: () => openTicket(
                      context,
                      sessionId: ticket.sessionId,
                      ticketId: ticket.id,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Bandeja del ANFITRIÓN: solicitudes de vinculación de identidad (ADR-037).
///
/// Vincular es reconocer que una persona real es un participante que hasta
/// ahora solo era un nombre. Como eso le da acceso a un historial económico,
/// lo decide el anfitrión y nadie más: Rules no permite escribir el vínculo
/// sin que la aceptación viaje en el mismo batch.
///
/// Aceptar NO mueve nada de lo ya registrado: el actor sigue siendo
/// `manual:{id}` y el participante, el mismo. Solo se añade la identidad.
class _PendingManualLinks extends ConsumerWidget {
  const _PendingManualLinks({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final requests =
        ref.watch(pendingManualLinksProvider(spaceId)).value ??
        const <ManualLinkRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();

    final manuals =
        ref.watch(spaceManualParticipantsProvider(spaceId)).value ??
        const <ManualParticipant>[];
    // Nunca el identificador: si el participante ya no está, un rótulo
    // controlado (misma regla que la resolución de nombres económicos).
    String manualName(String manualId) {
      final nombre = manuals
          .where((m) => m.id == manualId)
          .map((m) => m.displayName.trim())
          .firstOrNull;
      return (nombre == null || nombre.isEmpty) ? l10n.personUnnamed : nombre;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: TokenSpacing.lg),
        Text(l10n.manualLinkRequestsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: TokenSpacing.xs),
        Text(l10n.manualLinkRequestHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: TokenSpacing.sm),
        for (final request in requests)
          Card(
            // Los dos botones vivían en `ListTile.trailing`, que da
            // restricciones laxas: no había franja de desbordamiento, pero el
            // de aceptar quedaba fuera de la pantalla y no se podía pulsar.
            child: ActionBanner(
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
                  onPressed: () => _decide(context, ref, request, false),
                  child: Text(l10n.manualLinkReject),
                ),
                FilledButton(
                  onPressed: () => _decide(context, ref, request, true),
                  child: Text(l10n.manualLinkAccept),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    ManualLinkRequest request,
    bool accept,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(manualLinkRepositoryProvider);
    try {
      if (accept) {
        await repo.approve(spaceId, request);
      } else {
        await repo.reject(spaceId, request.id);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accept ? l10n.manualLinkProcessing : l10n.manualLinkRejected,
          ),
        ),
      );
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
    }
  }
}
