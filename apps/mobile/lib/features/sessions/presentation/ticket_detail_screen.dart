import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../scan/data/receipt_storage.dart';
import '../../spaces/data/spaces_repository.dart';
import '../../spaces/presentation/space_title_text.dart';
import '../application/session_providers.dart';
import '../data/session_repository.dart';
import '../data/ticket_links_repository.dart';
import '../domain/session_models.dart';
import '../domain/ticket_link_models.dart';

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
class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticket});

  final TicketRef ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = ticket.ticket;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.merchantName),
        actions: [
          _TicketLinkAction(ticketRef: ticket),
          _SpaceLinkAction(ticket: t),
        ],
      ),
      body: ScreenBody(
        children: [
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
          _TicketLines(ticketRef: ticket),
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
class _TicketLines extends ConsumerWidget {
  const _TicketLines({required this.ticketRef});

  final TicketRef ticketRef;

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
    final ownerPid = participants
        .where((p) => p.isOwner)
        .map((p) => p.id)
        .firstOrNull;
    final mode =
        ticket.splitModeOverride ?? detail?.splitModeDefault ?? SplitMode.equal;
    final canPick =
        ownerPid != null &&
        mode == SplitMode.byItem &&
        detail?.summary.status == SessionStatus.open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPick) ...[
          Text(l10n.ticketPickHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: TokenSpacing.sm),
        ],
        SaldaCardList(
          children: [
            for (final line in lines)
              _LineTile(
                line: line,
                ownerPid: ownerPid,
                canPick: canPick,
                names: names,
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
    required this.ownerPid,
    required this.canPick,
    required this.names,
    required this.payerName,
  });

  final TicketLine line;
  final String? ownerPid;
  final bool canPick;
  final Map<String, String> names;
  final String payerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pid = ownerPid;
    final myUnits = pid == null ? 0 : line.weightOf(pid);
    final mine = myUnits > 0;
    final interactive = canPick && line.assignmentType != 'all';

    Future<void> toggleUnit(int unit) => ref
        .read(sessionRepositoryProvider)
        .setUnitConsumer(
          line.path,
          unit: unit,
          participantId: pid!,
          selected: !line.unitIsMine(unit, pid),
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
      return ref
          .read(sessionRepositoryProvider)
          .setLineAssignment(line.path, weights, editorPid: pid);
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
    final effectiveSubtitle = line.usesUnitModel
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
          onTap: interactive && line.units == 1
              ? line.usesUnitModel
                    ? () => toggleUnit(0)
                    : () => setUnits(mine ? 0 : 1)
              : null,
          leading: interactive && line.units == 1
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
        if (interactive && line.units > 1 && !line.usesUnitModel)
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
