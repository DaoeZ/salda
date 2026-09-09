// A19 en la app: el gasto nace sabiendo a quién espera, cambiar tu consumo
// te devuelve a «eligiendo» en el mismo commit, y «He terminado» te saca.
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
const _linePath = '$_ticketPath/lines/l1';

FirestoreSessionRepository _repo(FakeFirebaseFirestore fake) =>
    FirestoreSessionRepository(
      firestore: fake,
      uid: () => 'owner',
      shareCodeFactory: () => 'TEST-CODE-1234567890',
    );

/// Ticket bajo el protocolo, con p1 (dueña) y p2 (Jorge) pendientes.
Future<FakeFirebaseFirestore> _seed({bool protocolo = true}) async {
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
    'name': 'Edgar',
    'isOwner': true,
    'order': 0,
    'claimedByDevice': 'owner',
    'active': true,
  });
  await fake.doc('sessions/s1/participants/p2').set({
    'name': 'Alba',
    'isOwner': false,
    'order': 1,
    'claimedByDevice': 'dev-2',
    'active': true,
  });
  await fake.doc(_ticketPath).set({
    'kind': 'manual',
    'grandTotal': 400,
    'paidByParticipantId': 'p1',
    if (protocolo) 'pickingModelVersion': 1,
    if (protocolo)
      'picking': {
        'open': {'p1': true, 'p2': true},
      },
  });
  await fake.doc(_linePath).set({
    'name': 'Flauta',
    'order': 0,
    'quantityMilli': 2000,
    'totalPrice': 400,
    'unitIds': ['u0', 'u1'],
    'assignment': {
      'type': 'units',
      'schemaVersion': 2,
      'units': <String, Object?>{},
    },
  });
  return fake;
}

void main() {
  group('A19: siembra al crear el gasto', () {
    test('un ticket nuevo nace con el protocolo y todos pendientes', () async {
      final repo = _repo(FakeFirebaseFirestore());
      final creada = await repo.createSession(
        NewSessionInput(
          name: 'Cena',
          kind: 'single',
          participantNames: const ['Edgar', 'Alba', 'Tete'],
          payerIndex: 0,
          splitModeDefault: SplitMode.byItem,
          ticket: const NewTicketInput(
            merchantName: 'Bar',
            grandTotal: Money(600),
            kind: 'manual',
            engine: 'manual',
            confidence: 1.0,
            lines: [NewLineInput(name: 'Cerveza', totalPrice: Money(600))],
          ),
        ),
      );
      final ticket = await repo.firestore.doc(creada.ticketPath).get();
      expect(ticket.data()!['pickingModelVersion'], 1);
      expect((ticket.data()!['picking'] as Map)['open'], {
        'p0': true,
        'p1': true,
        'p2': true,
      });
    });

    test(
      'añadir un gasto siembra SOLO con los participantes activos',
      () async {
        final repo = _repo(FakeFirebaseFirestore());
        final creada = await repo.createSession(
          NewSessionInput(
            name: 'Cena',
            kind: 'single',
            participantNames: const ['Edgar', 'Alba'],
            payerIndex: 0,
            splitModeDefault: SplitMode.byItem,
            spaceId: 'gr1',
            ticket: const NewTicketInput(
              merchantName: 'Bar',
              grandTotal: Money(600),
              kind: 'manual',
              engine: 'manual',
              confidence: 1.0,
              lines: [NewLineInput(name: 'Cerveza', totalPrice: Money(600))],
            ),
          ),
        );
        // Alba deja de participar antes del segundo gasto.
        await repo.firestore
            .doc('sessions/${creada.sessionId}/participants/p1')
            .update({'active': false});

        final path = await repo.addTicket(
          creada.sessionId,
          const NewTicketInput(
            merchantName: 'Otro',
            grandTotal: Money(200),
            kind: 'manual',
            engine: 'manual',
            confidence: 1.0,
            lines: [NewLineInput(name: 'Café', totalPrice: Money(200))],
          ),
          payerPid: 'p0',
          spaceId: 'gr1',
        );
        final ticket = await repo.firestore.doc(path).get();
        // A quien ya no participa no se le espera: recompute lo descarta igual.
        expect((ticket.data()!['picking'] as Map)['open'], {'p0': true});
      },
    );
  });

  group('A19: escrituras del protocolo', () {
    test('elegir consumo reabre a esa persona en el MISMO commit', () async {
      final fake = await _seed();
      final repo = _repo(fake);
      await repo.finishPicking(_ticketPath, participantId: 'p2');
      expect(
        ((await fake.doc(_ticketPath).get()).data()!['picking'] as Map)['open'],
        {'p1': true},
      );

      await repo.setUnitConsumer(
        _linePath,
        unit: 0,
        participantId: 'p2',
        selected: true,
        myPid: 'p2',
        usesPicking: true,
      );
      final picking =
          (await fake.doc(_ticketPath).get()).data()!['picking'] as Map;
      expect((picking['open'] as Map)['p2'], true);
      // El objetivo se declara: es lo que verifican las Rules.
      expect(picking['lastTarget'], 'p2');
    });

    test('en un gasto anterior al protocolo NO se escribe picking', () async {
      final fake = await _seed(protocolo: false);
      final repo = _repo(fake);
      await repo.setUnitConsumer(
        _linePath,
        unit: 0,
        participantId: 'p2',
        selected: true,
        myPid: 'p2',
      );
      // Escribirle `picking` haría que las Rules rechazasen el lote entero.
      expect(
        (await fake.doc(_ticketPath).get()).data()!.containsKey('picking'),
        isFalse,
      );
    });

    test('He terminado saca mi pid de la lista de pendientes', () async {
      final fake = await _seed();
      final repo = _repo(fake);
      await repo.finishPicking(_ticketPath, participantId: 'p1');
      final picking =
          (await fake.doc(_ticketPath).get()).data()!['picking'] as Map;
      expect((picking['open'] as Map).containsKey('p1'), isFalse);
      expect(picking['lastTarget'], 'p1');
    });

    test('el ticket transporta quién falta por terminar', () async {
      final fake = await _seed();
      final tickets = await _repo(fake).watchTickets('s1', 'a1').first;
      expect(tickets.single.usesPicking, isTrue);
      expect(tickets.single.pickingOpen, {'p1', 'p2'});
    });
  });

  group('A19: la pantalla dice a quién se espera', () {
    Future<void> pump(WidgetTester tester, FakeFirebaseFirestore fake) async {
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
                ticket: SessionTicket(
                  id: 't1',
                  path: _ticketPath,
                  merchantName: 'Bar Manolo',
                  grandTotal: const Money(400),
                  paidBy: 'p1',
                  kind: 'manual',
                  splitModeOverride: SplitMode.byItem,
                  pickingModelVersion: 1,
                  pickingOpen: const {'p1', 'p2'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('un gasto abierto enumera quién falta y ofrece He terminado', (
      tester,
    ) async {
      await pump(tester, await _seed());
      expect(find.text('Aún estáis eligiendo'), findsOneWidget);
      expect(find.textContaining('Falta Edgar, Alba'), findsOneWidget);
      expect(find.text('He terminado'), findsOneWidget);
    });

    testWidgets('con autoridad A10 se puede terminar por otra persona', (
      tester,
    ) async {
      await pump(tester, await _seed());
      // El dueño de la sesión tiene A10: cierra por Alba.
      expect(find.text('Terminar por Alba'), findsOneWidget);
    });
  });
}
