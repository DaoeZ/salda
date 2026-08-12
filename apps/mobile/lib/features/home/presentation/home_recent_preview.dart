import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/domain/activity_models.dart';
import '../../activity/presentation/activity_tile.dart';

/// Dos eventos de actividad real y fechada; no usa sesiones como historial.
class HomeRecentPreview extends ConsumerWidget {
  const HomeRecentPreview({super.key});

  bool _hasDestination(ActivityEvent event) =>
      event.paymentId != null ||
      (event.sessionId?.isNotEmpty ?? false) ||
      (event.spaceId?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(globalActivityProvider)
        .when(
          loading: () =>
              const Column(children: [SectionGap(), SkeletonList(rows: 2)]),
          error: (_, _) => Column(
            children: [
              const SectionGap(),
              ErrorStateView(message: l10n.activityLoadError),
            ],
          ),
          data: (events) {
            final visible =
                events
                    .where(
                      (event) => event.at != null && _hasDestination(event),
                    )
                    .toList()
                  ..sort((a, b) => b.at!.compareTo(a.at!));
            if (visible.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                const SectionGap(),
                SectionHeader(
                  title: l10n.homeRecent,
                  action: l10n.activityTitle,
                  onAction: () => context.push('/home/activity'),
                ),
                SaldaCardList(
                  children: [
                    for (final event in visible.take(2))
                      ActivityTile(event: event),
                  ],
                ),
              ],
            );
          },
        );
  }
}
