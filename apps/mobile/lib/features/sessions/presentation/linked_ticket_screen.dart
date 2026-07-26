import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../spaces/data/manual_link_repository.dart';
import '../../spaces/data/spaces_repository.dart' show spaceProvider;
import '../../spaces/domain/space_models.dart' show ManualLinkStatus;
import '../data/ticket_links_repository.dart';
import '../domain/ticket_link_models.dart';

/// Ticket abierto por enlace (Sprint 5, ADR-036): vista de SOLO LECTURA.
///
/// Enseña exactamente lo que el enlace concede —el ticket y sus líneas— y
/// nada del contexto: ni los demás tickets, ni la sesión, ni el grupo. Quien
/// se ha identificado como un MANUAL ve resaltado lo suyo, pero eso es
/// presentación: su actor económico sigue siendo `manual:{id}` y este acceso
/// no ha movido un solo balance.
class LinkedTicketScreen extends ConsumerStatefulWidget {
  const LinkedTicketScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<LinkedTicketScreen> createState() => _LinkedTicketScreenState();
}

class _LinkedTicketScreenState extends ConsumerState<LinkedTicketScreen> {
  TicketJoinLink? _link;
  TicketAccess? _access;
  Map<String, dynamic>? _ticket;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lines = const [];
  Map<String, String> _names = const {};
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(ticketLinksRepositoryProvider);
    try {
      final link = await repo.preview(widget.token);
      if (link == null) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context).ticketLinkInvalid;
        });
        return;
      }
      final firestore = FirebaseFirestore.instance;
      final access = await repo.myAccess(link.sessionId, link.ticketId);
      final ticket = await firestore.doc(link.ticketPath).get();
      final lines = await firestore
          .collection('${link.ticketPath}/lines')
          .orderBy('order')
          .get();
      // Los participantes NO se leen: el enlace no abre sus nombres. Solo
      // se conoce el nombre propio, que viene del enlace.
      final myName = link.manuals
          .where((m) => m.pid == (access?.pid ?? ''))
          .map((m) => m.displayName);
      if (!mounted) return;
      setState(() {
        _link = link;
        _access = access;
        _ticket = ticket.data();
        _lines = lines.docs;
        _names = myName.isEmpty
            ? const {}
            : {(access?.pid ?? ''): myName.first};
        _loading = false;
        // El ticket pudo borrarse, archivarse o moverse después de crear el
        // enlace: se degrada con un mensaje, nunca con una pantalla rota.
        if (ticket.data() == null) {
          _error = AppLocalizations.of(context).ticketLinkGone;
        }
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context).ticketLinkInvalid;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final link = _link;
    final ticket = _ticket;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (link == null || ticket == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(TokenSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _error ?? l10n.ticketLinkInvalid,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TokenSpacing.md),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: Text(l10n.commonDone),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final myPid = _access?.pid ?? '';
    final total = (ticket['grandTotal'] as int?) ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(link.merchantName)),
      body: ListView(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        children: [
          if (_access?.identifiesAManual ?? false) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(l10n.ticketLinkViewingAs(_names[myPid] ?? '')),
                subtitle: Text(l10n.ticketLinkTemporary),
                trailing: TextButton(
                  onPressed: _release,
                  child: Text(l10n.ticketLinkRelease),
                ),
              ),
            ),
            // Pedir la VINCULACIÓN (ADR-037): pasar de una identificación
            // temporal a que esta persona sea reconocida como ese
            // participante. Lo decide el anfitrión, no quien lo pide.
            if (link.spaceId.isNotEmpty)
              _ManualLinkRequestCard(
                spaceId: link.spaceId,
                manualId: _access!.manualId,
                displayName: _names[myPid] ?? '',
                // Procedencia: Rules la revalida contra ticketAccess y la
                // proyección autoritativa. No es una afirmación del cliente.
                sessionId: link.sessionId,
                ticketId: link.ticketId,
                pid: _access!.pid,
              ),
          ],
          const SizedBox(height: TokenSpacing.md),
          Text(l10n.ticketLinkLines, style: theme.textTheme.titleMedium),
          const SizedBox(height: TokenSpacing.sm),
          for (final line in _lines)
            _LineTile(data: line.data(), names: _names, highlightPid: myPid),
          const Divider(height: TokenSpacing.xl),
          ListTile(
            title: Text(l10n.ticketLinkTotal),
            trailing: Text(_euros(total), style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _release() async {
    final link = _link;
    final access = _access;
    if (link == null || access == null) return;
    await ref.read(ticketLinksRepositoryProvider).release(link, access);
    if (mounted) context.go('/home');
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.data,
    required this.names,
    required this.highlightPid,
  });

  final Map<String, dynamic> data;
  final Map<String, String> names;
  final String highlightPid;

  @override
  Widget build(BuildContext context) {
    final assignment = data['assignment'] as Map<String, dynamic>?;
    final claimed = _claimants(assignment);
    final mine = highlightPid.isNotEmpty && claimed.contains(highlightPid);
    return ListTile(
      dense: true,
      leading: mine ? const Icon(Icons.check_circle, size: 20) : null,
      title: Text((data['name'] as String?) ?? ''),
      subtitle: claimed.isEmpty
          ? null
          : Text(claimed.map((pid) => names[pid] ?? '').join(', ')),
      trailing: Text(_euros((data['totalPrice'] as int?) ?? 0)),
    );
  }

  /// Los pids que aparecen en la asignación, en cualquiera de los dos
  /// esquemas históricos (pesos de P2.1 y unidades de P2.2).
  static Set<String> _claimants(Map<String, dynamic>? assignment) {
    if (assignment == null) return const {};
    final result = <String>{};
    final participants = assignment['participants'];
    if (participants is Map) result.addAll(participants.keys.cast<String>());
    final units = assignment['units'];
    if (units is Map) {
      for (final entry in units.values) {
        if (entry is Map) result.addAll(entry.keys.cast<String>());
      }
    }
    return result;
  }
}

String _euros(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

/// «Soy yo»: solicitud de vinculación desde el ticket (ADR-037).
///
/// Es lo único que puede hacer quien se ha identificado temporalmente. La
/// decisión es del anfitrión, así que aquí solo se pide y se muestra el
/// estado. Aceptarla no moverá ningún importe: el actor sigue siendo
/// `manual:{id}` y solo se añade la identidad.
class _ManualLinkRequestCard extends ConsumerStatefulWidget {
  const _ManualLinkRequestCard({
    required this.spaceId,
    required this.manualId,
    required this.displayName,
    required this.sessionId,
    required this.ticketId,
    required this.pid,
  });

  final String spaceId;
  final String manualId;
  final String displayName;
  final String sessionId;
  final String ticketId;
  final String pid;

  @override
  ConsumerState<_ManualLinkRequestCard> createState() =>
      _ManualLinkRequestCardState();
}

class _ManualLinkRequestCardState
    extends ConsumerState<_ManualLinkRequestCard> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mine = ref
        .watch(
          myManualLinkProvider((
            spaceId: widget.spaceId,
            manualId: widget.manualId,
          )),
        )
        .value;

    if (mine?.status == ManualLinkStatus.accepted) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(l10n.manualLinkLinked),
        ),
      );
    }
    if (mine?.isPending ?? false) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.hourglass_empty),
          title: Text(l10n.manualLinkPending),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_add_alt),
        title: Text(l10n.manualLinkAsk),
        subtitle: Text(l10n.manualLinkRequestHelp),
        trailing: FilledButton(
          onPressed: _busy ? null : _ask,
          child: Text(l10n.manualLinkAsk),
        ),
      ),
    );
  }

  Future<void> _ask() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ownerUid =
        ref.read(spaceProvider(widget.spaceId)).value?.ownerUid ?? '';
    if (ownerUid.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(manualLinkRepositoryProvider)
          .request(
            widget.spaceId,
            widget.manualId,
            displayName: widget.displayName,
            // Propietario del espacio: Rules lo revalida contra el real.
            spaceOwnerUid: ownerUid,
            viaSessionId: widget.sessionId,
            viaTicketId: widget.ticketId,
            viaPid: widget.pid,
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkAskSent)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
