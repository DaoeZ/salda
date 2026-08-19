import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../scan/data/receipt_storage.dart';
import '../../spaces/data/spaces_repository.dart';
import '../../spaces/presentation/space_title_text.dart';
import '../application/session_providers.dart';
import '../data/session_repository.dart';
import '../data/ticket_links_repository.dart';
import '../domain/session_models.dart';
import '../domain/ticket_link_models.dart';
import 'ticket_correction_sheets.dart';

/// Datos de navegación al detalle de un ticket (van como `extra` de la ruta).
class TicketRef {
  const TicketRef({
    required this.sessionId,
    required this.ticket,
    required this.payerName,
  });

  final String sessionId;
  final SessionTicket ticket;
  final String payerName;
}

/// Detalle de un ticket del historial (RF-83): foto original, líneas OCR,
/// quién pagó, fecha e importe.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticket});

  final TicketRef ticket;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  /// Corregir el gasto y elegir lo que consumí son cosas distintas y no
  /// pueden compartir el mismo toque sobre la misma fila (A11c). El modo lo
  /// deja explícito: fuera de él, la pantalla es la de siempre.
  var _correcting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ticket = widget.ticket;
    final t = ticket.ticket;
    // Auditar no es intervenir (A11b): quien abre el ticket de otro lo ve
    // entero, pero no se le ofrece ni una acción que las Rules le vayan a
    // rechazar — compartirlo por enlace y vincularlo a un espacio son del
    // dueño de la sesión.
    final canEdit = ref.watch(canEditSessionProvider(ticket.sessionId));
    // Corregir el CONTENIDO sí lo puede quien administra el grupo (A11c).
    final canCorrect = ref.watch(
      canCorrectTicketProvider((
        sessionId: ticket.sessionId,
        spaceId: t.spaceId ?? '',
      )),
    );
    if (_correcting && !canCorrect) _correcting = false;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.merchantName),
        actions: [
          if (canCorrect)
            IconButton(
              tooltip: _correcting
                  ? l10n.ticketCorrectDone
                  : l10n.ticketCorrectAction,
              icon: Icon(_correcting ? Icons.check : Icons.edit_outlined),
              onPressed: () => setState(() => _correcting = !_correcting),
            ),
          if (canEdit) ...[
            _TicketLinkAction(ticketRef: ticket),
            _SpaceLinkAction(ticket: t),
          ],
        ],
      ),
      body: ScreenBody(
        children: [
          if (_correcting) ...[
            Text(l10n.ticketCorrectBanner, style: theme.textTheme.bodySmall),
            const SizedBox(height: TokenSpacing.md),
          ],
          SaldaCard(
            padding: const EdgeInsets.all(TokenSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.merchantName,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: TokenSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(t.grandTotal, size: MoneySize.large),
                ),
                const SizedBox(height: TokenSpacing.lg),
                _TicketFact(
                  icon: Icons.account_balance_wallet_outlined,
                  label: l10n.ticketPaidBy(ticket.payerName),
                ),
                if (t.date != null) ...[
                  const SizedBox(height: TokenSpacing.sm),
                  _TicketFact(icon: Icons.event_outlined, label: t.date!),
                ],
                // Quién tocó este gasto por última vez. Importa sobre todo
                // cuando NO fue quien lo subió (A11c).
                if (t.lastEditedByUid != null) ...[
                  const SizedBox(height: TokenSpacing.sm),
                  _CorrectionSignature(ticket: t),
                ],
                if (_correcting) ...[
                  const SizedBox(height: TokenSpacing.md),
                  // El total y la suma de los productos son cosas distintas
                  // —impuestos, propina y descuentos viven en la diferencia—,
                  // así que al corregir se enseñan las dos. Que no cuadren no
                  // es necesariamente un error, pero esconderlo sí lo sería.
                  _LineSumCheck(ticketPath: t.path, grandTotal: t.grandTotal),
                  const SizedBox(height: TokenSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => showTicketHeaderCorrection(
                      context,
                      ref,
                      ticketPath: t.path,
                      merchantName: t.merchantName,
                      date: t.date,
                      grandTotal: t.grandTotal,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.ticketCorrectHeaderTitle),
                  ),
                ],
              ],
            ),
          ),
          if (t.kind == 'scanned') ...[
            const SectionGap(),
            SectionHeader(title: l10n.ticketPhotoTitle),
            _TicketPhoto(ticketPath: t.path, uploaded: t.imagePath != null),
          ],
          const SectionGap(),
          SectionHeader(title: l10n.reviewLines),
          _TicketLines(ticketRef: ticket, correcting: _correcting),
        ],
      ),
    );
  }
}

/// Dato secundario del ticket: icono tenue y texto, en fila. Evita una
/// tabla densa sin esconder nada detras de mas toques.
class _TicketFact extends StatelessWidget {
  const _TicketFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    return Row(
      children: [
        Icon(icon, size: 16, color: c.textMuted),
        const SizedBox(width: TokenSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Vincular/desvincular el ticket a un espacio compartido (P4). Solo cambia
/// el campo `spaceId` del ticket: participantes, asignaciones, balances y
/// pagos quedan intactos. Máximo un espacio por ticket (el campo sobrescribe).
class _SpaceLinkAction extends ConsumerStatefulWidget {
  const _SpaceLinkAction({required this.ticket});

  final SessionTicket ticket;

  @override
  ConsumerState<_SpaceLinkAction> createState() => _SpaceLinkActionState();
}

class _SpaceLinkActionState extends ConsumerState<_SpaceLinkAction> {
  // El TicketRef llega por `extra` (estático): reflejamos aquí el vínculo
  // actual para que la acción responda sin recargar la pantalla.
  String? _spaceId;

  @override
  void initState() {
    super.initState();
    _spaceId = widget.ticket.spaceId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spaces = ref.watch(mySpacesProvider).value ?? const [];
    if (spaces.isEmpty && (_spaceId == null || _spaceId!.isEmpty)) {
      return const SizedBox.shrink();
    }
    final linked = _spaceId != null && _spaceId!.isNotEmpty;
    if (widget.ticket.isContextual) {
      return IconButton(
        onPressed: null,
        tooltip: l10n.ticketContextLocked,
        icon: const Icon(Icons.group_work),
      );
    }
    return PopupMenuButton<String>(
      icon: Icon(
        linked ? Icons.group_work : Icons.group_work_outlined,
        color: linked ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: l10n.spaceLinkTooltip,
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final repo = ref.read(spacesRepositoryProvider);
        try {
          if (value == 'unlink') {
            await repo.unlinkTicket(widget.ticket.path);
            setState(() => _spaceId = null);
            messenger.showSnackBar(SnackBar(content: Text(l10n.spaceUnlinked)));
          } else {
            await repo.linkTicket(widget.ticket.path, value);
            setState(() => _spaceId = value);
            messenger.showSnackBar(SnackBar(content: Text(l10n.spaceLinked)));
          }
        } on Object {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.spaceActionError)),
          );
        }
      },
      itemBuilder: (_) => [
        for (final space in spaces)
          if (space.isActive && space.id != _spaceId)
            PopupMenuItem(
              value: space.id,
              child: SpaceTitleText(
                spaceId: space.id,
                storedName: space.name,
                format: l10n.spaceLinkTo,
              ),
            ),
        if (linked)
          PopupMenuItem(value: 'unlink', child: Text(l10n.spaceUnlink)),
      ],
    );
  }
}

/// Líneas del ticket EN VIVO con selección del creador (P2.1): el owner
/// marca lo que consumió exactamente igual que un invitado — toggle en
/// líneas de una unidad, stepper de unidades en las de varias — y ve en
/// tiempo real lo que eligen los demás. Lo no reclamado recae en el pagador
/// (residual), así que la selección explícita nunca duplica importes.
/// Suma de los productos frente al total del ticket, con el mismo lenguaje
/// que la revisión previa al guardado: «cuadra» o «descuadre de X».
///
/// Es informativo a propósito. Un ticket con impuestos o propina descuadra
/// por construcción y sigue siendo correcto; quien corrige necesita ver los
/// dos números para decidir si lo que está mal es un producto o el total.
class _LineSumCheck extends ConsumerWidget {
  const _LineSumCheck({required this.ticketPath, required this.grandTotal});

  final String ticketPath;
  final Money grandTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lines = ref.watch(ticketLinesProvider(ticketPath)).value;
    if (lines == null) return const SizedBox.shrink();

    var sum = Money.zero;
    for (final line in lines) {
      sum += line.totalPrice;
    }
    final delta = sum - grandTotal;
    // Misma tolerancia que la revisión: el 1 % del total, mínimo 2 céntimos.
    final tolerance = grandTotal.abs().cents ~/ 100;
    final balanced = delta.abs().cents <= (tolerance > 2 ? tolerance : 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TicketFact(
          icon: Icons.functions_outlined,
          label: '${l10n.reviewComputedTotal}: ${formatMoney(sum)}',
        ),
        const SizedBox(height: TokenSpacing.sm),
        StatusBadge(
          balanced
              ? l10n.reviewBalanced
              : l10n.reviewMismatch(formatMoney(delta.abs())),
          tone: balanced ? BadgeTone.positive : BadgeTone.warning,
          icon: balanced ? Icons.check_rounded : Icons.error_outline_rounded,
        ),
      ],
    );
  }
}

/// Firma de la última corrección, con el nombre público de quien la hizo.
class _CorrectionSignature extends ConsumerWidget {
  const _CorrectionSignature({required this.ticket});

  final SessionTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(publicProfileProvider(ticket.lastEditedByUid!));
    return _TicketFact(
      icon: Icons.history_edu_outlined,
      label: l10n.ticketCorrectedBy(
        profile.value?.displayName ?? '…',
        (ticket.lastEditedAt ?? DateTime.now()).toLocal(),
      ),
    );
  }
}

class _TicketLines extends ConsumerWidget {
  const _TicketLines({required this.ticketRef, required this.correcting});

  final TicketRef ticketRef;
  final bool correcting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ticket = ticketRef.ticket;
    final linesAsync = ref.watch(ticketLinesProvider(ticket.path));
    final detail = ref.watch(sessionDetailProvider(ticketRef.sessionId)).value;
    final participants =
        ref.watch(participantsProvider(ticketRef.sessionId)).value ??
        const <SessionParticipant>[];

    final lines = linesAsync.value ?? const <TicketLine>[];
    if (!linesAsync.hasValue) return const SkeletonList(rows: 3);
    if (lines.isEmpty) {
      return EmptyState(
        icon: Icons.list_alt_outlined,
        title: l10n.ticketNoLines,
        body: l10n.ticketNoLinesBody,
      );
    }

    final names = {for (final p in participants) p.id: p.name};
    // Editar el ticket y elegir MI consumo son dos autoridades distintas.
    // La segunda no depende de ser dueño de la sesión: depende de tener un
    // participante reclamado por mi UID, que es EXACTAMENTE lo que
    // comprueban las Rules (`claimedBy(pid) == uid`). Un miembro del grupo
    // que abre el ticket de otro elige lo que consumió sin tocar nada más.
    //
    // Repliegue por `isOwner` para las sesiones antiguas, donde el
    // participante del anfitrión pudo quedar sin reclamar: ahí el dueño
    // sigue eligiendo como siempre.
    final myUid = ref.watch(currentUserIdFromSpacesProvider);
    final canEdit = ref.watch(canEditSessionProvider(ticketRef.sessionId));
    final myPid =
        (myUid.isEmpty
            ? null
            : participants
                  .where((p) => p.claimedByDevice == myUid)
                  .map((p) => p.id)
                  .firstOrNull) ??
        (canEdit
            ? participants.where((p) => p.isOwner).map((p) => p.id).firstOrNull
            : null);
    final mode =
        ticket.splitModeOverride ?? detail?.splitModeDefault ?? SplitMode.equal;
    // El estado de la sesión vive en un documento que el miembro NO puede
    // leer (shareCode). Quien sí lo lee exige `open` como siempre; para
    // quien no, mandan las Rules: si estuviera cerrada, la escritura se
    // rechaza y la pantalla lo dice.
    // En modo corrección la fila sirve para arreglar el producto, no para
    // elegir consumo: un mismo toque no puede significar dos cosas (A11c).
    final canPick =
        !correcting &&
        myPid != null &&
        mode == SplitMode.byItem &&
        (!canEdit || detail?.summary.status == SessionStatus.open);

    // «A partes iguales» no mira las líneas: repartirlo es dividir el total
    // entre quienes participan. Sin decirlo, la pantalla mentía — cada
    // producto salía rotulado «sin reclamar (para Alba)», que es la lectura
    // del OTRO modo, y quien audita concluía que no le tocaba nada.
    //
    // El importe se pide al MISMO motor que usa recompute, con el mismo
    // universo de participantes (activos, en su orden): es el número que ya
    // existe, no un cálculo nuevo.
    final activePids = [
      for (final p in participants)
        if (p.active) p.id,
    ];
    final myShare = mode == SplitMode.byItem || activePids.isEmpty
        ? null
        : SplitEngine.splitTicket(
            participantIds: activePids,
            mode: SplitMode.equal,
            ticket: SplitTicketInput(grandTotal: ticket.grandTotal),
          )[myPid];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPick) ...[
          Text(l10n.ticketPickHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: TokenSpacing.sm),
        ],
        if (mode == SplitMode.equal) ...[
          Text(
            l10n.ticketSplitEqualHint(activePids.length),
            style: theme.textTheme.bodySmall,
          ),
          if (myShare != null) ...[
            const SizedBox(height: TokenSpacing.xs),
            Text(
              l10n.ticketSplitYourShare(formatMoney(myShare)),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: TokenSpacing.sm),
        ],
        SaldaCardList(
          children: [
            for (final line in lines)
              _LineTile(
                line: line,
                myPid: myPid,
                canPick: canPick,
                canEdit: canEdit,
                correcting: correcting,
                names: names,
                showAssignment: mode == SplitMode.byItem,
                payerName: ticketRef.payerName,
              ),
          ],
        ),
      ],
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({
    required this.line,
    required this.myPid,
    required this.canPick,
    required this.canEdit,
    required this.correcting,
    required this.showAssignment,
    required this.names,
    required this.payerName,
  });

  /// Modo corrección (A11c): la fila abre el arreglo del producto.
  final bool correcting;

  final TicketLine line;
  final String? myPid;
  final bool canPick;

  /// Cambiar la FORMA de la línea (pasarla al modelo de unidades) es tocar
  /// el ticket, no elegir consumo: eso sigue siendo del dueño de la sesión.
  final bool canEdit;

  /// Quién consume cada unidad solo significa algo en «cada uno lo suyo».
  /// A partes iguales, esos rótulos describían un reparto que no se aplica.
  final bool showAssignment;
  final Map<String, String> names;
  final String payerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pid = myPid;
    final myUnits = pid == null ? 0 : line.weightOf(pid);
    final mine = myUnits > 0;
    final interactive = canPick && line.assignmentType != 'all';

    // La selección ya no es siempre del dueño: para un miembro del grupo la
    // autoridad la deciden las Rules (sesión abierta, modo por líneas), y el
    // cliente no puede saber el estado de la sesión. Si la rechazan, se dice.
    Future<void> guard(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
      } on Object {
        messenger.showSnackBar(SnackBar(content: Text(l10n.ticketPickError)));
      }
    }

    Future<void> toggleUnit(int unit) => guard(
      () => ref
          .read(sessionRepositoryProvider)
          .setUnitConsumer(
            line.path,
            unit: unit,
            participantId: pid!,
            selected: !line.unitIsMine(unit, pid),
          ),
    );

    Future<void> convertToUnits() async {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(l10n.unitsUpgradeTitle),
              content: Text(l10n.unitsUpgradeBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(l10n.unitsUpgradeAction),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !context.mounted) return;
      await ref
          .read(sessionRepositoryProvider)
          .convertLineToUnitAssignment(
            line.path,
            editorPid: pid!,
            unitCount: line.units,
          );
    }

    Future<void> setUnits(int units) {
      // Mapa completo deseado; 0 elimina la entrada (contrato del repo).
      final weights = Map<String, int>.from(line.weights);
      weights[pid!] = units;
      return guard(
        () => ref
            .read(sessionRepositoryProvider)
            .setLineAssignment(line.path, weights, editorPid: pid),
      );
    }

    final others = pid == null ? const <String>[] : line.othersThan(pid);
    final subtitle = line.assignmentType == 'all'
        ? l10n.lineForAll
        : others.isEmpty
        ? null
        : (mine ? l10n.lineSharedWith : l10n.lineTakenBy)(
            others.map((p) => names[p] ?? '?').join(', '),
          );

    final unitDescriptions = line.usesUnitModel
        ? [
            for (var unit = 0; unit < line.units; unit++)
              l10n.unitAssignment(
                unit + 1,
                line.consumersOf(unit).isEmpty
                    ? l10n.unitResidual(payerName)
                    : line
                          .consumersOf(unit)
                          .map((p) => names[p] ?? '?')
                          .join(', '),
              ),
          ]
        : const <String>[];
    final effectiveSubtitle = !showAssignment
        ? null
        : line.usesUnitModel
        ? (line.units <= 4
              ? unitDescriptions.join('\n')
              : l10n.unitCompactSummary(
                  [
                    for (var unit = 0; unit < line.units; unit++)
                      if (pid != null && line.unitIsMine(unit, pid)) unit,
                  ].length,
                  line.units,
                  [
                    for (var unit = 0; unit < line.units; unit++)
                      if (line.consumersOf(unit).isEmpty) unit,
                  ].length,
                ))
        : subtitle;

    Widget unitChip(int unit) {
      final consumers = line.consumersOf(unit);
      final selected = pid != null && consumers.contains(pid);
      final detail = consumers.isEmpty
          ? l10n.unitResidual(payerName)
          : consumers.map((p) => names[p] ?? '?').join(', ');
      return Tooltip(
        message: l10n.unitAssignment(unit + 1, detail),
        child: FilterChip(
          selected: selected,
          onSelected: interactive ? (_) => toggleUnit(unit) : null,
          label: Text('${unit + 1}'),
          avatar: Icon(
            consumers.length > 1 ? Icons.group_outlined : Icons.person_outline,
            size: 16,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          onTap: correcting
              ? () => showLineCorrection(
                  context,
                  ref,
                  line: line,
                  names: names,
                )
              : interactive && line.units == 1
              ? line.usesUnitModel
                    ? () => toggleUnit(0)
                    : () => setUnits(mine ? 0 : 1)
              : null,
          leading: correcting
              ? const Icon(Icons.edit_outlined)
              : interactive && line.units == 1
              ? Icon(
                  (line.usesUnitModel ? line.unitIsMine(0, pid!) : mine)
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: (line.usesUnitModel ? line.unitIsMine(0, pid!) : mine)
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                )
              : null,
          title: Row(
            children: [
              if (line.quantityMilli != 1000) ...[
                Text(
                  line.quantityMilli % 1000 == 0
                      ? '${line.quantityMilli ~/ 1000}×'
                      : '${(line.quantityMilli / 1000).toStringAsFixed(3)} kg',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: TokenSpacing.xs),
              ],
              Expanded(
                child: Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: effectiveSubtitle == null
              ? null
              : Text(
                  effectiveSubtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Text(
              formatMoney(line.totalPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        if (interactive && line.units > 1 && line.usesUnitModel)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TokenSpacing.lg,
              0,
              TokenSpacing.lg,
              TokenSpacing.sm,
            ),
            child: line.units <= 12
                ? Wrap(
                    spacing: TokenSpacing.xs,
                    runSpacing: TokenSpacing.xs,
                    children: [
                      for (var unit = 0; unit < line.units; unit++)
                        unitChip(unit),
                    ],
                  )
                : SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: line.units,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: TokenSpacing.xs),
                      itemBuilder: (_, unit) => unitChip(unit),
                    ),
                  ),
          ),
        // Migrar la línea al modelo de unidades reescribe su asignación
        // entera: es edición del ticket, no selección propia.
        if (canEdit && interactive && line.units > 1 && !line.usesUnitModel)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TokenSpacing.lg,
              0,
              TokenSpacing.lg,
              TokenSpacing.sm,
            ),
            child: FilledButton.tonalIcon(
              onPressed: convertToUnits,
              icon: const Icon(Icons.grid_view_outlined),
              label: Text(l10n.unitsUpgradeAction),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Foto original del ticket: local-primero (instantánea/offline), memoizada.
/// Toca para abrirla a pantalla completa con zoom y desplazamiento.
class _TicketPhoto extends ConsumerWidget {
  const _TicketPhoto({required this.ticketPath, required this.uploaded});

  final String ticketPath;
  final bool uploaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final image = ref.watch(
      ticketImageProvider((ticketPath: ticketPath, uploaded: uploaded)),
    );

    return image.when(
      loading: () => Container(
        height: 220,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(TokenRadius.card),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) =>
          Text(l10n.ticketNoPhoto, style: theme.textTheme.bodySmall),
      data: (bytes) {
        if (bytes == null) {
          return Text(l10n.ticketNoPhoto, style: theme.textTheme.bodySmall);
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => _FullscreenPhoto(bytes: bytes),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TokenRadius.card),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

/// Foto a pantalla completa con zoom (pellizco) y desplazamiento.
class _FullscreenPhoto extends StatelessWidget {
  const _FullscreenPhoto({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }
}

/// Compartir ESTE ticket por enlace (ADR-036 rev. 2).
///
/// Un enlace por PERSONA, no uno por ticket. El anfitrión elige a quién se
/// lo manda y el destinatario queda grabado en el token, así que quien lo
/// recibe solo puede identificarse como esa persona. El enlace único que
/// publicaba la lista entera permitía reclamar a cualquiera del ticket.
class _TicketLinkAction extends ConsumerWidget {
  const _TicketLinkAction({required this.ticketRef});

  final TicketRef ticketRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      tooltip: l10n.ticketLinkAction,
      icon: const Icon(Icons.link),
      onPressed: () => _share(context, ref),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final manuals = await _manualsOf(ref);
    if (!context.mounted) return;
    if (manuals.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketLinkNoTargets)));
      return;
    }
    final target = await _chooseTarget(context, manuals, l10n);
    if (target == null || !context.mounted) return;
    await _shareFor(context, ref, target);
  }

  /// Elegir destinatario. Con uno solo se pregunta igual: el enlace nombra a
  /// una persona y conviene verlo antes de mandarlo.
  Future<EligibleManual?> _chooseTarget(
    BuildContext context,
    List<EligibleManual> manuals,
    AppLocalizations l10n,
  ) => showModalBottomSheet<EligibleManual>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(l10n.ticketLinkChooseTarget),
            subtitle: Text(l10n.ticketLinkChooseTargetHelp),
          ),
          for (final manual in manuals)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(manual.displayName),
              onTap: () => Navigator.pop(sheetContext, manual),
            ),
        ],
      ),
    ),
  );

  Future<void> _shareFor(
    BuildContext context,
    WidgetRef ref,
    EligibleManual target,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(ticketLinksRepositoryProvider);
    final t = ticketRef.ticket;
    // sessions/{sid}/accounts/{aid}/tickets/{tid}
    final segments = t.path.split('/');
    final accountId = segments.length > 3 ? segments[3] : '';

    // Estado breve de preparación: crear el enlace espera a la señal
    // autoritativa, así que puede tardar un instante tras editar el ticket.
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Se reutiliza SOLO el enlace de esa misma persona: el de otra no vale.
      final existing = await repo
          .watchActiveLink(ticketRef.sessionId, t.id, manualId: target.manualId)
          .first;
      if (existing == null &&
          !await repo.isProjectionReady(ticketRef.sessionId, t.id)) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.ticketLinkPreparing)),
        );
      }
      final link =
          existing ??
          await repo.createLink(
            sessionId: ticketRef.sessionId,
            accountId: accountId,
            ticketId: t.id,
            merchantName: t.merchantName,
            spaceId: t.spaceId ?? '',
            target: target,
          );
      if (!context.mounted) return;
      final url = TicketLinksRepository.linkUrlFor(
        AppEnvironment.hostingDomain,
        link.token,
      );
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${t.merchantName} · ${Brand.appName}\n'
              '${l10n.ticketLinkFor(target.displayName)}\n$url',
        ),
      );
    } on TicketLinkNotReady {
      // Recuperable: recompute no ha terminado. Se reintenta a mano.
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketLinkNotReady)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketLinkError)));
    }
  }

  /// Participantes MANUAL activos de la sesión del ticket. La identidad se
  /// toma de `manualId`, nunca del nombre: renombrar no rompe el enlace.
  Future<List<EligibleManual>> _manualsOf(WidgetRef ref) async {
    final snap = await FirebaseFirestore.instance
        .collection('sessions/${ticketRef.sessionId}/participants')
        .get();
    return [
      for (final doc in snap.docs)
        if (((doc.data()['manualId'] as String?) ?? '').isNotEmpty &&
            (doc.data()['active'] as bool? ?? true))
          EligibleManual(
            pid: doc.id,
            manualId: doc.data()['manualId'] as String,
            displayName: (doc.data()['name'] as String?) ?? '',
          ),
    ];
  }
}
