import 'dart:async';

import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/auth_repository.dart';

String authErrorText(AppLocalizations l10n, AuthFailure failure) {
  final message = switch (failure.code) {
    AuthFailureCode.invalidCredential => l10n.authErrorInvalidCredential,
    AuthFailureCode.emailAlreadyInUse => l10n.authErrorEmailInUse,
    AuthFailureCode.weakPassword => l10n.authErrorWeakPassword,
    AuthFailureCode.network => l10n.authErrorNetwork,
    AuthFailureCode.tooManyRequests => l10n.authErrorTooManyRequests,
    AuthFailureCode.userDisabled => l10n.authErrorUserDisabled,
    AuthFailureCode.operationNotAllowed => l10n.authErrorOperationNotAllowed,
    AuthFailureCode.credentialAlreadyInUse =>
      l10n.authErrorCredentialAlreadyInUse,
    AuthFailureCode.cancelled => l10n.authErrorCancelled,
    AuthFailureCode.oauthConfiguration => l10n.authErrorOauthConfiguration,
    AuthFailureCode.signInInterrupted => l10n.authErrorSignInInterrupted,
    AuthFailureCode.sessionNotEstablished =>
      l10n.authErrorSessionNotEstablished,
    AuthFailureCode.profileUnavailable => l10n.authErrorProfileUnavailable,
    AuthFailureCode.unknown => l10n.authErrorUnknown,
  };
  // El código técnico solo acompaña a los fallos que NO puede resolver el
  // usuario: en el resto sería ruido delante de una acción clara.
  final code = failure.technicalCode;
  if (code == null || !_codeWorthShowing.contains(failure.code)) {
    return message;
  }
  return l10n.authErrorWithCode(message, code);
}

const _codeWorthShowing = {
  AuthFailureCode.oauthConfiguration,
  AuthFailureCode.sessionNotEstablished,
  AuthFailureCode.unknown,
};

String? validateEmail(AppLocalizations l10n, String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return l10n.authValidationEmailRequired;
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return l10n.authValidationEmailInvalid;
  }
  return null;
}

String? validateLoginPassword(AppLocalizations l10n, String? value) {
  if ((value ?? '').isEmpty) return l10n.authValidationPasswordRequired;
  return null;
}

String? validateNewPassword(AppLocalizations l10n, String? value) {
  final password = value ?? '';
  if (password.isEmpty) return l10n.authValidationPasswordRequired;
  if (password.length < 8) return l10n.authValidationPasswordLength;
  return null;
}

class AuthLoadingScreen extends StatelessWidget {
  const AuthLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _obscurePassword = true;
  var _busyAction = '';
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Future<void> Function() operation) async {
    if (_busyAction.isNotEmpty) return;
    setState(() {
      _busyAction = action;
      _error = null;
    });
    try {
      await operation();
    } on AuthFailure catch (failure) {
      if (mounted && failure.code != AuthFailureCode.cancelled) {
        setState(
          () => _error = authErrorText(AppLocalizations.of(context), failure),
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = '');
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      'email',
      () => ref
          .read(authRepositoryProvider)
          .signIn(_email.text.trim(), _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AuthShell(
      title: l10n.loginWelcome,
      subtitle: l10n.loginTitle,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) _InlineError(message: _error!),
              TextFormField(
                controller: _email,
                enabled: _busyAction.isEmpty,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                validator: (value) => validateEmail(l10n, value),
                decoration: InputDecoration(
                  labelText: l10n.loginEmail,
                  prefixIcon: const Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: TokenSpacing.md),
              TextFormField(
                controller: _password,
                enabled: _busyAction.isEmpty,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (value) => validateLoginPassword(l10n, value),
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.loginPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? l10n.authShowPassword
                        : l10n.authHidePassword,
                    onPressed: _busyAction.isEmpty
                        ? () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          )
                        : null,
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busyAction.isEmpty
                      ? () => context.push(
                          '/forgot-password',
                          extra: _email.text.trim(),
                        )
                      : null,
                  child: Text(l10n.loginForgot),
                ),
              ),
              FilledButton(
                onPressed: _busyAction.isEmpty ? _submit : null,
                child: _ButtonContent(
                  loading: _busyAction == 'email',
                  label: l10n.loginSignIn,
                ),
              ),
              const SizedBox(height: TokenSpacing.md),
              _OrDivider(label: l10n.authOr),
              const SizedBox(height: TokenSpacing.md),
              OutlinedButton.icon(
                onPressed: _busyAction.isEmpty
                    ? () => _run(
                        'google',
                        ref.read(authRepositoryProvider).signInWithGoogle,
                      )
                    : null,
                icon: _busyAction == 'google'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata, size: 28),
                label: Text(l10n.authContinueGoogle),
              ),
              TextButton.icon(
                onPressed: _busyAction.isEmpty
                    ? () => _run(
                        'guest',
                        ref.read(authRepositoryProvider).signInAsGuest,
                      )
                    : null,
                icon: _busyAction == 'guest'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_outline),
                label: Text(l10n.authContinueGuest),
              ),
              const SizedBox(height: TokenSpacing.sm),
              TextButton(
                onPressed: _busyAction.isEmpty
                    ? () => context.push('/register')
                    : null,
                child: Text(l10n.loginToRegister),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  var _busyAction = '';
  var _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Future<void> Function() operation) async {
    if (_busyAction.isNotEmpty) return;
    setState(() {
      _busyAction = action;
      _error = null;
    });
    try {
      await operation();
    } on AuthFailure catch (failure) {
      if (mounted && failure.code != AuthFailureCode.cancelled) {
        setState(
          () => _error = authErrorText(AppLocalizations.of(context), failure),
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = '');
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      'email',
      () => ref
          .read(authRepositoryProvider)
          .register(_email.text.trim(), _password.text, _name.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isUpgrade = ref.watch(authStateProvider).value?.isAnonymous ?? false;
    return _AuthShell(
      showBack: !isUpgrade,
      title: isUpgrade ? l10n.authProtectGuestTitle : l10n.registerTitle,
      subtitle: isUpgrade ? l10n.authProtectGuestBody : l10n.registerSubtitle,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) _InlineError(message: _error!),
              TextFormField(
                controller: _name,
                enabled: _busyAction.isEmpty,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
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
                controller: _email,
                enabled: _busyAction.isEmpty,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.newUsername],
                validator: (value) => validateEmail(l10n, value),
                decoration: InputDecoration(
                  labelText: l10n.loginEmail,
                  prefixIcon: const Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: TokenSpacing.md),
              TextFormField(
                controller: _password,
                enabled: _busyAction.isEmpty,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) => validateNewPassword(l10n, value),
                decoration: InputDecoration(
                  labelText: l10n.authNewPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                  helperText: l10n.authPasswordHint,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? l10n.authShowPassword
                        : l10n.authHidePassword,
                    onPressed: _busyAction.isEmpty
                        ? () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          )
                        : null,
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: TokenSpacing.md),
              TextFormField(
                controller: _confirmation,
                enabled: _busyAction.isEmpty,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                validator: (value) => value != _password.text
                    ? l10n.authValidationPasswordMismatch
                    : null,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.authConfirmPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: TokenSpacing.xl),
              FilledButton(
                onPressed: _busyAction.isEmpty ? _submit : null,
                child: _ButtonContent(
                  loading: _busyAction == 'email',
                  label: isUpgrade
                      ? l10n.authProtectGuestAction
                      : l10n.loginRegister,
                ),
              ),
              const SizedBox(height: TokenSpacing.md),
              OutlinedButton.icon(
                onPressed: _busyAction.isEmpty
                    ? () => _run(
                        'google',
                        ref.read(authRepositoryProvider).signInWithGoogle,
                      )
                    : null,
                icon: _busyAction == 'google'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata, size: 28),
                label: Text(
                  isUpgrade
                      ? l10n.authProtectGuestGoogle
                      : l10n.authContinueGoogle,
                ),
              ),
              if (!isUpgrade)
                TextButton(
                  onPressed: _busyAction.isEmpty ? () => context.pop() : null,
                  child: Text(l10n.loginToSignIn),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  var _busy = false;
  var _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = authErrorText(l10n, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AuthShell(
      showBack: true,
      title: _sent ? l10n.resetSentTitle : l10n.resetTitle,
      subtitle: _sent ? l10n.resetSentBody : l10n.resetBody,
      child: _sent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 64),
                const SizedBox(height: TokenSpacing.xl),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: Text(l10n.resetBackToLogin),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _sent = false),
                  child: Text(l10n.resetTryAnother),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) _InlineError(message: _error!),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    validator: (value) => validateEmail(l10n, value),
                    onFieldSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      labelText: l10n.loginEmail,
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: TokenSpacing.xl),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: _ButtonContent(
                      loading: _busy,
                      label: l10n.resetAction,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _timer;
  var _cooldown = 0;
  var _busyAction = '';
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busyAction = 'check';
      _message = null;
    });
    try {
      final verified = await ref
          .read(authRepositoryProvider)
          .refreshEmailVerification();
      if (mounted && !verified) {
        setState(() {
          _message = l10n.verifyNotYet;
          _messageIsError = false;
        });
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _message = authErrorText(l10n, failure);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busyAction = '');
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busyAction = 'resend';
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _message = l10n.verifyResent;
        _messageIsError = false;
        _cooldown = 30;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _cooldown <= 1) {
          timer.cancel();
          if (mounted) setState(() => _cooldown = 0);
        } else {
          setState(() => _cooldown--);
        }
      });
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _message = authErrorText(l10n, failure);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busyAction = '');
    }
  }

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busyAction = 'signOut';
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _message = authErrorText(l10n, failure);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busyAction = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    return _AuthShell(
      title: l10n.verifyTitle,
      subtitle: l10n.verifyBody(user?.email ?? ''),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: TokenSpacing.lg),
          if (_message != null)
            _messageIsError
                ? _InlineError(message: _message!)
                : Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
          const SizedBox(height: TokenSpacing.lg),
          FilledButton(
            onPressed: _busyAction.isEmpty ? _check : null,
            child: _ButtonContent(
              loading: _busyAction == 'check',
              label: l10n.verifyCheck,
            ),
          ),
          TextButton(
            onPressed: _busyAction.isEmpty && _cooldown == 0 ? _resend : null,
            child: Text(
              _cooldown == 0
                  ? l10n.verifyResend
                  : l10n.verifyResendIn(_cooldown),
            ),
          ),
          TextButton(
            onPressed: _busyAction.isEmpty ? _signOut : null,
            child: _ButtonContent(
              loading: _busyAction == 'signOut',
              label: l10n.authUseAnotherAccount,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthShell extends StatelessWidget {
  const _AuthShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 52,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: TokenSpacing.md),
                  Text(
                    Brand.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: TokenSpacing.xs),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: TokenSpacing.sm),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TokenSpacing.xl),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: TokenSpacing.md),
      padding: const EdgeInsets.all(TokenSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: TokenSpacing.sm),
          Expanded(child: Text(message, key: const Key('auth-error'))),
        ],
      ),
    ),
  );
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.loading, required this.label});

  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) => loading
      ? const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.md),
        child: Text(label),
      ),
      const Expanded(child: Divider()),
    ],
  );
}
