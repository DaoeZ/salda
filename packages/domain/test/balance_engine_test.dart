import 'dart:math';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('BalanceEngine', () {
    test('sin tickets: todo a cero y sin liquidaciones', () {
      final result = BalanceEngine.compute(
        participantIds: ['a', 'b'],
        tickets: [],
      );
      expect(result.settlements, isEmpty);
      expect(result.balances['a']!.net, Money.zero);
    });

    test('consumo puede omitir participantes (cuentan como 0)', () {
      final result = BalanceEngine.compute(
        participantIds: ['a', 'b', 'c'],
        tickets: [
          const TicketContribution(
            paidBy: 'a',
            grandTotal: Money(600),
            consumption: {'b': Money(600)},
          ),
        ],
      );
      expect(result.balances['c']!.consumed, Money.zero);
      expect(result.balances['c']!.net, Money.zero);
    });

    test('liquidación congelada con participante desconocido es error', () {
      expect(
        () => BalanceEngine.compute(
          participantIds: ['a', 'b'],
          tickets: const [],
          frozenSettlements: const [
            FrozenSettlement(from: 'x', to: 'a', amount: Money(1)),
          ],
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.code,
            'code',
            DomainException.unknownParticipant,
          ),
        ),
      );
    });

    test('genera como mucho N-1 liquidaciones', () {
      final result = BalanceEngine.compute(
        participantIds: ['a', 'b', 'c', 'd', 'e'],
        tickets: [
          const TicketContribution(
            paidBy: 'a',
            grandTotal: Money(1000),
            consumption: {
              'b': Money(100),
              'c': Money(200),
              'd': Money(300),
              'e': Money(400),
            },
          ),
          const TicketContribution(
            paidBy: 'b',
            grandTotal: Money(500),
            consumption: {'a': Money(250), 'c': Money(250)},
          ),
        ],
      );
      expect(result.settlements.length, lessThanOrEqualTo(4));
    });

    test('propiedad: aplicar las liquidaciones sugeridas deja a todos en paz '
        '(300 sesiones sembradas)', () {
      final rng = Random(99);
      for (var s = 0; s < 300; s++) {
        final n = 2 + rng.nextInt(5);
        final pids = List<String>.generate(n, (i) => 'p$i');
        final tickets = List<TicketContribution>.generate(1 + rng.nextInt(5), (
          _,
        ) {
          final total = Money(1 + rng.nextInt(10000));
          final shares = allocateEvenly(total, n);
          return TicketContribution(
            paidBy: pids[rng.nextInt(n)],
            grandTotal: total,
            consumption: {for (var i = 0; i < n; i++) pids[i]: shares[i]},
          );
        });
        final result = BalanceEngine.compute(
          participantIds: pids,
          tickets: tickets,
        );

        // Invariante 1: Σ outstanding == 0.
        final sum = result.balances.values.fold<int>(
          0,
          (a, b) => a + b.outstanding.cents,
        );
        expect(sum, 0, reason: 'sesión $s');

        // Invariante 2: ejecutar las transferencias sugeridas salda todo.
        final after = {
          for (final p in pids) p: result.balances[p]!.outstanding.cents,
        };
        for (final settlement in result.settlements) {
          expect(settlement.amount > Money.zero, isTrue);
          after[settlement.from] =
              after[settlement.from]! + settlement.amount.cents;
          after[settlement.to] =
              after[settlement.to]! - settlement.amount.cents;
        }
        for (final p in pids) {
          expect(after[p], 0, reason: 'sesión $s, participante $p');
        }
      }
    });

    test('determinismo: mismo input, mismo output (incluido orden)', () {
      const tickets = [
        TicketContribution(
          paidBy: 'a',
          grandTotal: Money(900),
          consumption: {'b': Money(450), 'c': Money(450)},
        ),
      ];
      final r1 = BalanceEngine.compute(
        participantIds: ['a', 'b', 'c'],
        tickets: tickets,
      );
      final r2 = BalanceEngine.compute(
        participantIds: ['a', 'b', 'c'],
        tickets: tickets,
      );
      expect(r1.settlements, r2.settlements);
    });
  });
}
