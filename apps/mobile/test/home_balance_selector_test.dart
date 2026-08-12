import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/home/application/home_balance_selector.dart';

void main() {
  test('empty overview has no preview rows', () {
    final result = selectHomeBalancePreview(
      EconomicOverview.compute(
        viewerUid: 'me',
        entries: const [],
        payments: const [],
      ),
    );

    expect(result.totalCount, 0);
    expect(result.rows, isEmpty);
  });

  test('ties use the stable person key', () {
    final overview = EconomicOverview.compute(
      viewerUid: 'me',
      entries: const [
        EconomicEntryView(
          id: 'a',
          debtorUid: 'zoe',
          creditorUid: 'me',
          amount: Money(100),
          currency: 'EUR',
          sessionId: 's',
          accountId: 'a',
          ticketId: 't',
          ticketName: 'Ticket',
        ),
        EconomicEntryView(
          id: 'b',
          debtorUid: 'ana',
          creditorUid: 'me',
          amount: Money(100),
          currency: 'EUR',
          sessionId: 's',
          accountId: 'a',
          ticketId: 't',
          ticketName: 'Ticket',
        ),
      ],
      payments: const [],
    );

    expect(
      selectHomeBalancePreview(overview).rows.map((row) => row.personUid),
      ['ana', 'zoe'],
    );
  });

  test(
    'limits a five, excludes zeroes and preserves currency and direction',
    () {
      final entries = <EconomicEntryView>[
        for (var i = 0; i < 15; i++)
          EconomicEntryView(
            id: 'owed-$i',
            debtorUid: 'person-$i',
            creditorUid: 'me',
            amount: Money(100 + i),
            currency: i.isEven ? 'EUR' : 'USD',
            sessionId: 's',
            accountId: 'a',
            ticketId: 't',
            ticketName: 'Ticket',
          ),
        for (var i = 0; i < 15; i++)
          EconomicEntryView(
            id: 'owe-$i',
            debtorUid: 'me',
            creditorUid: 'other-$i',
            amount: Money(200 + i),
            currency: i.isEven ? 'EUR' : 'GBP',
            sessionId: 's',
            accountId: 'a',
            ticketId: 't',
            ticketName: 'Ticket',
          ),
      ];
      final overview = EconomicOverview.compute(
        viewerUid: 'me',
        entries: entries,
        payments: const [],
      );

      final result = selectHomeBalancePreview(overview);

      expect(result.totalCount, 30);
      expect(result.rows, hasLength(5));
      expect(
        result.rows.map((row) => row.currency).toSet(),
        containsAll(['EUR', 'GBP', 'USD']),
      );
      expect(
        result.rows.map((row) => row.direction).toSet(),
        containsAll(HomeBalanceDirection.values),
      );
      expect(result.rows.every((row) => row.amount.cents > 0), isTrue);
    },
  );
}
