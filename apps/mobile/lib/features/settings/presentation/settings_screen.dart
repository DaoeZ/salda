import 'dart:convert';

import 'package:design_tokens/design_tokens.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_screen.dart';
import '../../people/data/frequent_people_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../../sessions/application/create_session_controller.dart';
import '../data/backup_service.dart';
import '../data/user_profile_repository.dart';

/// Ajustes (spec §4.1): apariencia, métodos de pago, personas frecuentes,
/// copia de seguridad y cuenta. Los proveedores de IA llegan en M6.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(themeControllerProvider);
    final user = ref.watch(authStateProvider).value;
    final isFullAccount = user?.isFullAccount ?? false;
    final people = isFullAccount
        ? ref.watch(frequentPeopleProvider).value ?? const []
        : const <FrequentPerson>[];

    // Grupos claramente separados: encabezado del sistema y UNA superficie
    // por bloque, con las filas divididas por líneas de un pelo.
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: TokenSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          SaldaCardList(children: children),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ScreenBody(
        children: [
          section(l10n.settingsAppearance, [
            Padding(
              padding: const EdgeInsets.all(TokenSpacing.md),
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.themeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l10n.themeDark),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(themeControllerProvider.notifier)
                    .set(selection.first),
              ),
            ),
          ]),
          if (isFullAccount) ...[
            section(l10n.profileTitle, [const _ProfileTile()]),
            section(l10n.settingsPayments, [const _PaymentMethodsForm()]),
            section(l10n.settingsPeople, [
              if (people.isEmpty)
                ListTile(
                  title: Text(
                    l10n.settingsPeopleEmpty,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                for (final person in people)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(person.name[0]),
                    ),
                    title: Text(person.name),
                    trailing: IconButton(
                      tooltip: l10n.commonDelete,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => ref
                          .read(frequentPeopleRepositoryProvider)
                          .remove(person.id),
                    ),
                  ),
            ]),
          ],
          section(l10n.aiTitle, [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.aiTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/home/settings/ai'),
            ),
          ]),
          section(l10n.settingsBackup, [
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: Text(l10n.backupExport),
              onTap: () => _exportBackup(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(l10n.backupImport),
              onTap: () => _importBackup(context, ref),
            ),
          ]),
          section(l10n.settingsAccount, [const _AccountCard()]),
          const SizedBox(height: TokenSpacing.xl),
        ],
      ),
    );
  }
}

/// Acceso al perfil público (P2): avatar + @username, o invitación a crearlo.
class _ProfileTile extends ConsumerWidget {
  const _ProfileTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentAppUserProvider);
    final profile = ref.watch(myProfileProvider).value;
    return ListTile(
      leading: profile == null
          ? const Icon(Icons.account_circle_outlined)
          : ProfileAvatar(
              seed: user?.uid ?? '',
              displayName: profile.displayName,
              radius: 16,
            ),
      title: Text(profile?.displayName ?? l10n.profileBannerTitle),
      subtitle: profile == null ? null : Text('@${profile.username}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/home/profile'),
    );
  }
}

class _AccountCard extends ConsumerStatefulWidget {
  const _AccountCard();

  @override
  ConsumerState<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends ConsumerState<_AccountCard> {
  var _busy = false;
  String? _error;

  Future<void> _signOut(AppUser user) async {
    final l10n = AppLocalizations.of(context);
    if (user.isAnonymous) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.guestSignOutTitle),
          content: Text(l10n.guestSignOutBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.guestSignOutConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() => _error = authErrorText(l10n, failure.code));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();
    final title = user.isAnonymous
        ? l10n.guestAccount
        : (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!
        : user.email ?? l10n.settingsAccount;
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundImage: user.photoUrl == null
                ? null
                : NetworkImage(user.photoUrl!),
            child: user.photoUrl == null
                ? Icon(
                    user.isAnonymous
                        ? Icons.person_outline
                        : Icons.person_rounded,
                  )
                : null,
          ),
          title: Text(title),
          subtitle: Text(
            user.isAnonymous
                ? l10n.guestAccountBody
                : '${user.email ?? ''} · ${l10n.accountVerified}',
          ),
          trailing: user.isFullAccount
              ? const Icon(Icons.verified_outlined)
              : null,
        ),
        if (user.isAnonymous)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TokenSpacing.md,
              0,
              TokenSpacing.md,
              TokenSpacing.sm,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : () => context.push('/register'),
                icon: const Icon(Icons.security_outlined),
                label: Text(l10n.authProtectGuestAction),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.md),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ListTile(
          leading: _busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
          title: Text(user.isAnonymous ? l10n.guestLeave : l10n.signOut),
          enabled: !_busy,
          onTap: _busy ? null : () => _signOut(user),
        ),
      ],
    );
  }
}

Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
  final backup = await ref.read(backupServiceProvider).exportAll();
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(backup)),
          mimeType: 'application/json',
          name: 'salda-backup-$stamp.json',
        ),
      ],
    ),
  );
}

Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (file == null || !context.mounted) return;

  final service = ref.read(backupServiceProvider);
  Map<String, Object?> backup;
  try {
    backup = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (backup['format'] != BackupService.format) throw const FormatException();
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.backupInvalid)));
    }
    return;
  }
  final summary = service.summarize(backup);
  if (!context.mounted) return;

  final replace = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.backupImport),
      content: Text(
        l10n.backupImportSummary(
          summary.sessions,
          summary.tickets,
          summary.lines,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.backupModeReplace),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.backupModeMerge),
        ),
      ],
    ),
  );
  if (replace == null || !context.mounted) return;

  await service.import(backup, replace: replace);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.backupImported)));
  }
}

class _PaymentMethodsForm extends ConsumerStatefulWidget {
  const _PaymentMethodsForm();

  @override
  ConsumerState<_PaymentMethodsForm> createState() =>
      _PaymentMethodsFormState();
}

class _PaymentMethodsFormState extends ConsumerState<_PaymentMethodsForm> {
  final _bizum = TextEditingController();
  final _paypal = TextEditingController();
  final _revolut = TextEditingController();
  final _iban = TextEditingController();
  var _loaded = false;

  @override
  void dispose() {
    for (final c in [_bizum, _paypal, _revolut, _iban]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    await ref
        .read(userProfileRepositoryProvider)
        .savePaymentMethods(
          PaymentMethods(
            bizumPhone: _bizum.text.trim(),
            paypalLink: _paypal.text.trim(),
            revolutTag: _revolut.text.trim(),
            iban: _iban.text.replaceAll(' ', '').toUpperCase(),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.paymentsSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(userProfileProvider).value;
    if (!_loaded && profile != null) {
      _loaded = true;
      _bizum.text = profile.paymentMethods.bizumPhone;
      _paypal.text = profile.paymentMethods.paypalLink;
      _revolut.text = profile.paymentMethods.revolutTag;
      _iban.text = profile.paymentMethods.iban;
    }

    return Padding(
      padding: const EdgeInsets.all(TokenSpacing.lg),
      child: Column(
        children: [
          Text(
            l10n.settingsPaymentsHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: TokenSpacing.md),
          TextField(
            controller: _bizum,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l10n.paymentBizum),
          ),
          const SizedBox(height: TokenSpacing.md),
          TextField(
            controller: _paypal,
            decoration: InputDecoration(labelText: l10n.paymentPaypal),
          ),
          const SizedBox(height: TokenSpacing.md),
          TextField(
            controller: _revolut,
            decoration: InputDecoration(labelText: l10n.paymentRevolut),
          ),
          const SizedBox(height: TokenSpacing.md),
          TextField(
            controller: _iban,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: l10n.paymentIban),
          ),
          const SizedBox(height: TokenSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _save,
              child: Text(l10n.commonSave),
            ),
          ),
        ],
      ),
    );
  }
}
