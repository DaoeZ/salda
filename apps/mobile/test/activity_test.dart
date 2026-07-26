import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/activity/data/activity_repository.dart';
import 'package:salda_mobile/features/activity/domain/activity_models.dart';
import 'package:salda_mobile/features/activity/presentation/activity_screen.dart';
import 'package:salda_mobile/features/activity/presentation/activity_tile.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

Future<void> _seedEvent(
  FakeFirebaseFirestore firestore,
  String id, {
  required String type,
  required List<String> memberUids,
  String actorUid = 'uid-otro',
  String? spaceId,
  Map<String, Object> summary = const {},
  required DateTime at,
}) => firestore.doc('activityEvents/$id').set({
  'type': type,
  'actorUid': actorUid,
  'memberUids': memberUids,
  'spaceId': ?spaceId,
  'summary': summary,
  'at': Timestamp.fromDate(at),
  'schemaVersion': 1,
});

void main() {
  group('ActivityRepository', () {
    late FakeFirebaseFirestore firestore;
    late ActivityRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ActivityRepository(firestore: firestore, uid: () => 'owner');
    });

    test(
      'la cronología solo incluye MI audiencia, en orden descendente',
      () async {
        await _seedEvent(
          firestore,
          'e1',
          type: 'space_created',
          memberUids: ['owner'],
          at: DateTime(2026, 7, 1),
        );
        await _seedEvent(
          firestore,
          'e2',
          type: 'ticket_created',
          memberUids: ['owner', 'uid-otro'],
          at: DateTime(2026, 7, 3),
        );
        await _seedEvent(
          firestore,
          'ajeno',
          type: 'ticket_created',
          memberUids: ['uid-otro'],
          at: DateTime(2026, 7, 2),
        );

        final events = await repo.watchFirstPage().first;
        expect(events.map((e) => e.id), ['e2', 'e1']);
        expect(events.first.type, ActivityType.ticketCreated);
      },
    );

    test('el filtro por espacio y el global conviven', () async {
      await _seedEvent(
        firestore,
        's1',
        type: 'member_joined',
        memberUids: ['owner'],
        spaceId: 'sp1',
        at: DateTime(2026, 7, 1),
      );
      await _seedEvent(
        firestore,
        'g1',
        type: 'payment_confirmed',
        memberUids: ['owner'],
        at: DateTime(2026, 7, 2),
      );

      final space = await repo.watchFirstPage(spaceId: 'sp1').first;
      expect(space.map((e) => e.id), ['s1']);
      final global = await repo.watchFirstPage().first;
      expect(global.map((e) => e.id), ['g1', 's1']);
    });

    test(
      'paginación por fecha: fetchOlder trae lo anterior sin repetir',
      () async {
        for (var i = 0; i < 40; i++) {
          await _seedEvent(
            firestore,
            'e$i',
            type: 'ticket_created',
            memberUids: ['owner'],
            at: DateTime(2026, 6, 1).add(Duration(hours: i)),
          );
        }
        final first = await repo.watchFirstPage().first;
        expect(first.length, ActivityRepository.pageSize);

        final older = await repo.fetchOlder(first.last.at!);
        expect(older.length, 40 - ActivityRepository.pageSize);
        final ids = {...first.map((e) => e.id), ...older.map((e) => e.id)};
        expect(ids.length, 40); // sin duplicados entre páginas
      },
    );

    test('el resumen congelado se mapea (rótulos e importes)', () async {
      await _seedEvent(
        firestore,
        'e1',
        type: 'payment_confirmed',
        memberUids: ['owner'],
        summary: {'amount': 1250, 'currency': 'EUR'},
        at: DateTime(2026, 7, 1),
      );
      final event = (await repo.watchFirstPage().first).single;
      expect(event.amountCents, 1250);
      expect(event.currency, 'EUR');
      expect(event.hasAmount, true);
    });
  });

  group('textos y tiempo relativo', () {
    testWidgets('cada tipo tiene un texto propio y legible', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      ActivityEvent event(ActivityType type) => ActivityEvent(
        id: 'x',
        type: type,
        actorUid: 'a',
        spaceName: 'Viaje',
        ticketName: 'Casa Paco',
      );
      // Todos los tipos reales producen texto no vacío y distinto de
      // "Actividad" (el fallback de unknown).
      final seen = <String>{};
      for (final type in ActivityType.values) {
        final text = activityText(l10n, event(type));
        expect(text, isNotEmpty, reason: type.name);
        seen.add(text);
      }
      expect(seen.length, greaterThan(10)); // textos diferenciados
      expect(
        activityText(l10n, event(ActivityType.ticketLinked)),
        contains('Casa Paco'),
      );
      expect(
        activityText(l10n, event(ActivityType.spaceArchived)),
        contains('Viaje'),
      );

      final now = DateTime(2026, 7, 20, 12);
      expect(relativeTime(l10n, now, now), 'ahora');
      expect(
        relativeTime(l10n, now.subtract(const Duration(minutes: 5)), now),
        'hace 5 min',
      );
      expect(
        relativeTime(l10n, now.subtract(const Duration(days: 30)), now),
        '20/06/2026',
      );
    });
  });

  group('ActivityScreen', () {
    Future<FakeFirebaseFirestore> pump(
      WidgetTester tester, {
      FakeFirebaseFirestore? firestore,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = firestore ?? FakeFirebaseFirestore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...loggedInOverrides(firestore: fake),
            activityRepositoryProvider.overrideWithValue(
              ActivityRepository(firestore: fake, uid: () => 'owner'),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ActivityScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('estado vacío', (tester) async {
      await pump(tester);
      // El estado vacío del sistema explica qué es y qué esperar, en vez
      // de una sola frase suelta centrada.
      expect(find.text('Sin movimientos'), findsOneWidget);
      expect(
        find.textContaining('lo que ocurra en tus contextos'),
        findsOneWidget,
      );
    });

    testWidgets('lista eventos con importe y actor por UID; nombres largos '
        'sin overflow', (tester) async {
      final fake = FakeFirebaseFirestore();
      await _seedEvent(
        fake,
        'e1',
        type: 'payment_confirmed',
        memberUids: ['owner'],
        summary: {'amount': 123456789, 'currency': 'EUR'},
        at: DateTime(2026, 7, 19),
      );
      await _seedEvent(
        fake,
        'e2',
        type: 'space_created',
        memberUids: ['owner'],
        summary: {
          'spaceName':
              'Un espacio con un nombre desproporcionadamente largo '
              'para forzar elipsis y no overflow',
        },
        at: DateTime(2026, 7, 18),
      );
      await pump(tester, firestore: fake);

      expect(find.byType(ActivityTile), findsNWidgets(2));
      expect(find.textContaining('1.234.567,89'), findsOneWidget);
      expect(tester.takeException(), isNull); // sin overflows
    });
  });
}
