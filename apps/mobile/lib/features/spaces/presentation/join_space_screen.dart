import 'package:design_tokens/design_tokens.dart';
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
/// Una sola pantalla cubre las tres identidades del producto:
/// - **Cuenta**: entra directamente.
/// - **Invitado** con nombre: entra igual, sin registrarse.
/// - **Sin sesión**: elige aquí mismo entre cuenta o invitado, sin perder el
///   enlace por el camino (el bloqueo clásico de "inicia sesión y vuelve a
///   pulsar el enlace").
///
/// Los participantes **manuales** no entran por aquí por definición: no
/// tienen dispositivo. Siguen siendo cosa del propietario dentro del grupo.
///
/// Con [token] nulo la pantalla pide pegar el enlace. Es la vía que funciona
/// HOY, sin depender de que Hosting sirva la página de aterrizaje ni de que
/// Android tenga verificados los App Links.
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
  var _loading = false;
  var _working = false;
  var _looked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.token != null) _lookup(widget.token!);
  }

  @override
  void dispose() {
    _pasted.dispose();
    _guestName.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    if (raw.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(spacesRepositoryProvider)
          .previewJoinLink(raw);
      if (!mounted) return;
      setState(() {
        _link = link;
        _looked = true;
        // Revocado y inexistente se presentan igual a propósito: distinguirlos
        // convertiría la pantalla en un oráculo de qué grupos existen.
        if (link == null) _error = AppLocalizations.of(context).joinLinkInvalid;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).joinLinkInvalid);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final l10n = AppLocalizations.of(context);
    final link = _link;
    if (link == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      // Un invitado necesita nombre visible ANTES de la membresía: es el
      // snapshot con el que se le pinta (no tiene perfil público).
      final user = ref.read(currentAppUserProvider);
      final needsName =
          (user?.isAnonymous ?? false) &&
          ref.read(myGuestIdentityProvider).value == null;
      if (needsName) {
        final name = _guestName.text.trim();
        if (name.isEmpty) {
          setState(() {
            _error = l10n.guestNameRequired;
            _working = false;
          });
          return;
        }
        await ref.read(guestIdentityRepositoryProvider).setDisplayName(name);
      }

      final outcome = await ref
          .read(spacesRepositoryProvider)
          .joinWithLink(link.token);
      if (!mounted) return;
      switch (outcome) {
        case JoinLinkOutcome.joined:
        case JoinLinkOutcome.alreadyMember:
          context.go('/home/spaces/${link.spaceId}');
        case JoinLinkOutcome.needsGuestName:
          setState(() => _error = l10n.guestNameRequired);
        case JoinLinkOutcome.invalid:
          setState(() => _error = l10n.joinLinkInvalid);
      }
    } on Object {
      if (mounted) setState(() => _error = l10n.joinLinkError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = ref.watch(currentAppUserProvider);
    final guestIdentity = ref.watch(myGuestIdentityProvider).value;
    final signedIn = user != null;
    final needsGuestName = (user?.isAnonymous ?? false) && guestIdentity == null;

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

                if (widget.token == null && _link == null) ...[
                  Text(l10n.joinPasteHint, textAlign: TextAlign.center),
                  const SizedBox(height: TokenSpacing.md),
                  TextField(
                    controller: _pasted,
                    decoration: InputDecoration(
                      labelText: l10n.joinPasteLabel,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _lookup,
                  ),
                  const SizedBox(height: TokenSpacing.md),
                  FilledButton(
                    onPressed: _loading ? null : () => _lookup(_pasted.text),
                    child: Text(l10n.joinLookup),
                  ),
                ],

                if (_loading) ...[
                  const SizedBox(height: TokenSpacing.lg),
                  const Center(child: CircularProgressIndicator()),
                ],

                if (_link case final link?) ...[
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

                  if (!signedIn) ...[
                    // El enlace NO se pierde al identificarse: se resuelve
                    // aquí mismo y la pantalla sigue en pie.
                    Text(l10n.joinIdentifyHint, textAlign: TextAlign.center),
                    const SizedBox(height: TokenSpacing.md),
                    FilledButton.tonal(
                      onPressed: _working ? null : _continueAsGuest,
                      child: Text(l10n.authContinueGuest),
                    ),
                    const SizedBox(height: TokenSpacing.sm),
                    TextButton(
                      onPressed: () => context.push('/login'),
                      child: Text(l10n.joinWithAccount),
                    ),
                  ] else ...[
                    if (needsGuestName) ...[
                      TextField(
                        controller: _guestName,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.guestNameLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: TokenSpacing.md),
                    ],
                    FilledButton.icon(
                      onPressed: _working ? null : _join,
                      icon: const Icon(Icons.login),
                      label: Text(l10n.joinAction),
                    ),
                  ],
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

                if (_looked && _link == null && widget.token != null) ...[
                  const SizedBox(height: TokenSpacing.md),
                  TextButton(
                    onPressed: () => context.go('/home'),
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

  Future<void> _continueAsGuest() async {
    setState(() => _working = true);
    try {
      await ref.read(authRepositoryProvider).signInAsGuest();
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).joinLinkError);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
