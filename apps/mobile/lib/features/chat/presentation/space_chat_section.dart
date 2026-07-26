import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Entrada contextual al chat desde una Relación o Grupo.
class SpaceChatSection extends StatelessWidget {
  const SpaceChatSection({
    super.key,
    required this.spaceId,
    required this.isActive,
  });

  final String spaceId;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: TokenSpacing.md,
        leading: const Icon(Icons.forum_outlined),
        title: Text(l10n.chatTitle),
        subtitle: Text(
          isActive ? l10n.chatDescription : l10n.chatReadOnly,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/home/spaces/$spaceId/chat'),
      ),
    );
  }
}
