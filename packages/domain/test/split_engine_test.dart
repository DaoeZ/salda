import 'dart:math';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('SplitEngine', () {
    test('todos los participantes aparecen en el resultado, aunque con 0',
        () {
      final result = SplitEngine.splitTicket(
        participantIds: ['a', 'b', 'c'],
        mode: SplitMode.byItem,
        ticket: const SplitTicketInput(
          grandTotal: Money(500),
          lines: [
            SplitLine(
              id: 'l1',
              totalPrice: Money(500),
              assignment: LineAssignment(AssignmentType.one, {'a': 1}),
            ),
          ],
        ),
      );
      expect(result.keys, ['a', 'b', 'c']);
      expect(result['b'], Money.zero);
      expect(result['c'], Money.zero);
    });

    test('equal ignora las líneas y reparte solo el total', () {
      final result = SplitEngine.splitTicket(
        participantIds: ['a', 'b'],
        mode: SplitMode.equal,
        ticket: const SplitTicketInput(
          grandTotal: Money(1000),
          lines: [
            SplitLine(
              id: 'l1',
              totalPrice: Money(1000),
              assignment: LineAssignment(AssignmentType.one, {'a': 1}),
            ),
          ],
        ),
      );
      expect(result['a'], const Money(500));
      expect(result['b'], const Money(500));
    });

    test('byItem con líneas de importe cero cae a partes iguales', () {
      final result = SplitEngine.splitTicket(
        participantIds: ['a', 'b'],
        mode: SplitMode.byItem,
        ticket: const SplitTicketInput(
          grandTotal: Money(300),
          lines: [
            SplitLine(
              id: 'l1',
              totalPrice: Money(0),
              assignment: LineAssignment(AssignmentType.one, {'a': 1}),
            ),
          ],
        ),
      );
      expect(result['a'], const Money(150));
      expect(result['b'], const Money(150));
    });

    test('participante inactivo simplemente no se pasa en la lista', () {
      // "Todos" significa todos los ACTIVOS: el llamante filtra la lista.
      final result = SplitEngine.splitTicket(
        participantIds: ['a', 'c'], // b excluido de este ticket
        mode: SplitMode.byItem,
        ticket: const SplitTicketInput(
          grandTotal: Money(100),
          lines: [
            SplitLine(
              id: 'l1',
              totalPrice: Money(100),
              assignment: LineAssignment.all,
            ),
          ],
        ),
      );
      expect(result['a'], const Money(50));
      expect(result['c'], const Money(50));
    });

    test('propiedad: Σ consumo == grandTotal (500 tickets sembrados)', () {
      final rng = Random(7);
      const types = AssignmentType.values;
      for (var t = 0; t < 500; t++) {
        final n = 1 + rng.nextInt(6);
        final pids = List<String>.generate(n, (i) => 'p$i');
        final lines = List<SplitLine>.generate(rng.nextInt(8), (i) {
          final type = types[1 + rng.nextInt(3)]; // one|shared|all
          final weights = switch (type) {
            AssignmentType.one => {pids[rng.nextInt(n)]: 1},
            AssignmentType.shared => {
                for (final p in (pids.toList()..shuffle(rng))
                    .take(1 + rng.nextInt(n)))
                  p: 1 + rng.nextInt(5),
              },
            _ => const <String, int>{},
          };
          return SplitLine(
            id: 'l$i',
            totalPrice: Money(rng.nextInt(5000)),
            assignment: LineAssignment(type, weights),
          );
        });
        // Total independiente del subtotal (simula impuestos/descuentos).
        final total = Money(rng.nextInt(100000));
        final result = SplitEngine.splitTicket(
          participantIds: pids,
          mode: SplitMode.byItem,
          ticket: SplitTicketInput(grandTotal: total, lines: lines),
        );
        final sum = result.values.fold<int>(0, (a, m) => a + m.cents);
        expect(sum, total.cents, reason: 'caso $t');
      }
    });

    test('unitsFromQuantityMilli: enteros ≥2 son unidades; el resto, 1', () {
      expect(SplitLine.unitsFromQuantityMilli(1000), 1);
      expect(SplitLine.unitsFromQuantityMilli(2000), 2);
      expect(SplitLine.unitsFromQuantityMilli(5000), 5);
      expect(SplitLine.unitsFromQuantityMilli(466), 1); // a peso
      expect(SplitLine.unitsFromQuantityMilli(2500), 1); // 2,5 no es entero
    });

    test(
        'propiedad P2.1: con unidades y pagador, Σ consumo == grandTotal '
        '(500 tickets sembrados)', () {
      final rng = Random(11);
      for (var t = 0; t < 500; t++) {
        final n = 1 + rng.nextInt(6);
        final pids = List<String>.generate(n, (i) => 'p$i');
        final payer = pids[rng.nextInt(n)];
        final lines = List<SplitLine>.generate(rng.nextInt(8), (i) {
          final units = 1 + rng.nextInt(5);
          // Reclamaciones parciales a propósito: pesos que a veces no llegan
          // a cubrir las unidades (el residual cae al pagador).
          final claimers = (pids.toList()..shuffle(rng))
              .take(1 + rng.nextInt(n))
              .toList();
          final weights = {
            for (final p in claimers) p: 1 + rng.nextInt(units),
          };
          return SplitLine(
            id: 'l$i',
            totalPrice: Money(rng.nextInt(5000)),
            units: units,
            assignment: LineAssignment(
              claimers.length == 1
                  ? AssignmentType.one
                  : AssignmentType.shared,
              weights,
            ),
          );
        });
        final total = Money(rng.nextInt(100000));
        final result = SplitEngine.splitTicket(
          participantIds: pids,
          mode: SplitMode.byItem,
          payerId: payer,
          ticket: SplitTicketInput(grandTotal: total, lines: lines),
        );
        final sum = result.values.fold<int>(0, (a, m) => a + m.cents);
        expect(sum, total.cents, reason: 'caso $t');
      }
    });
  });
}
