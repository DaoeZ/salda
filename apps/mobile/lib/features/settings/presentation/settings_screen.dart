import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../people/data/frequent_people_repository.dart';
import '../../sessions/application/create_session_controller.dart';
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
