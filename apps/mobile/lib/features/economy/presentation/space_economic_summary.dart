import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../spaces/data/spaces_repository.dart';
import '../application/identity_names.dart';
import 'economic_names.dart';
import 'obligation_settlement.dart';
import '../data/economic_repository.dart';

/// Situación económica del espacio.
///
/// Antes lo decidía TODO a partir de las obligaciones abiertas: si no había
/// ninguna, anunciaba «todavía no tienes movimientos económicos». Eso es
/// falso en cuanto hay un ticket cuyo reparto deja a todo el mundo a cero
/// —por ejemplo uno que pagó y consumió la misma persona—, que es justo lo
/// que ocurría en el dispositivo: un gasto real y una portada afirmando que
/// no había pasado nada.
///
/// Ahora hay cuatro estados y ninguno se confunde con otro: cargando, error,
/// sin actividad, y con actividad (en paz o con saldos abiertos). La
/// actividad se deduce de los TICKETS del espacio —el mismo stream que ya
/// alimenta la lista de tickets— y los saldos siguen saliendo del ledger:
/// aquí no se recalcula economía.
class SpaceEconomicSummary extends ConsumerWidget {
  const SpaceEconomicSummary({required this.spaceId, super.key});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(
      spaceManageableEconomicOverviewProvider(spaceId),
    );
    final tickets = ref.watch(spaceTicketsProvider(spaceId));

    Widget cuerpo() {
      // 1) CARGANDO — nunca se afirma que no hay nada mientras falten datos.
      if (overview.isLoading || tickets.isLoading) {
        return const SkeletonList(rows: 2, leading: false);
      }
      // 2) ERROR — tampoco se disfraza de vacío.
      if (overview.hasError || tickets.hasError) {
        return ErrorStateView(message: l10n.economyLoadError);
      }

      final scoped = overview.value!;
      final open = scoped.balances
          .where((balance) => balance.signedOutstandingCents != 0)
          .toList();
      final lista = tickets.value!;
      final gastado = lista.fold<int>(
        0,
        (total, ticket) => total + ticket.grandTotalCents,
      );

      // 3) SIN ACTIVIDAD — ni tickets ni saldos: aquí sí es cierto.
      if (open.isEmpty && lista.isEmpty) {
        return EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: l10n.spaceEconomicEmptyTitle,
          body: l10n.spaceEconomicEmpty,
        );
      }

      // 4) CON ACTIVIDAD.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GastoTotal(cents: gastado, tickets: lista.length),
          const SizedBox(height: TokenSpacing.md),
          if (open.isEmpty)
            // Saldo cero CON gasto: estáis en paz. Es una buena noticia, y
            // una información distinta de «no ha pasado nada».
            SaldaCard(
              color: context.salda.positiveMuted,
              borderColor: context.salda.positive.withValues(alpha: 0.25),
              child: Row(
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: context.salda.positive,
                  ),
                  const SizedBox(width: TokenSpacing.md),
                  Expanded(child: Text(l10n.spaceEconomicSettled)),
                ],
              ),
            )
          else
            SaldaCardList(
              children: [
                for (final balance in open)
                  _SpaceBalanceTile(
                    balance: balance,
                    viewerUid: scoped.viewerUid,
                    spaceId: spaceId,
                  ),
              ],
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.spaceEconomicTitle),
        cuerpo(),
      ],
    );
  }
}

/// Cuánto se ha gastado en el espacio. Es el dato que demuestra que «aquí ha
/// pasado algo» aunque el saldo entre las personas sea cero.
class _GastoTotal extends StatelessWidget {
  const _GastoTotal({required this.cents, required this.tickets});

  final int cents;
  final int tickets;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.spaceEconomicSpent,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: 2),
                MoneyText(Money(cents), size: MoneySize.medium),
              ],
            ),
          ),
          StatusBadge(l10n.spaceTicketsCount(tickets)),
        ],
      ),
    );
  }
}

class _SpaceBalanceTile extends ConsumerWidget {
  const _SpaceBalanceTile({
    required this.balance,
    required this.viewerUid,
    required this.spaceId,
  });

  final BilateralEconomicBalance balance;
  final String viewerUid;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final otherUid = balance.firstUid == viewerUid
        ? balance.secondUid
        : balance.firstUid;
    // Antes caia al actor crudo: para un MANUAL eso es `manual:{id}`, que
    // es justo lo que se veia en los saldos.
    final name = economicNameText(ref, l10n, otherUid);
    final iOwe = balance.debtorUid == viewerUid;
    // Quien representa a alguien SIN cuenta ve deudas de las que no es parte:
    // pintarlas como suyas era falso (ADR-038).
    final amParty =
        balance.firstUid == viewerUid || balance.secondUid == viewerUid;
    final debtor = balance.debtorUid;
    final creditor = balance.creditorUid;
    final canConfirm =
        debtor != null &&
        creditor != null &&
        !iOwe &&
        canViewerConfirmReceipt(ref, creditorActor: creditor, spaceId: spaceId);
    return ListTile(
      onTap: () => context.push('/home/economy/$otherUid'),
      leading: SaldaAvatar(
        seed: economicAvatarSeed(otherUid),
        label: name,
        radius: 17,
      ),
      title: Text(
        amParty
            ? (iOwe ? l10n.economyYouOwe(name) : l10n.economyOwesYou(name))
            : l10n.economyOwesTo(
                economicNameText(ref, l10n, debtor ?? otherUid),
                economicNameText(ref, l10n, creditor ?? otherUid),
              ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(
            balance.outstanding,
            size: MoneySize.small,
            currency: balance.currency,
            tone: !amParty
                ? MoneyTone.muted
                : iOwe
                ? MoneyTone.negative
                : MoneyTone.positive,
          ),
          if (canConfirm)
            IconButton(
              tooltip: l10n.economyConfirmPayment,
              icon: const Icon(Icons.check_rounded, size: 20),
              onPressed: () => openObligationSettlement(
                context,
                debtorActor: debtor,
                creditorActor: creditor,
                currency: balance.currency,
                spaceId: spaceId,
              ),
            ),
        ],
      ),
    );
  }
}
