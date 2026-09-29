import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';

/// Entrada de cuenta breve. Los detalles siguen en Ajustes para conservar los
/// flujos ya existentes sin convertir la barra de Inicio en navegación global.
class AccountHubScreen extends ConsumerWidget {
  const AccountHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentAppUserProvider);
    final fullAccount = user?.isFullAccount ?? false;
    final guestDisplayName = user?.isAnonymous == true
        ? ref.watch(myGuestIdentityProvider).value?.displayName
        : null;
    final profile = ref
        .watch(myProfileProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final name =
        profile?.displayName ??
        guestDisplayName ??
        user?.displayName ??
        l10n.guestAccount;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountHubTitle)),
      // Una sola hoja: la identidad arriba y, debajo, las puertas. Antes cada
      // fila vivía en su propia caja bajo un encabezado que repetía su
      // nombre («Personas» → «Personas»): cuatro cajas para cuatro enlaces.
      body: ScreenBody(
        children: [
          SaldaCardList(
            children: [
              ListTile(
                leading: ProfileAvatar(
                  seed: user?.uid ?? '',
                  displayName: name,
                  radius: 20,
                ),
                title: Text(name),
                subtitle: profile == null ? null : Text('@${profile.username}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  fullAccount ? '/home/profile' : '/home/guest-name',
                ),
              ),
              if (fullAccount)
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(l10n.personasTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/home/personas'),
                ),
              if (fullAccount)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(l10n.historyTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/home/history'),
                ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(l10n.accountHubOpenSettings),
                subtitle: Text(
                  '${l10n.accountHubPayments}, ${l10n.accountHubPreferences}, '
                  '${l10n.accountHubData} y ${l10n.accountHubAdvanced}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/home/settings'),
              ),
            ],
          ),
          const SizedBox(height: TokenSpacing.xl),
        ],
      ),
    );
  }
}
