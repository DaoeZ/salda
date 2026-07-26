import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../data/ticket_links_repository.dart';
import '../domain/ticket_link_models.dart';

/// Acceso a un ticket por enlace (Sprint 5, ADR-036).
///
/// Orden del flujo, sin pantallas intermedias innecesarias:
///  1. se resuelve el enlace (solo se ve el comercio);
///  2. quien no tenga identidad elige: invitado, entrar o crear cuenta;
///  3. un invitado sin nombre solo pone su nombre;
///  4. con identidad, se abre el acceso de LECTURA sin preguntar nada;
///  5. si además resulta ser alguien conocido de la sesión, entra directo;
///  6. si no, y el ticket tiene participantes MANUAL, «¿Quién eres?».
///
/// El paso 4 es lo que permite el 5: sin acceso de lectura no se pueden leer
/// los participantes, y sin leerlos no se sabe si hay que preguntar.
class JoinTicketScreen extends ConsumerStatefulWidget {
  const JoinTicketScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinTicketScreen> createState() => _JoinTicketScreenState();
}

class _JoinTicketScreenState extends ConsumerState<JoinTicketScreen> {
  final _guestName = TextEditingController();

  TicketJoinLink? _link;
  List<EligibleManual>? _choices;
  var _busy = false;
  var _resolved = false;
  var _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(pendingTicketLinkProvider.notifier).set(widget.token);
      }
    });
    _resolve();
  }

  @override
  void dispose() {
    _guestName.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(ticketLinksRepositoryProvider)
          .preview(widget.token);
      if (!mounted) return;
      setState(() {
        _link = link;
        _resolved = true;
        if (link == null) {
          _error = AppLocalizations.of(context).ticketLinkInvalid;
        }
      });
    } on Object {
      if (mounted) {
        setState(() {
          _resolved = true;
          _error = AppLocalizations.of(context).ticketLinkInvalid;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _hasIdentity() {
    final user = ref.read(currentAppUserProvider);
    if (user == null) return false;
    if (user.isFullAccount) return true;
    return user.isAnonymous && ref.read(myGuestIdentityProvider).value != null;
  }

  /// Pasos 4–6. Se ejecuta solo, sin confirmación.
  Future<void> _enter({String? guestName}) async {
    final l10n = AppLocalizations.of(context);
    final link = _link;
    if (link == null || _working) return;
    _working = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (guestName != null) {
        await ref
            .read(guestIdentityRepositoryProvider)
            .setDisplayName(guestName);
      }
      final repo = ref.read(ticketLinksRepositoryProvider);

      // Reabrir el mismo enlace no repite pasos: si ya hay identificación
      // vigente para ESTE ticket, se entra y punto.
      final existing = await repo.myAccess(link.sessionId, link.ticketId);
      if (existing != null && existing.ticketId == link.ticketId) {
        _goToTicket(link);
        return;
      }

      // Poseer el enlace NO basta: hay que representar a alguien del
      // ticket. Si este UID ya es participante, entra sin elegir nada.
      final knownPid = await repo.knownParticipantPid(link);
      if (knownPid != null) {
        await repo.enterAsKnownParticipant(link, knownPid);
        _goToTicket(link);
        return;
      }
      if (link.manuals.isEmpty) {
        // Ni participante conocido ni MANUAL elegible: no hay a quién
        // representar, así que no se concede lectura.
        setState(() => _error = l10n.ticketLinkNoManuals);
        return;
      }
      if (!mounted) return;
      setState(() => _choices = link.manuals);
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'permission-denied'
              ? l10n.ticketLinkInvalid
              : l10n.ticketLinkError,
        );
      }
    } on Object {
      if (mounted) setState(() => _error = l10n.ticketLinkError);
    } finally {
      _working = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(EligibleManual manual) async {
    final l10n = AppLocalizations.of(context);
    final link = _link;
    if (link == null || _working) return;
    _working = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(ticketLinksRepositoryProvider)
          .identifyAsManual(link, manual);
      if (!mounted) return;
      switch (outcome) {
        case TicketLinkOutcome.opened:
          _goToTicket(link);
        case TicketLinkOutcome.manualTaken:
          // Otro dispositivo llegó antes entre la lectura y la selección.
          setState(() {
            _error = l10n.ticketLinkManualTaken;
            _choices = [
              for (final candidate in link.manuals)
                if (candidate.manualId != manual.manualId) candidate,
            ];
          });
        case TicketLinkOutcome.invalid:
        case TicketLinkOutcome.needsIdentity:
        case TicketLinkOutcome.needsManualChoice:
          setState(() => _error = l10n.ticketLinkInvalid);
      }
    } on Object {
      if (mounted) setState(() => _error = l10n.ticketLinkError);
    } finally {
      _working = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToTicket(TicketJoinLink link) {
    ref.read(pendingTicketLinkProvider.notifier).clear();
    context.go('/ticket/${link.token}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = ref.watch(currentAppUserProvider);
    final guestIdentity = ref.watch(myGuestIdentityProvider).value;
    final signedIn = user != null;
    final needsGuestName =
        (user?.isAnonymous ?? false) && guestIdentity == null;
    final link = _link;

    // Entrada automática: identidad conocida y enlace válido ⇒ adelante.
    if (link != null &&
        !_busy &&
        !_working &&
        _choices == null &&
        _hasIdentity()) {
      Future.microtask(() {
        if (mounted) _enter();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ticketLinkTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TokenSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 64),
                const SizedBox(height: TokenSpacing.lg),

                if (link != null && _choices == null) ...[
                  Text(
                    l10n.ticketLinkSharedWithYou,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: TokenSpacing.sm),
                  Text(
                    link.merchantName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: TokenSpacing.lg),
                ],

                if (link != null && _choices == null && !signedIn) ...[
                  Text(l10n.joinIdentifyHint, textAlign: TextAlign.center),
                  const SizedBox(height: TokenSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : _continueAsGuest,
                    child: Text(l10n.authContinueGuest),
                  ),
                  const SizedBox(height: TokenSpacing.sm),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => context.push('/login'),
                    child: Text(l10n.joinWithAccount),
                  ),
                  const SizedBox(height: TokenSpacing.sm),
                  TextButton(
                    onPressed: _busy ? null : () => context.push('/register'),
                    child: Text(l10n.joinCreateAccount),
                  ),
                ] else if (link != null &&
                    _choices == null &&
                    needsGuestName) ...[
                  Text(l10n.joinGuestNameHint, textAlign: TextAlign.center),
                  const SizedBox(height: TokenSpacing.md),
                  TextField(
                    controller: _guestName,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.guestNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: TokenSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : _submitGuestName,
                    child: Text(l10n.commonConfirm),
                  ),
                ],

                // «¿Quién eres?» — SOLO participantes MANUAL de este ticket.
                // Ni cuentas, ni invitados, ni miembros del grupo: la lista
                // viene denormalizada en el enlace y no hay nada más que ver.
                if (_choices case final choices?) ...[
                  Text(
                    l10n.ticketLinkWhoAreYou,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: TokenSpacing.sm),
                  Text(
                    l10n.ticketLinkWhoAreYouHelp,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: TokenSpacing.md),
                  if (choices.isEmpty)
                    Text(l10n.ticketLinkNoManuals, textAlign: TextAlign.center)
                  else
                    // Incluso con UNO solo se confirma: autoseleccionar
                    // convertiría un enlace reenviado por error en una
                    // suplantación silenciosa, y confirmar cuesta un toque.
                    for (final manual in choices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: TokenSpacing.sm),
                        child: FilledButton.tonal(
                          onPressed: _busy ? null : () => _pick(manual),
                          child: Text(manual.displayName),
                        ),
                      ),
                ],

                if (_busy) ...[
                  const SizedBox(height: TokenSpacing.lg),
                  const Center(child: CircularProgressIndicator()),
                ],

                if (_error case final message?) ...[
                  const SizedBox(height: TokenSpacing.md),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],

                if (_resolved && link == null) ...[
                  const SizedBox(height: TokenSpacing.md),
                  TextButton(
                    onPressed: () {
                      ref.read(pendingTicketLinkProvider.notifier).clear();
                      context.go('/home');
                    },
                    child: Text(l10n.commonDone),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitGuestName() {
    final name = _guestName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).guestNameRequired);
      return;
    }
    _enter(guestName: name);
  }

  Future<void> _continueAsGuest() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signInAsGuest();
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).ticketLinkError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
