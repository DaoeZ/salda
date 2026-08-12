import 'package:domain/domain.dart';

import '../../economy/domain/economic_models.dart';

/// Dirección visible de una relación económica desde quien usa la app.
enum HomeBalanceDirection { owedToMe, iOwe }

/// Una fila del resumen de Inicio. No agrega personas ni convierte monedas.
class HomeBalanceRow {
  const HomeBalanceRow({
    required this.personUid,
    required this.currency,
    required this.direction,
    required this.amount,
  });

  final String personUid;
  final String currency;
  final HomeBalanceDirection direction;
  final Money amount;

  String get stableKey => '$currency:${direction.name}:$personUid';
}

/// Vista compacta y honesta del listado económico completo.
class HomeBalancePreview {
  const HomeBalancePreview({required this.rows, required this.totalCount});

  final List<HomeBalanceRow> rows;
  final int totalCount;
}

/// Selecciona como máximo [limit] relaciones para Inicio.
///
/// Cada relación se mantiene separada por persona, moneda y dirección. Los
/// bloques se entrelazan en orden estable para que una sola moneda o dirección
/// no desplace completamente las otras; dentro de cada bloque manda el importe
/// y, ante empate, la clave estable.
HomeBalancePreview selectHomeBalancePreview(
  EconomicOverview overview, {
  int limit = 5,
}) {
  final rows = <HomeBalanceRow>[];
  for (final balance in overview.balances) {
    final debtor = balance.debtorUid;
    final creditor = balance.creditorUid;
    if (debtor == null || creditor == null || balance.outstanding.cents == 0) {
      continue;
    }
    if (creditor == overview.viewerUid) {
      rows.add(
        HomeBalanceRow(
          personUid: debtor,
          currency: balance.currency,
          direction: HomeBalanceDirection.owedToMe,
          amount: balance.outstanding,
        ),
      );
    } else if (debtor == overview.viewerUid) {
      rows.add(
        HomeBalanceRow(
          personUid: creditor,
          currency: balance.currency,
          direction: HomeBalanceDirection.iOwe,
          amount: balance.outstanding,
        ),
      );
    }
  }

  final grouped = <String, List<HomeBalanceRow>>{};
  for (final row in rows) {
    grouped
        .putIfAbsent('${row.currency}:${row.direction.name}', () => [])
        .add(row);
  }
  final keys = grouped.keys.toList()..sort();
  for (final key in keys) {
    grouped[key]!.sort((a, b) {
      final amount = b.amount.cents.compareTo(a.amount.cents);
      return amount != 0 ? amount : a.stableKey.compareTo(b.stableKey);
    });
  }
  final selected = <HomeBalanceRow>[];
  for (var index = 0; selected.length < limit; index++) {
    var added = false;
    for (final key in keys) {
      final group = grouped[key]!;
      if (index < group.length && selected.length < limit) {
        selected.add(group[index]);
        added = true;
      }
    }
    if (!added) break;
  }
  return HomeBalancePreview(rows: selected, totalCount: rows.length);
}
