import 'dart:convert';

import 'package:design_tokens/design_tokens.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../people/data/frequent_people_repository.dart';
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
    final people = ref.watch(frequentPeopleProvider).value ?? const [];

    Widget section(String title, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  TokenSpacing.xs, TokenSpacing.xl, 0, TokenSpacing.sm),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            Card(child: Column(children: children)),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        children: [
          section(l10n.settingsAppearance, [
            Padding(
              padding: const EdgeInsets.all(TokenSpacing.md),
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                      value: ThemeMode.system, label: Text(l10n.themeSystem)),
                  ButtonSegment(
                      value: ThemeMode.light, label: Text(l10n.themeLight)),
                  ButtonSegment(
                      value: ThemeMode.dark, label: Text(l10n.themeDark)),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(themeControllerProvider.notifier)
                    .set(selection.first),
              ),
            ),
          ]),
          section(l10n.settingsPayments, [const _PaymentMethodsForm()]),
          section(l10n.settingsPeople, [
            if (people.isEmpty)
              ListTile(
                  title: Text(l10n.settingsPeopleEmpty,
                      style: theme.textTheme.bodySmall))
            else
              for (final person in people)
                ListTile(
                  leading: CircleAvatar(
                      radius: 16, child: Text(person.name[0])),
                  title: Text(person.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => ref
                        .read(frequentPeopleRepositoryProvider)
                        .remove(person.id),
                  ),
                ),
          ]),
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
          section(l10n.settingsAccount, [
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.signOut),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ]),
          const SizedBox(height: TokenSpacing.xl),
        ],
      ),
    );
  }
}

Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
  final backup = await ref.read(backupServiceProvider).exportAll();
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  await SharePlus.instance.share(ShareParams(files: [
    XFile.fromData(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(backup)),
      mimeType: 'application/json',
      name: 'salda-backup-$stamp.json',
    ),
  ]));
}

Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final file = await openFile(acceptedTypeGroups: [
    const XTypeGroup(label: 'JSON', extensions: ['json']),
  ]);
  if (file == null || !context.mounted) return;

  final service = ref.read(backupServiceProvider);
  Map<String, Object?> backup;
  try {
    backup =
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
    if (backup['format'] != BackupService.format) throw const FormatException();
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.backupInvalid)));
    }
    return;
  }
  final summary = service.summarize(backup);
  if (!context.mounted) return;

  final replace = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.backupImport),
      content: Text(l10n.backupImportSummary(
          summary.sessions, summary.tickets, summary.lines)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonCancel)),
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.backupModeReplace)),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.backupModeMerge)),
      ],
    ),
  );
  if (replace == null || !context.mounted) return;

  await service.import(backup, replace: replace);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.backupImported)));
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
    await ref.read(userProfileRepositoryProvider).savePaymentMethods(
          PaymentMethods(
            bizumPhone: _bizum.text.trim(),
            paypalLink: _paypal.text.trim(),
            revolutTag: _revolut.text.trim(),
            iban: _iban.text.replaceAll(' ', '').toUpperCase(),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.paymentsSaved)));
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
      child: Column(children: [
        Text(l10n.settingsPaymentsHint,
            style: Theme.of(context).textTheme.bodySmall),
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
              onPressed: _save, child: Text(l10n.commonSave)),
        ),
      ]),
    );
  }
}
