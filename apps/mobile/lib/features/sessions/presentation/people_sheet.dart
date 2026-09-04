import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../spaces/data/spaces_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../spaces/domain/space_identities.dart';
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
        // Un MANUAL ya vinculado cuya cuenta también es miembro es UNA
        // persona (BUG-6): listarlo dos veces la partiría en dos deudas y
        // podría enfrentarla consigo misma. El actor histórico no se toca;
        // aquí solo se elige con qué identidad entra en ESTE ticket, y la
        // cuenta manda porque puede leer y confirmar.
        final memberUids = {for (final member in ordered) member.uid};
        final shown = [
          for (final manual in manuals)
            if (!memberUids.contains(manual.linkedUid)) manual,
        ];
        final people = [
          for (final member in ordered)
            (
              uid: member.uid,
              manualId: '',
              // Un INVITADO no tiene perfil público: su nombre es el que
              // congeló al unirse al contexto (ADR-034).
              name: member.isGuest
                  ? (member.displayName ?? '…')
                  : member.uid == myUid
                  ? ref.watch(hostDisplayNameProvider)
                  : ref
                            .watch(publicProfileProvider(member.uid))
                            .value
                            ?.displayName ??
                        '…',
            ),
          for (final manual in shown)
            (uid: '', manualId: manual.id, name: manual.displayName),
        ];
        final complete = contextReadyForExpenses(
          target.kind,
          spaceEconomicIdentities(
            members: spaceMembers,
            manuals: manuals,
          ).length,
        );
        if (payerIndex >= people.length) payerIndex = 0;

        final c = context.salda;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            TokenLayout.screenMargin,
            0,
            TokenLayout.screenMargin,
            TokenSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.peopleSheetTitle,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text(
                target.name,
                style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: TokenSpacing.xxl),

              TextField(
                controller: sessionName,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.sessionNameLabel),
              ),

              // ── Quién participa ──────────────────────────────────────
              // Una persona sin cuenta se enseña IGUAL que una con cuenta:
              // mismo avatar, mismo tamaño, misma fila. Lo único que la
              // distingue es una etiqueta que explica su situación, no un
              // trato de participante de segunda (ADR-033).
              const SizedBox(height: TokenSpacing.xxl),
              SectionHeader(title: l10n.peopleSectionTitle),
              SaldaCardList(
                children: [
                  for (final person in people)
                    _PersonRow(
                      name: person.name,
                      seed: person.manualId.isEmpty
                          ? person.uid
                          : person.manualId,
                      isManual: person.manualId.isNotEmpty,
                    ),
                ],
              ),
              if (!complete) ...[
                const SizedBox(height: TokenSpacing.md),
                EmptyState(
                  icon: Icons.person_add_alt,
                  title: target.kind == SpaceKind.relationship
                      ? l10n.relationshipNeedsAcceptance
                      : l10n.groupNeedsMembers,
                  body: target.kind == SpaceKind.relationship
                      ? l10n.relationshipNeedsAcceptanceBody
                      : l10n.groupNeedsMembersBody,
                ),
              ],

              // ── Cómo se reparte ──────────────────────────────────────
              const SizedBox(height: TokenSpacing.xxl),
              SectionHeader(title: l10n.splitSectionTitle),
              SegmentedButton<SplitMode>(
                segments: [
                  ButtonSegment(
                    value: SplitMode.equal,
                    icon: const Icon(Icons.balance, size: 18),
                    label: Text(l10n.splitEqual),
                  ),
                  ButtonSegment(
                    value: SplitMode.byItem,
                    icon: const Icon(Icons.checklist, size: 18),
                    label: Text(l10n.splitByItem),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => mode = selection.first),
              ),
              const SizedBox(height: TokenSpacing.sm),
              Text(
                mode == SplitMode.equal
                    ? l10n.splitEqualHelp
                    : l10n.splitByItemHelp,
                style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
              ),

              // ── Quién paga ───────────────────────────────────────────
              // Cualquiera de las identidades puede pagar, incluido un
              // MANUAL: el modelo económico ya lo admite (BUG-6).
              const SizedBox(height: TokenSpacing.xxl),
              SectionHeader(title: l10n.payerQuestion),
              SaldaCardList(
                children: [
                  for (var index = 0; index < people.length; index++)
                    _PersonRow(
                      name: people[index].name,
                      seed: people[index].manualId.isEmpty
                          ? people[index].uid
                          : people[index].manualId,
                      isManual: people[index].manualId.isNotEmpty,
                      selected: payerIndex == index,
                      onTap: () => setState(() => payerIndex = index),
                    ),
                ],
              ),

              const SizedBox(height: TokenSpacing.xxl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: !complete || creating
                      ? null
                      : () => create(people),
                  icon: creating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share, size: 18),
                  label: Text(l10n.createAndShare),
                ),
              ),
              if (!complete) ...[
                const SizedBox(height: TokenSpacing.sm),
                Text(
                  l10n.createDisabledHelp,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.textMuted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Fila de una persona en la hoja de reparto.
///
/// Cuenta, INVITADO y MANUAL se pintan EXACTAMENTE igual: la diferencia es
/// una etiqueta que explica la situación, no un tamaño menor ni un icono
/// gris. Quien no tiene la app pesa lo mismo económicamente (ADR-033).
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.seed,
    required this.isManual,
    this.selected,
    this.onTap,
  });

  final String name;
  final String seed;
  final bool isManual;

  /// Null = la fila solo informa; no-null = es seleccionable.
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.salda;
    final isSelected = selected ?? false;
    return ListTile(
      onTap: onTap,
      selected: isSelected,
      selectedTileColor: c.primaryMuted,
      leading: SaldaAvatar(seed: seed, label: name, radius: 17),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: isManual ? Text(l10n.personKindManual) : null,
      trailing: selected == null
          ? null
          : Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: isSelected ? c.primary : c.borderStrong,
            ),
    );
  }
}
