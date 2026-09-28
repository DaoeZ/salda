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
import '../../economy/data/economic_repository.dart';
import '../data/spaces_repository.dart';
import '../domain/space_identities.dart';
import '../domain/space_models.dart';
import 'space_title_text.dart';

/// Fila de un contexto, IDÉNTICA en Inicio y en la lista de espacios.
///
/// Lleva exactamente tres cosas: quién/qué es, cuánta gente hay, y cómo
/// estás con ese contexto. El tipo se distingue por la FORMA del avatar
/// —círculo una relación, cuadrado redondeado un grupo— antes de leer nada;
/// el estado pendiente lleva su propia etiqueta.
class SpaceRow extends ConsumerWidget {
  const SpaceRow({super.key, required this.space});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.salda;
    final l10n = AppLocalizations.of(context);
    final title = spaceTitleLabel(
      ref.watch(spaceTitleProvider(space.id)),
      l10n,
      space.name,
    );

    final members = ref.watch(spaceMembersProvider(space.id));
    final manuals = ref.watch(spaceManualParticipantsProvider(space.id));
    final counted = members.hasValue && manuals.hasValue;
    // Mismo resolver central que el resto de la app (BUG-6): las personas,
    // no las cuentas.
    final people = counted
        ? spaceEconomicIdentities(
            members: members.value!,
            manuals: manuals.value!,
          ).length
        : 0;
    final ready = counted && contextReadyForExpenses(space.kind, people);

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
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (!counted)
                        const Skeleton.line(width: 62, height: 11)
                      else ...[
                        Flexible(
                          child: Text(
                            l10n.peopleCount(people),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: c.textMuted),
                          ),
                        ),
                        // Un contexto que aún no puede repartir se dice, no
                        // se deja adivinar por un botón apagado dentro.
                        if (!ready) ...[
                          const SizedBox(width: TokenSpacing.sm),
                          Flexible(
                            child: StatusBadge(
                              l10n.contextPendingShort,
                              tone: BadgeTone.pending,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: TokenSpacing.md),
            // Un saldo largo con el texto ampliado se reduce antes que
            // desbordar la fila.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _SpaceBalance(spaceId: space.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saldo del usuario EN ese contexto. Cero no se pinta como «0,00 €», que
/// compite con los importes reales: se pinta como un guion tenue.
class _SpaceBalance extends ConsumerWidget {
  const _SpaceBalance({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.salda;
    final overview = ref.watch(economicOverviewProvider);
    if (!overview.hasValue) {
      return const Skeleton.line(width: 52, height: 15);
    }
    final scoped = overview.value!.withinSpace(spaceId);
    final nets = <String, int>{};
    for (final balance in scoped.balances) {
      if (balance.signedOutstandingCents == 0) continue;
      final signed = balance.debtorUid == scoped.viewerUid
          ? -balance.outstanding.cents
          : balance.outstanding.cents;
      nets[balance.currency] = (nets[balance.currency] ?? 0) + signed;
    }
    nets.removeWhere((_, cents) => cents == 0);
    if (nets.isEmpty) {
      return Text(
        '—',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: c.textMuted),
      );
    }
    if (nets.length > 1) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Text(
          AppLocalizations.of(context).balanceMultipleCurrencies,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
        ),
      );
    }
    final entry = nets.entries.single;
    return MoneyText(
      Money(entry.value),
      size: MoneySize.small,
      currency: entry.key,
      signed: true,
      tone: entry.value > 0 ? MoneyTone.positive : MoneyTone.negative,
    );
  }
}
