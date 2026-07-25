import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_environment.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';

/// Enlace de incorporación a un GRUPO (Sprint 4, ADR-035), vista del
/// propietario: QR + copiar + compartir + revocar.
///
/// Misma forma que `ShareScreen` (enlace de sesión) a propósito: el usuario
/// ya sabe qué significa esta pantalla. La diferencia es el alcance — aquí
/// se entra en el grupo, no en una cuenta suelta — y que el enlace es
/// revocable y rotable en cualquier momento.
class SpaceLinkScreen extends ConsumerWidget {
  const SpaceLinkScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final space = ref.watch(spaceProvider(spaceId)).value;
    final link = ref.watch(spaceJoinLinkProvider(spaceId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.spaceLinkTitle)),
      body: link.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.spaceLinkError)),
        data: (active) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: active == null
                  ? _NoLink(spaceId: spaceId, spaceName: space?.name ?? '')
                  : _ActiveLink(link: active, theme: theme),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoLink extends ConsumerStatefulWidget {
  const _NoLink({required this.spaceId, required this.spaceName});

  final String spaceId;
  final String spaceName;

  @override
  ConsumerState<_NoLink> createState() => _NoLinkState();
}

class _NoLinkState extends ConsumerState<_NoLink> {
  bool _working = false;
  var _lifetime = JoinLinkLifetime.never;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        const Icon(Icons.link_outlined, size: 64),
        const SizedBox(height: TokenSpacing.md),
        Text(l10n.spaceLinkEmpty, textAlign: TextAlign.center),
        const SizedBox(height: TokenSpacing.lg),
        _LifetimePicker(
          value: _lifetime,
          onChanged: (value) => setState(() => _lifetime = value),
        ),
        const SizedBox(height: TokenSpacing.lg),
        FilledButton.icon(
          onPressed: _working ? null : _create,
          icon: const Icon(Icons.add_link),
          label: Text(l10n.spaceLinkCreate),
        ),
      ],
    );
  }

  Future<void> _create() async {
    setState(() => _working = true);
    try {
      await ref
          .read(spacesRepositoryProvider)
          .createJoinLink(
            widget.spaceId,
            widget.spaceName,
            lifetime: _lifetime,
          );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// Cuánto vive el enlace. Un enlace es un secreto portador: acotarle la vida
/// limita el daño si acaba donde no debe. Sin caducidad sigue siendo el
/// valor por defecto — el propietario siempre puede revocar.
class _LifetimePicker extends StatelessWidget {
  const _LifetimePicker({required this.value, required this.onChanged});

  final JoinLinkLifetime value;
  final ValueChanged<JoinLinkLifetime> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(JoinLinkLifetime lifetime) => switch (lifetime) {
      JoinLinkLifetime.never => l10n.spaceLinkExpiryNever,
      JoinLinkLifetime.oneDay => l10n.spaceLinkExpiry1d,
      JoinLinkLifetime.sevenDays => l10n.spaceLinkExpiry7d,
      JoinLinkLifetime.thirtyDays => l10n.spaceLinkExpiry30d,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.spaceLinkExpiryLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: TokenSpacing.sm),
        Wrap(
          spacing: TokenSpacing.sm,
          children: [
            for (final lifetime in JoinLinkLifetime.values)
              ChoiceChip(
                label: Text(label(lifetime)),
                selected: lifetime == value,
                onSelected: (_) => onChanged(lifetime),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActiveLink extends ConsumerWidget {
  const _ActiveLink({required this.link, required this.theme});

  final SpaceJoinLink link;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final url = SpacesRepository.joinUrlFor(
      AppEnvironment.hostingDomain,
      link.token,
    );

    return Column(
      children: [
        Text(link.spaceName, style: theme.textTheme.titleLarge),
        const SizedBox(height: TokenSpacing.lg),
        LayoutBuilder(
          builder: (_, constraints) => Card(
            child: Padding(
              padding: const EdgeInsets.all(TokenSpacing.lg),
              child: QrImageView(
                data: url,
                size: constraints.maxWidth.clamp(160.0, 220.0).toDouble(),
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: TokenSpacing.md),
        Text(
          l10n.spaceLinkHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        if (link.expiresAt case final expiry?) ...[
          const SizedBox(height: TokenSpacing.sm),
          Text(
            l10n.spaceLinkExpiresOn(expiry.toLocal()),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: TokenSpacing.xl),
        LayoutBuilder(
          builder: (_, constraints) {
            final buttonWidth = constraints.maxWidth >= 360
                ? (constraints.maxWidth - TokenSpacing.md) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: TokenSpacing.md,
              runSpacing: TokenSpacing.sm,
              children: [
                SizedBox(
                  width: buttonWidth,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.shareCopied)),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l10n.shareCopy),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text: '${link.spaceName} · ${Brand.appName}\n$url',
                      ),
                    ),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text(l10n.shareSystem),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: TokenSpacing.lg),
        // Revocar es la única forma de cerrar la puerta: quien ya tuviera el
        // enlace deja de poder entrar en cuanto se rota.
        TextButton.icon(
          onPressed: () => _rotate(context, ref),
          icon: const Icon(Icons.autorenew, size: 18),
          label: Text(l10n.spaceLinkRotate),
        ),
        TextButton.icon(
          onPressed: () => _revoke(context, ref),
          icon: const Icon(Icons.link_off, size: 18),
          label: Text(l10n.spaceLinkRevoke),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }

  Future<void> _rotate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(context, l10n.spaceLinkRotateConfirm);
    if (!confirmed) return;
    await ref
        .read(spacesRepositoryProvider)
        .rotateJoinLink(
          link.spaceId,
          link.spaceName,
          previousToken: link.token,
        );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(context, l10n.spaceLinkRevokeConfirm);
    if (!confirmed) return;
    await ref.read(spacesRepositoryProvider).revokeJoinLink(link.token);
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
