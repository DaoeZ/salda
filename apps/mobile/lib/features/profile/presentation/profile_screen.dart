import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../data/profile_repository.dart';
import 'profile_avatar.dart';

String usernameErrorText(AppLocalizations l10n, UsernameError error) =>
    switch (error) {
      UsernameError.empty ||
      UsernameError.tooShort => l10n.usernameErrorTooShort,
      UsernameError.tooLong => l10n.usernameErrorTooLong,
      UsernameError.invalidCharacters => l10n.usernameErrorInvalidChars,
      UsernameError.mustStartWithLetter => l10n.usernameErrorStartLetter,
      UsernameError.endsWithUnderscore ||
      UsernameError.consecutiveUnderscores => l10n.usernameErrorUnderscores,
      UsernameError.reserved => l10n.usernameErrorReserved,
    };

/// Crear/editar el perfil público (P2). Al crear, propone un username
/// NATURAL derivado del nombre (edgar → edgar27 → edgar_cantera…): el
/// usuario puede cambiarlo antes de aceptar. La disponibilidad se comprueba
/// en vivo con debounce; guardar es un batch atómico perfil+claim.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  Timer? _debounce;
  var _initialized = false;
  var _isNew = true;
  var _checking = false;
  var _saving = false;
  UsernameCheck? _check;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _initFrom(PublicProfile? profile) async {
    _initialized = true;
    _isNew = profile == null;
    if (profile != null) {
      _name.text = profile.displayName;
      _username.text = profile.username;
      _check = const UsernameOk(); // su propio username siempre es válido
      return;
    }
    _name.text =
        ref.read(currentAppUserProvider)?.displayName?.trim() ?? '';
    if (_name.text.isEmpty) return;
    // Propuesta automática (RF de P2): primer candidato natural libre.
    final suggested = await ref
        .read(profileRepositoryProvider)
        .suggestUsername(_name.text);
    if (!mounted || _username.text.isNotEmpty) return;
    setState(() {
      _username.text = suggested;
      _check = const UsernameOk();
    });
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    final error = validateUsername(value);
    if (error != null) {
      setState(() {
        _check = UsernameInvalid(error);
        _checking = false;
      });
      return;
    }
    setState(() {
      _checking = true;
      _check = null;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final result =
          await ref.read(profileRepositoryProvider).checkUsername(value);
      if (!mounted || normalizeUsername(_username.text) !=
          normalizeUsername(value)) {
        return;
      }
      setState(() {
        _check = result;
        _checking = false;
      });
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Nunca guardar sin comprobar: si el debounce sigue pendiente, se
    // resuelve aquí de forma síncrona para el usuario.
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(profileRepositoryProvider);
      final check = await repo.checkUsername(_username.text);
      if (check is! UsernameOk) {
        setState(() {
          _check = check;
          _saving = false;
        });
        return;
      }
      if (_isNew) {
        await repo.createProfile(
          displayName: _name.text,
          username: _username.text,
        );
      } else {
        await repo.updateProfile(
          displayName: _name.text,
          username: _username.text,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    } on FirebaseException {
      // Carrera perdida (otro reclamó el username entre comprobar y guardar)
      // o sin conexión: el mensaje invita a reintentar.
      if (mounted) setState(() => _error = l10n.profileSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider);
    final user = ref.watch(currentAppUserProvider);

    if (!_initialized && !profile.isLoading) {
      _initFrom(profile.value);
    }

    final (Widget? statusIcon, String? statusText, bool statusIsError) =
        switch ((_checking, _check)) {
      (true, _) => (
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          l10n.usernameChecking,
          false,
        ),
      (_, UsernameOk()) => (
          Icon(Icons.check_circle_outline,
              color: theme.colorScheme.primary),
          l10n.usernameAvailable,
          false,
        ),
      (_, UsernameTaken()) => (
          Icon(Icons.cancel_outlined, color: theme.colorScheme.error),
          l10n.usernameTaken,
          true,
        ),
      (_, UsernameInvalid(:final error)) => (
          Icon(Icons.cancel_outlined, color: theme.colorScheme.error),
          usernameErrorText(l10n, error),
          true,
        ),
      _ => (null, null, false),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.profileCreateTitle : l10n.profileTitle),
      ),
      body: profile.isLoading && !_initialized
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(TokenSpacing.xl),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isNew) ...[
                      Text(
                        l10n.profileCreateBody,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: TokenSpacing.lg),
                    ],
                    Center(
                      child: ListenableBuilder(
                        listenable: _name,
                        builder: (_, _) => ProfileAvatar(
                          seed: user?.uid ?? '',
                          displayName: _name.text,
                          radius: 40,
                        ),
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
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? l10n.authValidationName
                          : null,
                      decoration: InputDecoration(
                        labelText: l10n.loginDisplayName,
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: TokenSpacing.md),
                    TextFormField(
                      controller: _username,
                      enabled: !_saving,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      // El username es minúsculas por definición: el teclado
                      // no puede introducir otra cosa.
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_]'),
                        ),
                        TextInputFormatter.withFunction(
                          (_, value) =>
                              value.copyWith(text: value.text.toLowerCase()),
                        ),
                      ],
                      onChanged: _onUsernameChanged,
                      onFieldSubmitted: (_) => _save(),
                      validator: (value) =>
                          validateUsername(value ?? '') != null
                              ? usernameErrorText(
                                  l10n,
                                  validateUsername(value ?? '')!,
                                )
                              : null,
                      decoration: InputDecoration(
                        labelText: l10n.profileUsername,
                        helperText: l10n.profileUsernameHelp,
                        prefixIcon: const Icon(Icons.alternate_email),
                        suffixIcon: statusIcon == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.all(12),
                                child: statusIcon,
                              ),
                      ),
                    ),
                    if (statusText != null) ...[
                      const SizedBox(height: TokenSpacing.xs),
                      Text(
                        statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusIsError
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: TokenSpacing.xl),
                    FilledButton(
                      onPressed:
                          _saving || _checking || _check is! UsernameOk
                              ? null
                              : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isNew
                              ? l10n.profileCreateAction
                              : l10n.commonSave),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
