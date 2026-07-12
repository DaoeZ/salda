import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/auth_repository.dart';

/// Login del anfitrión: email + contraseña (registro y recuperación).
/// El botón de Google aparecerá cuando exista el proyecto Firebase real
/// (AuthRepository.googleSignInAvailable) — contra el emulador no aplica.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  var _registering = false;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  String _errorText(AppLocalizations l10n, String code) => switch (code) {
        'invalid-credential' => l10n.authErrorInvalidCredential,
        'email-already-in-use' => l10n.authErrorEmailInUse,
        'weak-password' => l10n.authErrorWeakPassword,
        'network' => l10n.authErrorNetwork,
        _ => l10n.authErrorUnknown,
      };

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final auth = ref.read(authRepositoryProvider);
    setState(() => _busy = true);
    try {
      if (_registering) {
        await auth.register(
            _email.text.trim(), _password.text, _name.text.trim());
      } else {
        await auth.signIn(_email.text.trim(), _password.text);
      }
      // La redirección la hace el router al cambiar authState.
    } on AuthFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_errorText(l10n, failure.code))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    if (_email.text.trim().isEmpty) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(_email.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.loginResetSent)));
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_errorText(l10n, failure.code))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: TokenSpacing.md),
                  Text(Brand.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(l10n.loginTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: TokenSpacing.xl),
                  if (_registering) ...[
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          InputDecoration(labelText: l10n.loginDisplayName),
                    ),
                    const SizedBox(height: TokenSpacing.md),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: l10n.loginEmail),
                  ),
                  const SizedBox(height: TokenSpacing.md),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration:
                        InputDecoration(labelText: l10n.loginPassword),
                  ),
                  const SizedBox(height: TokenSpacing.xl),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_registering
                            ? l10n.loginRegister
                            : l10n.loginSignIn),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _registering = !_registering),
                    child: Text(_registering
                        ? l10n.loginToSignIn
                        : l10n.loginToRegister),
                  ),
                  if (!_registering)
                    TextButton(
                        onPressed: _reset, child: Text(l10n.loginForgot)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
