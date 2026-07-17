import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

const _ticketPath = 'sessions/s1/accounts/a1/tickets/t1';

Future<FakeFirebaseFirestore> _seed() async {
  final fake = FakeFirebaseFirestore();
  await fake.doc('sessions/s1').set({
    'ownerUid': 'owner',
    'kind': 'single',
    'name': 'Cena',
    'status': 'open',
    'splitModeDefault': 'byItem',
    'shareCode': 'TEST-CODE-1234567890',
    'currency': 'EUR',
  });
  await fake.doc('sessions/s1/participants/p1').set({
    'name': 'Edgar', 'isOwner': true, 'order': 0, 'claimedByDevice': '',
  });
  await fake.doc('sessions/s1/participants/p2').set({
    'name': 'Alba', 'isOwner': false, 'order': 1, 'claimedByDevice': 'dev-2',
  });
  await fake.doc(_ticketPath).set({
    'kind': 'manual',
    'grandTotal': 400,
    'paidByParticipantId': 'p1',
  });
  await fake.doc('$_ticketPath/lines/l1').set({
    'name': 'Flauta de pollo',
    'order': 0,
    'quantityMilli': 2000,
    'totalPrice': 400,
    'assignment': {'type': 'unassigned', 'participants': <String, int>{}},
  });
  await fake.doc('$_ticketPath/lines/l2').set({
    'name': 'Pizza',
    'order': 1,
    'quantityMilli': 1000,
    'totalPrice': 1200,
    'assignment': {
      'type': 'one',
      'participants': {'p2': 1},
    },
  });
  return fake;
}

Future<void> _pump(WidgetTester tester, FakeFirebaseFirestore fake) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: loggedInOverrides(firestore: fake),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TicketDetailScreen(
          ticket: TicketRef(
            sessionId: 's1',
            payerName: 'Edgar',
            ticket: const SessionTicket(
              id: 't1',
              path: _ticketPath,
              merchantName: 'Bar Manolo',
              grandTotal: Money(400),
              paidBy: 'p1',
              kind: 'manual',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('repositorio: líneas vivas y asignación del owner', () {
    test('watchTicketLines expone asignación, unidades y pesos', () async {
      final fake = await _seed();
      final repo = FirestoreSessionRepository(
        firestore: fake,
        uid: () => 'owner',
        shareCodeFactory: () => 'X',
      );
      final lines = await repo.watchTicketLines(_ticketPath).first;
      expect(lines, hasLength(2));
      expect(lines.first.units, 2);
      expect(lines.first.weightOf('p1'), 0);
      expect(lines.last.units, 1);
      expect(lines.last.weightOf('p2'), 1);
      expect(lines.last.othersThan('p1'), ['p2']);
    });

    test('setLineAssignment escribe la misma forma que la web', () async {
      final fake = await _seed();
      final repo = FirestoreSessionRepository(
        firestore: fake,
        uid: () => 'owner',
        shareCodeFactory: () => 'X',
      );

      // El creador reclama 1 unidad conservando la entrada de Alba.
      await repo.setLineAssignment(
        '$_ticketPath/lines/l2',
        {'p2': 1, 'p1': 1},
        editorPid: 'p1',
      );
      var assignment = (await fake.doc('$_ticketPath/lines/l2').get())
          .data()!['assignment'] as Map<String, dynamic>;
      expect(assignment['type'], 'shared');
      expect(assignment['participants'], {'p2': 1, 'p1': 1});
      expect(assignment['lastEditorPid'], 'p1');

      // Quitarse (peso 0) limpia la entrada y recalcula el tipo.
      await repo.setLineAssignment(
        '$_ticketPath/lines/l2',
        {'p2': 1, 'p1': 0},
        editorPid: 'p1',
      );
      assignment = (await fake.doc('$_ticketPath/lines/l2').get())
          .data()!['assignment'] as Map<String, dynamic>;
      expect(assignment['type'], 'one');
      expect(assignment['participants'], {'p2': 1});

      // Nadie → unassigned (todo a 0).
      await repo.setLineAssignment(
        '$_ticketPath/lines/l2',
        {'p2': 0, 'p1': 0},
        editorPid: 'p1',
      );
      assignment = (await fake.doc('$_ticketPath/lines/l2').get())
          .data()!['assignment'] as Map<String, dynamic>;
      expect(assignment['type'], 'unassigned');
      expect(assignment['participants'], isEmpty);
    });
  });

  group('detalle del ticket: el creador selecciona (P2.1)', () {
    testWidgets('línea de 1 unidad: tap reclama y muestra quién la tiene', (
      tester,
    ) async {
      final fake = await _seed();
      await _pump(tester, fake);

      // La pizza la tiene Alba; el creador se suma con un toque.
      expect(find.text('Lo tiene Alba'), findsOneWidget);
      await tester.tap(find.text('Pizza'));
      await tester.pumpAndSettle();

      final assignment = (await fake.doc('$_ticketPath/lines/l2').get())
          .data()!['assignment'] as Map<String, dynamic>;
      expect(assignment['type'], 'shared');
      expect(assignment['participants'], {'p2': 1, 'p1': 1});
      expect(find.text('Compartido con Alba'), findsOneWidget);
    });

    testWidgets('línea multi-unidad: el stepper reclama unidades sueltas', (
      tester,
    ) async {
      final fake = await _seed();
      await _pump(tester, fake);

      // 2 flautas: el creador reclama una con "+".
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      var assignment = (await fake.doc('$_ticketPath/lines/l1').get())
          .data()!['assignment'] as Map<String, dynamic>;
      expect(assignment['participants'], {'p1': 1});

      // Y la segunda: el peso es el número de unidades.
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();
      assignment = (await fake.doc('$_ticketPath/lines/l1').get())
          .data()!['assignment'] as Map<String, dynamic>;
      expect(assignment['participants'], {'p1': 2});

      // El "+" queda deshabilitado al llegar al máximo de unidades.
      final addButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.add_circle_outline).first,
          matching: find.byType(IconButton),
        ),
      );
      expect(addButton.onPressed, isNull);
    });

    testWidgets('sesión cerrada: sin selección posible', (tester) async {
      final fake = await _seed();
      await fake.doc('sessions/s1').update({'status': 'closed'});
      await _pump(tester, fake);

      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.circle_outlined), findsNothing);
    });
  });
}
