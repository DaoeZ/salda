import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/create_session_controller.dart';

/// Hoja "Gente y reparto" (spec §2.1 paso 4): chips de personas frecuentes,
/// modo de reparto, pagador y crear+compartir en un toque.
Future<void> showPeopleSheet(BuildContext context, {String? suggestedName}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PeopleForm(suggestedName: suggestedName),
    ),
  );
}

class _PeopleForm extends ConsumerStatefulWidget {
  const _PeopleForm({this.suggestedName});

  final String? suggestedName;

  @override
  ConsumerState<_PeopleForm> createState() => _PeopleFormState();
}

class _PeopleFormState extends ConsumerState<_PeopleForm> {
  final _newPerson = TextEditingController();
  late final _sessionName =
      TextEditingController(text: widget.suggestedName ?? '');
  final List<String> _people = [];
  var _mode = SplitMode.equal;
  var _payerIndex = 0;

  @override
  void dispose() {
    _newPerson.dispose();
    _sessionName.dispose();
    super.dispose();
  }

  List<String> get _allNames =>
      [ref.read(hostDisplayNameProvider), ..._people];

  void _addPerson(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _people.contains(trimmed)) return;
    setState(() {
      _people.add(trimmed);
      _newPerson.clear();
    });
  }

  Future<void> _create() async {
    final sid = await ref.read(createSessionControllerProvider.notifier).create(
          participantNames: _allNames,
          payerIndex: _payerIndex,
          splitMode: _mode,
          sessionName: _sessionName.text.trim().isEmpty
              ? (widget.suggestedName ?? 'Cuenta')
              : _sessionName.text.trim(),
        );
    if (sid != null && mounted) {
      Navigator.pop(context);
      context.go('/session/$sid/share');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final frequent = ref.watch(frequentPeopleProvider).value ?? const [];
    final creating =
        ref.watch(createSessionControllerProvider) is AsyncLoading;
    final names = _allNames;

    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.peopleSheetTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: TokenSpacing.md),
          TextField(
            controller: _sessionName,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.sessionNameLabel),
          ),
          const SizedBox(height: TokenSpacing.md),
          Wrap(
            spacing: TokenSpacing.sm,
            runSpacing: TokenSpacing.xs,
            children: [
              InputChip(
                avatar: const Icon(Icons.person, size: 18),
                label: Text(
                    '${ref.watch(hostDisplayNameProvider)} (${l10n.peopleYou})'),
                onPressed: null,
              ),
              for (final person in _people)
                InputChip(
                  label: Text(person),
                  onDeleted: () => setState(() {
                    _people.remove(person);
                    _payerIndex = 0;
                  }),
                ),
              // Frecuentes aún no elegidas: un toque para añadir (RF-40).
              for (final person in frequent.where(
                  (f) => !_people.contains(f.name)))
                ActionChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(person.name),
                  onPressed: () => _addPerson(person.name),
                ),
            ],
          ),
          TextField(
            controller: _newPerson,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: l10n.peopleAddHint,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _addPerson(_newPerson.text),
              ),
            ),
            onSubmitted: _addPerson,
          ),
          const SizedBox(height: TokenSpacing.lg),
          SegmentedButton<SplitMode>(
            segments: [
              ButtonSegment(
                  value: SplitMode.equal,
                  icon: const Icon(Icons.balance),
                  label: Text(l10n.splitEqual)),
              ButtonSegment(
                  value: SplitMode.byItem,
                  icon: const Icon(Icons.checklist),
                  label: Text(l10n.splitByItem)),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(height: TokenSpacing.lg),
          Row(children: [
            Text(l10n.payerQuestion, style: theme.textTheme.bodyMedium),
            const SizedBox(width: TokenSpacing.md),
            Expanded(
              child: DropdownButton<int>(
                value: _payerIndex,
                isExpanded: true,
                items: [
                  for (var i = 0; i < names.length; i++)
                    DropdownMenuItem(value: i, child: Text(names[i])),
                ],
                onChanged: (value) =>
                    setState(() => _payerIndex = value ?? 0),
              ),
            ),
          ]),
          const SizedBox(height: TokenSpacing.lg),
          FilledButton.icon(
            onPressed: _people.isEmpty || creating ? null : _create,
            icon: creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            label: Text(
                _people.isEmpty ? l10n.peopleNeedTwo : l10n.createAndShare),
          ),
          const SizedBox(height: TokenSpacing.sm),
        ],
      ),
    );
  }
}
