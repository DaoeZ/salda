import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/guest_identity_repository.dart';

/// El invitado elige su nombre visible (ADR-034). Es lo ÚNICO que necesita
/// para participar: su identidad ya vive en el dispositivo (sesión anónima
/// de Firebase, que sobrevive a reinicios) y no crea ninguna cuenta.
class GuestNameScreen extends ConsumerStatefulWidget {
  const GuestNameScreen({super.key});

  @override
  ConsumerState<GuestNameScreen> createState() => _GuestNameScreenState();
}

class _GuestNameScreenState extends ConsumerState<GuestNameScreen> {
  final _name = TextEditingController();
  var _initialized = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.guestNameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(guestIdentityRepositoryProvider).setDisplayName(name);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.guestNameSaved)));
      }
    } on Object {
      if (mounted) setState(() => _error = l10n.guestNameError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final identity = ref.watch(myGuestIdentityProvider);

    // Precarga el nombre ya elegido: renombrarse NO cambia la identidad.
    if (!_initialized && identity.hasValue) {
      _initialized = true;
      _name.text = identity.value?.displayName ?? '';
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.guestNameTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.person_pin_circle_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: TokenSpacing.lg),
            Text(
              l10n.guestNameBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: TokenSpacing.xl),
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: TokenSpacing.md),
            ],
            TextField(
              controller: _name,
              enabled: !_saving,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l10n.guestNameLabel,
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: TokenSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.commonSave),
            ),
            const SizedBox(height: TokenSpacing.xl),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(TokenSpacing.lg),
                child: Text(
                  l10n.guestLimitsBody,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
