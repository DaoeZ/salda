import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
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
    final activity = ref.watch(spaceActivityProvider(spaceId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.activityTitle,
          action: l10n.activitySeeAll,
          onAction: () => context.push('/home/spaces/$spaceId/activity'),
        ),
        activity.when(
          // Esqueleto y no un aro girando: la estructura de la lista ya se
          // conoce, así que nada salta de sitio cuando llegan los datos.
          loading: () => const SkeletonList(rows: 3),
          error: (error, _) => ErrorStateView(message: l10n.activityLoadError),
          data: (events) => events.isEmpty
              ? EmptyState(
                  icon: Icons.bolt_outlined,
                  title: l10n.emptyActivityTitle,
                  body: l10n.emptyActivityBody,
                )
              : SaldaCardList(
                  children: [
                    for (final event in events.take(previewCount))
                      ActivityTile(event: event),
                  ],
                ),
        ),
      ],
    );
  }
}
