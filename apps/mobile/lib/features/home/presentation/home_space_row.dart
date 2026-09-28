import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../spaces/domain/space_models.dart';
import '../../spaces/presentation/space_title_text.dart';

/// Fila compacta y perezosa exclusiva de Inicio. Solo resuelve el título de
/// las filas montadas; los contadores de personas y manuales pertenecen al
/// detalle, no a una lista que puede contener decenas de contextos.
class HomeSpaceRow extends ConsumerWidget {
  const HomeSpaceRow({
    super.key,
    required this.space,
    required this.currencyBalances,
    required this.pendingManualLinks,
    required this.attentionKnown,
  });

  final Space space;
  final Map<String, int> currencyBalances;
  final int pendingManualLinks;
  final bool attentionKnown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.salda;
    final title = spaceTitleLabel(
      ref.watch(spaceTitleProvider(space.id)),
      l10n,
      space.name,
    );
    return InkWell(
      onTap: () => context.push('/home/spaces/${space.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.lg,
          vertical: TokenSpacing.md,
        ),
        child: Row(
          children: [
            SaldaAvatar(
              seed: space.id,
              label: title.isEmpty ? space.name : title,
              emoji: space.avatarEmoji,
              square: !space.isRelationship,
              radius: 19,
            ),
            const SizedBox(width: TokenSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isEmpty)
                    const Skeleton.line(width: 110, height: 15)
                  else
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  const SizedBox(height: 4),
                  if (!attentionKnown)
                    const Skeleton.line(width: 72, height: 11)
                  else if (pendingManualLinks > 0)
                    Semantics(
                      label: l10n.manualLinkPendingInSpace(pendingManualLinks),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.assignment_ind_outlined,
                            size: 15,
                            color: c.warning,
                          ),
                          const SizedBox(width: TokenSpacing.xs),
                          Flexible(
                            child: Text(
                              l10n.manualLinkPendingInSpace(pendingManualLinks),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: c.warning),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      l10n.spacesTitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: TokenSpacing.md),
            _CurrencyBalances(currencyBalances: currencyBalances),
          ],
        ),
      ),
    );
  }
}

class _CurrencyBalances extends StatelessWidget {
  const _CurrencyBalances({required this.currencyBalances});

  final Map<String, int> currencyBalances;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    if (currencyBalances.isEmpty) {
      return Text(
        '—',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: c.textMuted),
      );
    }
    final entries = currencyBalances.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 126),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: MoneyText(
                Money(entry.value),
                size: MoneySize.small,
                currency: entry.key,
                signed: true,
                tone: entry.value > 0 ? MoneyTone.positive : MoneyTone.negative,
              ),
            ),
        ],
      ),
    );
  }
}
