import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Destinos secundarios de Inicio, agrupados en UN menú.
///
/// Antes eran seis `IconButton` en la barra superior: seis siluetas grises
/// del mismo tamaño que había que leer una a una, y que además cambiaban de
/// número según el tipo de usuario. Un menú con rótulos se lee mejor que una
/// fila de iconos que se parecen, y deja la barra tranquila.
class HomeMenuButton extends ConsumerWidget {
  const HomeMenuButton({
    super.key,
    required this.participates,
    required this.fullAccount,
  });

  final bool participates;
  final bool fullAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.salda;

    return PopupMenuButton<String>(
      tooltip: l10n.homeMenuTitle,
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_horiz),
      onSelected: (route) => context.push(route),
      itemBuilder: (_) => [
        if (participates) ...[
          _item(
            context,
            '/home/activity',
            Icons.bolt_outlined,
            l10n.activityTitle,
          ),
          _item(
            context,
            '/home/economy',
            Icons.account_balance_wallet_outlined,
            l10n.economyTitle,
          ),
        ],
        if (fullAccount) ...[
          _item(
            context,
            '/home/friends',
            Icons.people_outline,
            l10n.friendsTitle,
          ),
          _item(
            context,
            '/home/history',
            Icons.inventory_2_outlined,
            l10n.historyTitle,
          ),
          const PopupMenuDivider(),
          _item(
            context,
            '/home/profile',
            Icons.person_outline,
            l10n.profileTitle,
          ),
        ],
        _item(
          context,
          '/home/settings',
          Icons.tune,
          l10n.settingsTitle,
          color: c.textSecondary,
        ),
      ],
    );
  }

  PopupMenuItem<String> _item(
    BuildContext context,
    String route,
    IconData icon,
    String label, {
    Color? color,
  }) => PopupMenuItem<String>(
    value: route,
    height: TokenLayout.minTouchTarget,
    child: Row(
      children: [
        Icon(icon, size: 19, color: color ?? context.salda.textSecondary),
        const SizedBox(width: TokenSpacing.md),
        Text(label),
      ],
    ),
  );
}

/// Acción principal de una pantalla, en fila y a ancho completo cuando es
/// la única cosa que se espera que hagas ahí.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 19),
            label: Text(label),
          ),
  );
}
