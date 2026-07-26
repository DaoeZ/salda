import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/activity_repository.dart';
import '../domain/activity_models.dart';
import 'activity_tile.dart';

/// Cronología (P6): global o de un espacio. La primera página llega EN VIVO
/// por stream; el historial anterior se pagina bajo demanda por fecha.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.spaceId});

  final String? spaceId;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final List<ActivityEvent> _older = [];
  var _loadingMore = false;
  var _exhausted = false;

  Future<void> _loadMore(List<ActivityEvent> live) async {
    if (_loadingMore || _exhausted) return;
    final last = (_older.isNotEmpty ? _older : live).lastOrNull?.at;
    if (last == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(activityRepositoryProvider)
          .fetchOlder(last, spaceId: widget.spaceId);
      if (!mounted) return;
      setState(() {
        // La página viva puede crecer por delante; aquí solo se acumula lo
        // ESTRICTAMENTE anterior, sin duplicar ids.
        final known = {...live.map((e) => e.id), ..._older.map((e) => e.id)};
        _older.addAll(page.where((event) => !known.contains(event.id)));
        _exhausted = page.length < ActivityRepository.pageSize;
      });
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).activityLoadError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = widget.spaceId == null
        ? ref.watch(globalActivityProvider)
        : ref.watch(spaceActivityProvider(widget.spaceId!));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.activityTitle)),
      body: live.when(
        loading: () => const ScreenBody(children: [SkeletonList(rows: 6)]),
        error: (error, _) => ScreenBody(
          children: [
            ErrorStateView(
              message: l10n.activityLoadError,
              onRetry: () => widget.spaceId == null
                  ? ref.invalidate(globalActivityProvider)
                  : ref.invalidate(spaceActivityProvider(widget.spaceId!)),
            ),
          ],
        ),
        data: (events) {
          if (events.isEmpty && _older.isEmpty) {
            return ScreenBody(
              children: [
                EmptyState(
                  icon: Icons.bolt_outlined,
                  title: l10n.emptyActivityTitle,
                  body: l10n.emptyActivityBody,
                ),
              ],
            );
          }
          final canLoadMore =
              !_exhausted &&
              (events.length >= ActivityRepository.pageSize ||
                  _older.isNotEmpty);
          return ScreenBody(
            children: [
              SaldaCardList(
                children: [
                  for (final event in events) ActivityTile(event: event),
                  for (final event in _older) ActivityTile(event: event),
                ],
              ),
              if (canLoadMore)
                Padding(
                  padding: const EdgeInsets.only(top: TokenSpacing.lg),
                  child: Center(
                    child: _loadingMore
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : OutlinedButton(
                            onPressed: () => _loadMore(events),
                            child: Text(l10n.activityLoadMore),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
