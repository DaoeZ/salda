import 'package:design_tokens/design_tokens.dart';

import '../../../core/routing/incoming_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';

/// Incorporación a un grupo por enlace (Sprint 4, ADR-035).
///
/// **Regla de producto: a quien ya tiene identidad no se le pregunta quién
/// es.** Si hay cuenta —o identidad de invitado, que persiste en el
/// dispositivo— el enlace entra SOLO y aterriza en el grupo. No hay pantalla
/// intermedia ni botón de confirmar: la identidad ya se conoce, así que
/// preguntar sería fricción pura.
///
/// El selector de identidad se reserva para los participantes MANUAL de los
/// enlaces de TICKET (Sprint 5), donde sí hace falta: allí la persona elige
/// a qué participante sin cuenta corresponde.
///
/// Solo se pide algo a quien NO tiene identidad todavía, y entonces se le
/// ofrecen las tres salidas: entrar con su cuenta, crear una, o continuar
/// como invitado (que solo necesita un nombre visible).
///
/// Con [token] nulo la pantalla pide pegar el enlace: es la vía manual
/// mientras Hosting no sirva la página de aterrizaje.
class JoinSpaceScreen extends ConsumerStatefulWidget {
  const JoinSpaceScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<JoinSpaceScreen> createState() => _JoinSpaceScreenState();
}

class _JoinSpaceScreenState extends ConsumerState<JoinSpaceScreen> {
  final _pasted = TextEditingController();
  final _guestName = TextEditingController();

  SpaceJoinLink? _link;
  var _busy = false;
  var _resolved = false;

  /// Evita que el auto-canje se dispare dos veces si el árbol se reconstruye
  /// mientras la escritura está en vuelo.
  var _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final token = widget.token;
    if (token != null) {
      // Se recuerda ANTES de resolver nada: si la persona se va a
      // identificarse, el router la devolverá aquí con el mismo enlace.
      Future.microtask(() {
        if (mounted) ref.read(pendingGroupLinkProvider.notifier).set(token);
      });
      _resolve(token);
    }
  }

  @override
  void dispose() {
    _pasted.dispose();
    _guestName.dispose();
    super.dispose();
  }

  Future<void> _resolve(String raw) async {
    if (raw.trim().isEmpty) return;
    // Lo que se pega es la URL COMPLETA del chat, no el token suelto: sin
    // extraerlo, la búsqueda iba contra `spaceLinks/https://…` y siempre
    // respondía que la invitación no existe.
    final parsed = IncomingLinkParser.parse(raw);
    final token = parsed is GroupInvitationLink ? parsed.token : raw.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(spacesRepositoryProvider)
          .previewJoinLink(token);
      if (!mounted) return;
      setState(() {
        _link = link;
        _resolved = true;
        // Revocado, caducado e inexistente se presentan igual a propósito:
        // distinguirlos convertiría la pantalla en un oráculo de qué grupos
        // existen.
        if (link == null) _error = AppLocalizations.of(context).joinLinkInvalid;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _resolved = true;
          _error = AppLocalizations.of(context).joinLinkInvalid;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ¿Sabemos ya quién es? Cuenta completa, o invitado con nombre elegido.
  bool _hasIdentity() {
    final user = ref.read(currentAppUserProvider);
    if (user == null) return false;
    if (user.isFullAccount) return true;
    return user.isAnonymous && ref.read(myGuestIdentityProvider).value != null;
  }

  Future<void> _join({String? guestName}) async {
    final l10n = AppLocalizations.of(context);
    final link = _link;
    if (link == null || _joining) return;
    _joining = true;
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
      final outcome = await ref
          .read(spacesRepositoryProvider)
          .joinWithLink(link.token);
      if (!mounted) return;
      switch (outcome) {
        case JoinLinkOutcome.joined:
        case JoinLinkOutcome.alreadyMember:
          // Entrar y ya estar dentro llevan al mismo sitio: el grupo. Volver
          // a pulsar el enlace nunca debe dar un error.
          ref.read(pendingGroupLinkProvider.notifier).clear();
          context.go('/home/spaces/${link.spaceId}');
        case JoinLinkOutcome.needsGuestName:
          setState(() => _error = l10n.guestNameRequired);
        case JoinLinkOutcome.invalid:
          setState(() => _error = l10n.joinLinkInvalid);
      }
    } on Object {
      if (mounted) setState(() => _error = l10n.joinLinkError);
    } finally {
      _joining = false;
      if (mounted) setState(() => _busy = false);
    }
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

    // ENTRADA AUTOMÁTICA: en cuanto hay enlace válido e identidad conocida,
    // se entra sin preguntar. Cubre también el regreso desde el login: el
    // router devuelve aquí y esto se dispara solo.
    if (link != null && !_busy && !_joining && _hasIdentity()) {
      Future.microtask(() {
        if (mounted) _join();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TokenSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.groups_outlined, size: 64),
                const SizedBox(height: TokenSpacing.lg),

                // Vía manual: pegar el enlace recibido.
                if (widget.token == null && link == null) ...[
                  Text(l10n.joinPasteHint, textAlign: TextAlign.center),
                  const SizedBox(height: TokenSpacing.md),
                  TextField(
                    controller: _pasted,
                    decoration: InputDecoration(
                      labelText: l10n.joinPasteLabel,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _resolve,
                  ),
                  const SizedBox(height: TokenSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : () => _resolve(_pasted.text),
                    child: Text(l10n.joinLookup),
                  ),
                ],

                if (link != null) ...[
                  Text(
                    l10n.joinInvitedTo,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: TokenSpacing.sm),
                  Text(
                    link.spaceName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: TokenSpacing.lg),

                  if (!signedIn)
                    _IdentityChoices(
                      busy: _busy,
                      onGuest: _continueAsGuest,
                      onLogin: () => context.push('/login'),
                      onRegister: () => context.push('/register'),
                    )
                  else if (user.needsEmailVerification) ...[
                    // Cuenta recién creada: el enlace queda recordado, así
                    // que verificar y volver aterriza en el grupo.
                    Text(l10n.joinVerifyEmail, textAlign: TextAlign.center),
                    const SizedBox(height: TokenSpacing.md),
                    FilledButton(
                      onPressed: () => context.push('/verify-email'),
                      child: Text(l10n.joinVerifyEmailAction),
                    ),
                  ] else if (needsGuestName) ...[
                    // Un invitado nuevo solo necesita su nombre visible: es
                    // lo único que la app no puede saber por él.
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
                      onSubmitted: (_) => _submitGuestName(),
                    ),
                    const SizedBox(height: TokenSpacing.md),
                    FilledButton(
                      onPressed: _busy ? null : _submitGuestName,
                      child: Text(l10n.joinAction),
                    ),
                  ],
                ],

                // Identidad conocida: solo progreso. No hay nada que decidir.
                if (_busy) ...[
                  const SizedBox(height: TokenSpacing.lg),
                  const Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
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

                if (_resolved && link == null && widget.token != null) ...[
                  const SizedBox(height: TokenSpacing.md),
                  TextButton(
                    onPressed: () {
                      ref.read(pendingGroupLinkProvider.notifier).clear();
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
    _join(guestName: name);
  }

  Future<void> _continueAsGuest() async {
    setState(() => _busy = true);
    try {
      // Al volver, `needsGuestName` pedirá su nombre y de ahí entra solo.
      await ref.read(authRepositoryProvider).signInAsGuest();
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).joinLinkError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Las tres salidas de quien todavía no tiene identidad. El enlace queda
/// recordado, así que identificarse no lo pierde.
class _IdentityChoices extends StatelessWidget {
  const _IdentityChoices({
    required this.busy,
    required this.onGuest,
    required this.onLogin,
    required this.onRegister,
  });

  final bool busy;
  final VoidCallback onGuest;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.joinIdentifyHint, textAlign: TextAlign.center),
        const SizedBox(height: TokenSpacing.md),
        FilledButton(
          onPressed: busy ? null : onGuest,
          child: Text(l10n.authContinueGuest),
        ),
        const SizedBox(height: TokenSpacing.sm),
        FilledButton.tonal(
          onPressed: busy ? null : onLogin,
          child: Text(l10n.joinWithAccount),
        ),
        const SizedBox(height: TokenSpacing.sm),
        TextButton(
          onPressed: busy ? null : onRegister,
          child: Text(l10n.joinCreateAccount),
        ),
      ],
    );
  }
}
