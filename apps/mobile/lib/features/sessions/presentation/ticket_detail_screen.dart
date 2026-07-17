import 'dart:typed_data';

import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../scan/data/receipt_storage.dart';
import '../application/session_providers.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';

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
      appBar: AppBar(title: Text(t.merchantName)),
      body: ListView(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.ticketPaidBy(ticket.payerName)),
              subtitle: t.date == null ? null : Text(t.date!),
              trailing: Text(
                formatMoney(t.grandTotal),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          const SizedBox(height: TokenSpacing.lg),
          if (t.kind == 'scanned') ...[
            _TicketPhoto(ticketPath: t.path, uploaded: t.imagePath != null),
            const SizedBox(height: TokenSpacing.lg),
          ],
          Text(l10n.reviewLines, style: theme.textTheme.titleMedium),
          const SizedBox(height: TokenSpacing.sm),
          _TicketLines(ticketRef: ticket),
        ],
      ),
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
    final detail =
        ref.watch(sessionDetailProvider(ticketRef.sessionId)).value;
    final participants =
        ref.watch(participantsProvider(ticketRef.sessionId)).value ??
            const <SessionParticipant>[];

    final lines = linesAsync.value ?? const <TicketLine>[];
    if (linesAsync.hasValue && lines.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.lg),
          child: Text(l10n.ticketNoLines, style: theme.textTheme.bodySmall),
        ),
      );
    }

    final names = {for (final p in participants) p.id: p.name};
    final ownerPid = participants
        .where((p) => p.isOwner)
        .map((p) => p.id)
        .firstOrNull;
    final mode = ticket.splitModeOverride ??
        detail?.splitModeDefault ??
        SplitMode.equal;
    final canPick = ownerPid != null &&
        mode == SplitMode.byItem &&
        detail?.summary.status == SessionStatus.open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPick) ...[
          Text(l10n.ticketPickHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: TokenSpacing.sm),
        ],
        Card(
          child: Column(children: [
            for (final line in lines)
              _LineTile(
                line: line,
                ownerPid: ownerPid,
                canPick: canPick,
                names: names,
              ),
          ]),
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
  });

  final TicketLine line;
  final String? ownerPid;
  final bool canPick;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pid = ownerPid;
    final myUnits = pid == null ? 0 : line.weightOf(pid);
    final mine = myUnits > 0;
    final interactive = canPick && line.assignmentType != 'all';

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

    return ListTile(
      dense: true,
      onTap: interactive && line.units == 1
          ? () => setUnits(mine ? 0 : 1)
          : null,
      leading: interactive
          ? Icon(
              mine ? Icons.check_circle : Icons.circle_outlined,
              color: mine
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            )
          : null,
      title: Row(children: [
        if (line.quantityMilli != 1000) ...[
          Text(
            line.quantityMilli % 1000 == 0
                ? '${line.quantityMilli ~/ 1000}×'
                : '${(line.quantityMilli / 1000).toStringAsFixed(3)} kg',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(width: TokenSpacing.xs),
        ],
        Expanded(child: Text(line.name)),
      ]),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (interactive && line.units > 1) ...[
            IconButton(
              tooltip: l10n.lineRemoveUnit,
              visualDensity: VisualDensity.compact,
              onPressed: myUnits > 0 ? () => setUnits(myUnits - 1) : null,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
            ),
            Text('$myUnits', style: theme.textTheme.titleSmall),
            IconButton(
              tooltip: l10n.lineAddUnit,
              visualDensity: VisualDensity.compact,
              onPressed:
                  myUnits < line.units ? () => setUnits(myUnits + 1) : null,
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
            const SizedBox(width: TokenSpacing.xs),
          ],
          Text(
            formatMoney(line.totalPrice),
            style:
                const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
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
