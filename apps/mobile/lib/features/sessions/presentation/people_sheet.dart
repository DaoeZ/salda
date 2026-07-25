import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../spaces/data/spaces_repository.dart';
import '../../spaces/domain/space_models.dart';
import '../application/create_session_controller.dart';

/// Configura el reparto usando los miembros registrados del contexto. La
/// relación o grupo decide quién participa; el ticket no crea una segunda
/// lista social independiente.
Future<void> showPeopleSheet(BuildContext context, {String? suggestedName}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _PeopleForm(suggestedName: suggestedName),
      ),
    );

class _PeopleForm extends ConsumerStatefulWidget {
  const _PeopleForm({this.suggestedName});
  final String? suggestedName;

  @override
  ConsumerState<_PeopleForm> createState() => _PeopleFormState();
}

class _PeopleFormState extends ConsumerState<_PeopleForm> {
  late final sessionName = TextEditingController(
    text: widget.suggestedName ?? '',
  );
  var mode = SplitMode.equal;
  var payerIndex = 0;

  @override
  void dispose() {
    sessionName.dispose();
    super.dispose();
  }

  Future<void> create(
    List<({String uid, String manualId, String name})> people,
  ) async {
    final sid = await ref
        .read(createSessionControllerProvider.notifier)
        .create(
          participantNames: people.map((person) => person.name).toList(),
          participantUids: people.map((person) => person.uid).toList(),
          participantManualIds: people
              .map((person) => person.manualId)
              .toList(),
          payerIndex: payerIndex,
          splitMode: mode,
          sessionName: sessionName.text.trim().isEmpty
              ? (widget.suggestedName ?? 'Cuenta')
              : sessionName.text.trim(),
        );
    if (sid != null && mounted) {
      Navigator.pop(context);
      context.go('/home/session/$sid/share');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final target = ref.watch(pendingSpaceLinkProvider);
    if (target == null) {
      return Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Text(l10n.ticketContextMissing, textAlign: TextAlign.center),
      );
    }
    final members = ref.watch(spaceMembersProvider(target.id));
    final creating = ref.watch(createSessionControllerProvider) is AsyncLoading;

    return members.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(TokenSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Text(l10n.spacesLoadError, textAlign: TextAlign.center),
      ),
      data: (spaceMembers) {
        final myUid = ref.watch(currentUserIdFromSpacesProvider);
        final ordered = [...spaceMembers]
          ..sort((a, b) => a.uid == myUid ? -1 : (b.uid == myUid ? 1 : 0));
        // Los participantes manuales del contexto entran en el reparto en
        // igualdad de condiciones: no tienen cuenta, pero sí identidad
        // estable y peso económico (ADR-033).
        final manuals =
            ref.watch(spaceManualParticipantsProvider(target.id)).value ??
            const <ManualParticipant>[];
        final people = [
          for (final member in ordered)
            (
              uid: member.uid,
              manualId: '',
              name: member.uid == myUid
                  ? ref.watch(hostDisplayNameProvider)
                  : ref
                            .watch(publicProfileProvider(member.uid))
                            .value
                            ?.displayName ??
                        '…',
            ),
          for (final manual in manuals)
            (uid: '', manualId: manual.id, name: manual.displayName),
        ];
        final complete = target.kind == SpaceKind.relationship
            ? people.length == 2
            : people.length >= 3;
        if (payerIndex >= people.length) payerIndex = 0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.peopleSheetTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: TokenSpacing.xs),
              Text(target.name, style: theme.textTheme.bodyMedium),
              const SizedBox(height: TokenSpacing.md),
              TextField(
                controller: sessionName,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.sessionNameLabel),
              ),
              const SizedBox(height: TokenSpacing.md),
              Wrap(
                spacing: TokenSpacing.sm,
                runSpacing: TokenSpacing.xs,
                children: [
                  for (final person in people)
                    Chip(
                      avatar: const Icon(Icons.person, size: 18),
                      label: Text(person.name),
                    ),
                ],
              ),
              if (!complete) ...[
                const SizedBox(height: TokenSpacing.sm),
                Text(
                  target.kind == SpaceKind.relationship
                      ? l10n.relationshipNeedsAcceptance
                      : l10n.groupNeedsMembers,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: TokenSpacing.lg),
              SegmentedButton<SplitMode>(
                segments: [
                  ButtonSegment(
                    value: SplitMode.equal,
                    icon: const Icon(Icons.balance),
                    label: Text(l10n.splitEqual),
                  ),
                  ButtonSegment(
                    value: SplitMode.byItem,
                    icon: const Icon(Icons.checklist),
                    label: Text(l10n.splitByItem),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) =>
                    setState(() => mode = selection.first),
              ),
              const SizedBox(height: TokenSpacing.lg),
              DropdownButtonFormField<int>(
                initialValue: people.isEmpty ? null : payerIndex,
                decoration: InputDecoration(labelText: l10n.payerQuestion),
                items: [
                  for (var index = 0; index < people.length; index++)
                    DropdownMenuItem(
                      value: index,
                      child: Text(people[index].name),
                    ),
                ],
                onChanged: (value) => setState(() => payerIndex = value ?? 0),
              ),
              const SizedBox(height: TokenSpacing.lg),
              FilledButton.icon(
                onPressed: !complete || creating ? null : () => create(people),
                icon: creating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(l10n.createAndShare),
              ),
            ],
          ),
        );
      },
    );
  }
}
