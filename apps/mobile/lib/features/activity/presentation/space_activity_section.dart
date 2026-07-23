import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/activity_repository.dart';
import 'activity_tile.dart';

/// Actividad reciente de un espacio, embebida en su detalle (P6). Muestra
/// los últimos eventos en vivo y enlaza a la cronología completa paginada.
class SpaceActivitySection extends ConsumerWidget {
  const SpaceActivitySection({super.key, required this.spaceId});

  final String spaceId;

  static const int previewCount = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final activity = ref.watch(spaceActivityProvider(spaceId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.activityTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () =>
                  context.push('/home/spaces/$spaceId/activity'),
              child: Text(l10n.activitySeeAll),
            ),
          ],
        ),
        activity.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(TokenSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(TokenSpacing.lg),
              child: Text(
                l10n.activityLoadError,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          data: (events) => events.isEmpty
              ? Card(
                  child: Padding(
                    padding: const EdgeInsets.all(TokenSpacing.lg),
                    child: Text(
                      l10n.activityEmpty,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final event in events.take(previewCount))
                        ActivityTile(event: event),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
