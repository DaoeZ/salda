import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/action_banner.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/application/social_account.dart';
import '../../auth/data/auth_repository.dart';
import '../../spaces/data/manual_link_repository.dart';
import '../../spaces/data/spaces_repository.dart'
    show spaceManualParticipantProvider;
import '../../spaces/domain/space_models.dart'
    show ManualLinkPropagationStatus, ManualLinkStatus;
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
      final firestore = repo.firestore;
      final access = await repo.myAccess(link.sessionId, link.ticketId);
      final ticket = await firestore.doc(link.ticketPath).get();
      final lines = await firestore
          .collection('${link.ticketPath}/lines')
          .orderBy('order')
          .get();
      // Los participantes NO se leen: el enlace no abre sus nombres. Solo
      // se conoce el nombre propio, que es el DESTINATARIO del enlace.
      final target = link.target;
      final soyElDestinatario =
          target != null && target.pid == (access?.pid ?? '');
      if (!mounted) return;
      setState(() {
        _link = link;
        _access = access;
        _ticket = ticket.data();
        _lines = lines.docs;
        _names = soyElDestinatario
            ? {target.pid: target.displayName}
            : const {};
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
        body: const ScreenBody(children: [SkeletonList(rows: 3)]),
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
      body: ScreenBody(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        children: [
          if (_access?.identifiesAManual ?? false) ...[
            SaldaCard(
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
                token: link.token,
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
    required this.token,
  });

  final String spaceId;
  final String manualId;
  final String displayName;
  final String sessionId;
  final String ticketId;
  final String pid;
  final String token;

  @override
  ConsumerState<_ManualLinkRequestCard> createState() =>
      _ManualLinkRequestCardState();
}

class _ManualLinkRequestCardState
    extends ConsumerState<_ManualLinkRequestCard> {
  var _busy = false;
  String? _preparedUid;
  SocialAccountStatus? _preparedAccount;
  var _preparingAccount = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentAppUserProvider);
    // La identificación temporal del ticket sí es apta para GUEST, pero
    // apropiarse del historial económico no: Rules exige una cuenta completa.
    // Se corta antes de escuchar solicitudes que esa identidad no puede leer.
    if (user?.isAnonymous ?? false) {
      _clearPreparedAccount();
      return _guestAccountCard(l10n);
    }
    if (user == null) {
      _clearPreparedAccount();
      return _signInCard(l10n);
    }
    if (user.needsEmailVerification) {
      _clearPreparedAccount();
      return _verifyEmailCard(l10n);
    }
    if (_preparedUid != user.uid) {
      _startAccountPreparation(user.uid);
    }
    if (_preparingAccount || _preparedAccount == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.hourglass_empty),
          title: Text(l10n.ticketLinkPreparing),
        ),
      );
    }
    if (!_preparedAccount!.isReady) {
      return _accountNotReadyCard(_preparedAccount!.readiness, l10n);
    }
    final mine = ref
        .watch(
          myManualLinkProvider((
            spaceId: widget.spaceId,
            manualId: widget.manualId,
          )),
        )
        .value;
    final manual = mine?.status == ManualLinkStatus.accepted
        ? ref
              .watch(
                spaceManualParticipantProvider((
                  spaceId: widget.spaceId,
                  manualId: widget.manualId,
                )),
              )
              .value
        : null;

    if (mine?.status == ManualLinkStatus.accepted) {
      if (manual?.effectiveLinkStatus == ManualLinkPropagationStatus.active) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(l10n.manualLinkLinked),
          ),
        );
      }
      if (manual?.effectiveLinkStatus == ManualLinkPropagationStatus.failed) {
        final message = manual?.linkError == 'legacy-sessions-without-context'
            ? l10n.manualLinkFailedLegacy
            : l10n.manualLinkFailed;
        return Card(
          child: ActionBanner(
            icon: Icons.error_outline,
            title: Text(message),
            actions: [
              FilledButton(
                onPressed: _busy ? null : _retryPropagation,
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
        );
      }
      return Card(
        child: ActionBanner(
          icon: Icons.hourglass_empty,
          title: Text(l10n.manualLinkProcessing),
          actions: [
            if (manual?.linkedUid != null)
              OutlinedButton(
                onPressed: _busy ? null : _retryPropagation,
                child: Text(l10n.commonRetry),
              ),
          ],
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
    if (mine?.status == ManualLinkStatus.rejected) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cancel_outlined),
          title: Text(l10n.manualLinkRejected),
        ),
      );
    }
    return Card(
      // El botón repetía el título y colgaba de `trailing`, así que con el
      // texto ampliado se salía de la pantalla. Ahora la acción va debajo.
      child: ActionBanner(
        icon: Icons.person_add_alt,
        title: Text(l10n.manualLinkAsk),
        subtitle: Text(l10n.manualLinkRequestHelp),
        actions: [
          FilledButton(
            onPressed: _busy ? null : _ask,
            child: Text(l10n.manualLinkAsk),
          ),
        ],
      ),
    );
  }

  Widget _guestAccountCard(AppLocalizations l10n) => Card(
    child: ActionBanner(
      icon: Icons.account_circle_outlined,
      title: Text(l10n.authProtectGuestTitle),
      subtitle: Text(l10n.authProtectGuestBody),
      actions: [
        FilledButton(
          onPressed: _busy ? null : () => _continueAuth('/register'),
          child: Text(l10n.authProtectGuestAction),
        ),
      ],
    ),
  );

  Widget _signInCard(AppLocalizations l10n) => Card(
    child: ActionBanner(
      icon: Icons.login,
      title: Text(l10n.joinIdentifyHint),
      actions: [
        FilledButton(
          onPressed: _busy ? null : () => _continueAuth('/login'),
          child: Text(l10n.joinWithAccount),
        ),
      ],
    ),
  );

  Widget _verifyEmailCard(AppLocalizations l10n) => Card(
    child: ActionBanner(
      icon: Icons.mark_email_unread_outlined,
      title: Text(l10n.socialEmailNotVerified),
      actions: [
        FilledButton(
          onPressed: _busy ? null : () => _continueAuth('/verify-email'),
          child: Text(l10n.joinVerifyEmailAction),
        ),
      ],
    ),
  );

  Widget _accountNotReadyCard(
    SocialReadiness readiness,
    AppLocalizations l10n,
  ) => switch (readiness) {
    SocialReadiness.notSignedIn => _signInCard(l10n),
    SocialReadiness.anonymous => _guestAccountCard(l10n),
    SocialReadiness.emailNotVerified => _verifyEmailCard(l10n),
    SocialReadiness.ready => const SizedBox.shrink(),
    SocialReadiness.staleToken ||
    SocialReadiness.publicProfileMissing ||
    SocialReadiness.publicProfileUnavailable => Card(
      child: ActionBanner(
        icon: Icons.error_outline,
        title: Text(
          readiness == SocialReadiness.staleToken
              ? l10n.spaceSessionNotReady
              : l10n.socialProfileNotReady,
        ),
        actions: [
          OutlinedButton(
            onPressed: _busy ? null : _retryAccountPreparation,
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    ),
  };

  void _clearPreparedAccount() {
    _preparedUid = null;
    _preparedAccount = null;
    _preparingAccount = false;
  }

  void _startAccountPreparation(String uid) {
    _preparedUid = uid;
    _preparedAccount = null;
    _preparingAccount = true;
    unawaited(_prepareAccountForView(uid));
  }

  Future<void> _prepareAccountForView(String uid) async {
    final account = await _prepareAccountStatus(
      'manualLink:${widget.spaceId}:${widget.manualId}:view',
    );
    if (!mounted || ref.read(currentAppUserProvider)?.uid != uid) return;
    setState(() {
      _preparingAccount = false;
      _preparedAccount = account;
    });
  }

  Future<SocialAccountStatus> _prepareAccountStatus(String flow) async {
    try {
      return await ref.read(socialAccountServiceProvider).prepare(flow: flow);
    } on Object {
      return const SocialAccountStatus(
        SocialReadiness.publicProfileUnavailable,
      );
    }
  }

  void _retryAccountPreparation() {
    setState(_clearPreparedAccount);
  }

  Future<void> _ask() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // Es el espejo cliente de `canUseSocial()`: no se intenta nunca una
      // escritura de solicitud hasta que token, verificación y perfil público
      // están listos.
      final account = await ref
          .read(socialAccountServiceProvider)
          .prepare(flow: 'manualLink:${widget.spaceId}:${widget.manualId}');
      if (!mounted) return;
      if (!account.isReady) {
        _handleAccountNotReady(account.readiness, l10n, messenger);
        return;
      }
      await ref
          .read(manualLinkRepositoryProvider)
          .request(
            widget.spaceId,
            widget.manualId,
            displayName: widget.displayName,
            // La callable deriva UID y propietario actuales y revalida este
            // acceso temporal antes de crear la solicitud.
            viaSessionId: widget.sessionId,
            viaTicketId: widget.ticketId,
            viaPid: widget.pid,
          );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkAskSent)));
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.manualLinkError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPropagation() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(manualLinkRepositoryProvider)
          .retryPropagation(widget.spaceId, widget.manualId);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleAccountNotReady(
    SocialReadiness readiness,
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) {
    switch (readiness) {
      case SocialReadiness.notSignedIn:
        _continueAuth('/login');
        return;
      case SocialReadiness.anonymous:
        _continueAuth('/register');
        return;
      case SocialReadiness.emailNotVerified:
        _continueAuth('/verify-email');
        return;
      case SocialReadiness.ready:
        return;
      case SocialReadiness.staleToken:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.spaceSessionNotReady)),
        );
        return;
      case SocialReadiness.publicProfileMissing ||
          SocialReadiness.publicProfileUnavailable:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.socialProfileNotReady)),
        );
        return;
    }
  }

  void _continueAuth(String route) {
    ref.read(pendingTicketLinkProvider.notifier).set(widget.token);
    if (mounted) context.go(route);
  }
}
