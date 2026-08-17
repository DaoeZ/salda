import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/spaces_repository.dart';
import 'space_group_cover.dart';
import 'space_relationship_cover.dart';

/// Chooses the context-first cover. Administration is deliberately second
/// level, at `/home/spaces/:sid/manage`.
class SpaceDetailScreen extends ConsumerWidget {
  const SpaceDetailScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(spaceProvider(spaceId))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => Scaffold(
            appBar: AppBar(),
            body: ScreenBody(
              children: [
                ErrorStateView(
                  message: l10n.spacesLoadError,
                  onRetry: () => ref.invalidate(spaceProvider(spaceId)),
                ),
              ],
            ),
          ),
          data: (space) {
            if (space == null) {
              return Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(l10n.spaceGone)),
              );
            }
            return space.isRelationship
                ? RelationshipSpaceCover(space: space)
                : GroupSpaceCover(space: space);
          },
        );
  }
}
