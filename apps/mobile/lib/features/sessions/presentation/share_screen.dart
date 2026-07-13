import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/session_providers.dart';

/// Compartir sesión: QR grande + enlace (spec §2.1 paso final).
/// El shareCode viaja en el fragment (#k=) para no llegar a logs (spec §13).
class ShareScreen extends ConsumerWidget {
  const ShareScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = ref.watch(sessionDetailProvider(sessionId)).value;

    if (detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final url =
        'https://${Brand.hostingDomain}/s/$sessionId#k=${detail.shareCode}';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TokenSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(children: [
              Text(detail.summary.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: TokenSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(TokenSpacing.lg),
                  child: QrImageView(
                    data: url,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: TokenSpacing.md),
              Text(
                l10n.shareHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: TokenSpacing.xl),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.shareCopied)));
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l10n.shareCopy),
                  ),
                ),
                const SizedBox(width: TokenSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                          text: '${detail.summary.name} · ${Brand.appName}\n$url'),
                    ),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text(l10n.shareSystem),
                  ),
                ),
              ]),
              const SizedBox(height: TokenSpacing.md),
              TextButton(
                onPressed: () => context.go('/home/session/$sessionId'),
                child: Text(l10n.commonDone),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
