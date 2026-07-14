import 'dart:typed_data';

import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../scan/data/receipt_storage.dart';
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
          FutureBuilder(
            future: ref
                .read(sessionRepositoryProvider)
                .fetchTicketLines(t.path),
            builder: (context, snapshot) {
              final lines = snapshot.data ?? const <LineExport>[];
              if (snapshot.connectionState == ConnectionState.done &&
                  lines.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(TokenSpacing.lg),
                    child: Text(l10n.ticketNoLines,
                        style: theme.textTheme.bodySmall),
                  ),
                );
              }
              return Card(
                child: Column(children: [
                  for (final line in lines)
                    ListTile(
                      dense: true,
                      title: Text(line.name),
                      leading: line.quantityMilli == 1000
                          ? null
                          : Text(
                              line.quantityMilli % 1000 == 0
                                  ? '${line.quantityMilli ~/ 1000}×'
                                  : '${(line.quantityMilli / 1000).toStringAsFixed(3)} kg',
                              style: theme.textTheme.labelMedium,
                            ),
                      trailing: Text(
                        formatMoney(line.totalPrice),
                        style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                ]),
              );
            },
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
