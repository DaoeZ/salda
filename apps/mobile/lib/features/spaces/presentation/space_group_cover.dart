import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/surfaces.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../../scan/presentation/scan_flow.dart';
import '../data/spaces_repository.dart';
import '../domain/space_identities.dart';
import '../domain/space_models.dart';
import 'space_cover_content.dart';
import 'space_title_text.dart';

/// A group cover is an operational surface: current balances and tickets
/// come before the optional administration area.
class GroupSpaceCover extends ConsumerStatefulWidget {
  const GroupSpaceCover({super.key, required this.space});

  final Space space;

  @override
  ConsumerState<GroupSpaceCover> createState() => _GroupSpaceCoverState();
}

class _GroupSpaceCoverState extends ConsumerState<GroupSpaceCover> {
  var _scanning = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final space = widget.space;
    final members = ref.watch(spaceMembersProvider(space.id));
    final manuals = ref.watch(spaceManualParticipantsProvider(space.id));
    final peopleError = members.hasError || manuals.hasError;
    final countingPeople = !members.hasValue || !manuals.hasValue;
    final peopleCount = countingPeople
        ? 0
        : spaceEconomicIdentities(
            members: members.value!,
            manuals: manuals.value!,
          ).length;
    final contextReady =
        !countingPeople && contextReadyForExpenses(space.kind, peopleCount);
    final canWrite =
        space.isActive &&
        ((ref.watch(currentAppUserProvider)?.isFullAccount ?? false) ||
            (space.guestsCanCreateExpenses &&
                ref.watch(isOperationalGuestProvider)));
    final canChat = !(ref.watch(currentAppUserProvider)?.isAnonymous ?? false);
    return Scaffold(
      appBar: AppBar(
        title: SpaceTitleText(spaceId: space.id, storedName: space.name),
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
        actions: [
          if (canChat)
            IconButton(
              tooltip: l10n.chatTitle,
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => context.push('/home/spaces/${space.id}/chat'),
            ),
          IconButton(
            tooltip: l10n.spaceManageGroupTitle,
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/home/spaces/${space.id}/manage'),
          ),
        ],
      ),
      body: ScreenBody(
        children: [
          if (peopleError) ...[
            ErrorStateView(
              message: l10n.spacesLoadError,
              onRetry: () {
                ref.invalidate(spaceMembersProvider(space.id));
                ref.invalidate(spaceManualParticipantsProvider(space.id));
              },
            ),
            const SectionGap(),
          ],
          if (!peopleError && !contextReady && !countingPeople) ...[
            EmptyState(
              icon: Icons.person_add_alt,
              title: l10n.groupNeedsMembers,
              body: l10n.groupNeedsMembersBody,
            ),
            const SectionGap(),
          ],
          CoverSection(
            title: l10n.spaceCoverGroupBalance,
            action: TextButton(
              onPressed: () =>
                  context.push('/home/spaces/${space.id}/balances'),
              child: Text(l10n.spaceCoverViewBalances),
            ),
            child: SpaceBalances(spaceId: space.id, compact: true),
          ),
          const SectionGap(),
          CoverSection(
            title: l10n.spaceTicketsTitle,
            action: TextButton(
              onPressed: () => context.push('/home/spaces/${space.id}/tickets'),
              child: Text(l10n.spaceCoverViewAll),
            ),
            child: SpaceTicketsPreview(spaceId: space.id),
          ),
          const SizedBox(height: 88),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _scanning || peopleError || !contextReady
                  ? null
                  : () => _addTicket(space),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(l10n.spaceAddTicket),
            )
          : null,
    );
  }

  void _addTicket(Space space) {
    ref
        .read(pendingSpaceLinkProvider.notifier)
        .set(space.id, space.name, space.kind);
    showScanEntrySheet(
      context,
      ref,
      onBusy: (busy) {
        if (mounted) {
          setState(() => _scanning = busy);
        }
      },
    );
  }
}
