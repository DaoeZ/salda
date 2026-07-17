/// Runner de los vectores dorados (test/golden/*.json).
///
/// Estos mismos JSON los ejecuta la implementación TS en
/// backend/functions/src/test/golden.test.ts: si alguna implementación
/// diverge del vector, su CI rompe. NO editar un vector sin actualizar
/// y revisar ambas implementaciones.
library;

import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('golden: SplitEngine', () {
    final cases = _load('test/golden/split_engine.json');
    for (final c in cases) {
      test(c['name'] as String, () {
        final ticketJson = c['ticket'] as Map<String, dynamic>;
        Map<String, Money> run() => SplitEngine.splitTicket(
          participantIds: (c['participants'] as List).cast<String>(),
          mode: SplitMode.values.byName(c['mode'] as String),
          unassignedPolicy: c['unassignedPolicy'] == 'all'
              ? UnassignedLinePolicy.splitAmongAll
              : UnassignedLinePolicy.error,
          payerId: c['payerId'] as String?,
          ticket: SplitTicketInput(
            grandTotal: Money(ticketJson['grandTotal'] as int),
            lines: [
              for (final l
                  in (ticketJson['lines'] as List).cast<Map<String, dynamic>>())
                SplitLine(
                  id: l['id'] as String,
                  totalPrice: Money(l['totalPrice'] as int),
                  units: (l['units'] as int?) ?? 1,
                  unitConsumers: (l['unitConsumers'] as Map<String, dynamic>?)
                      ?.map(
                        (unit, consumers) => MapEntry(
                          int.parse(unit),
                          (consumers as List).cast<String>(),
                        ),
                      ),
                  assignment: _assignment(
                    l['assignment'] as Map<String, dynamic>,
                  ),
                ),
            ],
          ),
        );

        final expectedError = c['expectedError'] as String?;
        if (expectedError != null) {
          expect(
            run,
            throwsA(
              isA<DomainException>().having(
                (e) => e.code,
                'code',
                expectedError,
              ),
            ),
          );
        } else {
          final result = run();
          expect(
            result.map((k, v) => MapEntry(k, v.cents)),
            (c['expected'] as Map<String, dynamic>).cast<String, int>(),
          );
        }
      });
    }
  });

  group('golden: BalanceEngine', () {
    final cases = _load('test/golden/balance_engine.json');
    for (final c in cases) {
      test(c['name'] as String, () {
        BalanceResult run() => BalanceEngine.compute(
          participantIds: (c['participants'] as List).cast<String>(),
          tickets: [
            for (final t in (c['tickets'] as List).cast<Map<String, dynamic>>())
              TicketContribution(
                paidBy: t['paidBy'] as String,
                grandTotal: Money(t['grandTotal'] as int),
                consumption: (t['consumption'] as Map<String, dynamic>).map(
                  (k, v) => MapEntry(k, Money(v as int)),
                ),
              ),
          ],
          frozenSettlements: [
            for (final f
                in ((c['frozenSettlements'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>())
              FrozenSettlement(
                from: f['from'] as String,
                to: f['to'] as String,
                amount: Money(f['amount'] as int),
              ),
          ],
        );

        final expectedError = c['expectedError'] as String?;
        if (expectedError != null) {
          expect(
            run,
            throwsA(
              isA<DomainException>().having(
                (e) => e.code,
                'code',
                expectedError,
              ),
            ),
          );
          return;
        }

        final result = run();
        final expected = c['expected'] as Map<String, dynamic>;

        final expectedBalances = (expected['balances'] as Map<String, dynamic>)
            .map((pid, b) => MapEntry(pid, (b as Map<String, dynamic>)));
        expect(result.balances.length, expectedBalances.length);
        for (final entry in expectedBalances.entries) {
          final actual = result.balances[entry.key]!;
          expect(actual.paid.cents, entry.value['paid'], reason: entry.key);
          expect(
            actual.consumed.cents,
            entry.value['consumed'],
            reason: entry.key,
          );
          expect(actual.net.cents, entry.value['net'], reason: entry.key);
          expect(
            actual.outstanding.cents,
            entry.value['outstanding'],
            reason: entry.key,
          );
        }

        expect(result.settlements, [
          for (final s
              in (expected['settlements'] as List).cast<Map<String, dynamic>>())
            SettlementDraft(
              from: s['from'] as String,
              to: s['to'] as String,
              amount: Money(s['amount'] as int),
            ),
        ]);
      });
    }
  });
}

List<Map<String, dynamic>> _load(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return (json['cases'] as List).cast<Map<String, dynamic>>();
}

LineAssignment _assignment(Map<String, dynamic> json) {
  return LineAssignment(
    AssignmentType.values.byName(json['type'] as String),
    ((json['weights'] as Map<String, dynamic>?) ?? const {})
        .cast<String, int>(),
  );
}
