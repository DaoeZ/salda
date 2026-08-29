import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:salda_mobile/features/sessions/application/session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';
import 'package:domain/domain.dart';

import 'fakes.dart';

/// A10: repartir el consumo de otras personas.
///
/// Lo que se fija aquí es a quién se le OFRECE repartir —las Rules son la
/// autoridad; esto decide qué se enseña— y que la escritura que sale sea la
/// de siempre por unidad, firmada, sin tocar el contenido del gasto.
void main() {
  const ticketPath = 'sessions/s1/accounts/a1/tickets/t1';
  const linePath = '$ticketPath/lines/l1';
  SessionTicket ticketCon(SplitMode mode) => SessionTicket(
    id: 't1',
    path: ticketPath,
    merchantName: 'Bar',
    grandTotal: const Money(1000),
    paidBy: 'p1',
    kind: 'manual',
    spaceId: 'g1',
    contextModelVersion: 1,
    splitModeOverride: mode,
  );

  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> sembrar({
    String kind = 'group',
    String status = 'open',
    SplitMode mode = SplitMode.byItem,
  }) async {
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': 'jefa',
      'kind': kind,
      'relationshipUids': kind == 'relationship' ? ['owner', 'pareja'] : [],
      'status': 'active',
      'schemaVersion': 2,
    });
    for (final uid in ['jefa', 'owner', 'admin', 'miembro', 'pareja']) {
      await firestore.doc('spaces/g1/members/$uid').set({
        'uid': uid,
        if (uid == 'admin') 'role': 'admin',
      });
    }
    await firestore.doc('sessions/s1').set({
      'ownerUid': 'owner',
      'kind': 'single',
      'name': 'Cena',
      'status': status,
      'splitModeDefault': mode.name,
      'shareCode': 'TEST-CODE-1234567890',
      'currency': 'EUR',
      'spaceId': 'g1',
      'contextModelVersion': 1,
    });
    await firestore.doc('sessions/s1/participants/p1').set({
      'name': 'Edgar',
      'isOwner': true,
      'order': 0,
      'claimedByDevice': 'owner',
      'active': true,
    });
    await firestore.doc('sessions/s1/participants/p2').set({
      'name': 'Alba',
      'isOwner': false,
      'order': 1,
      'claimedByDevice': 'miembro',
      'active': true,
    });
    // Persona MANUAL: no tiene cuenta y aun así consume.
    await firestore.doc('sessions/s1/participants/p3').set({
      'name': 'Tete',
      'isOwner': false,
      'order': 2,
      'claimedByDevice': '',
      'manualId': 'm-tete',
      'active': true,
    });
    // Quien ya no participa no se ofrece para consumo nuevo.
    await firestore.doc('sessions/s1/participants/p4').set({
      'name': 'Retirada',
      'isOwner': false,
      'order': 3,
      'claimedByDevice': '',
      'active': false,
    });
    await firestore.doc('sessions/s1/accounts/a1').set({'name': 'Cena'});
    await firestore.doc(ticketPath).set({
      'kind': 'manual',
      'grandTotal': 1000,
      'paidByParticipantId': 'p1',
      'merchant': {'name': 'Bar'},
      'spaceId': 'g1',
      'contextModelVersion': 1,
      'splitModeOverride': mode.name,
    });
    await firestore.doc(linePath).set({
      'name': 'Cocacola',
      'totalPrice': 1000,
      'quantityMilli': 2000,
      'order': 0,
      'unitIds': ['u0', 'u1'],
      'assignment': {
        'type': 'units',
        'schemaVersion': 2,
        'units': <String, Object?>{},
      },
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    String uid = 'owner',
    SplitMode mode = SplitMode.byItem,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        ...loggedInOverrides(firestore: firestore, uid: uid),
        // En producción SOLO la dueña de la sesión la lee (ahí vive el
        // shareCode); sin esto cualquier uid parecería la creadora.
        if (uid != 'owner')
          sessionDetailProvider('s1').overrideWith(
            (ref) => Stream<SessionDetail?>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            ),
          ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TicketDetailScreen(
            ticket: TicketRef(
              sessionId: 's1',
              payerName: 'Edgar',
              ticket: ticketCon(mode),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<Map<String, dynamic>> asignacion() async =>
      (await firestore.doc(linePath).get()).data()!['assignment']
          as Map<String, dynamic>;

  final unidad1 = find.byType(FilterChip);

  group('a quién se le ofrece repartir', () {
    testWidgets('el creador del gasto abre el reparto de una unidad', (
      tester,
    ) async {
      await sembrar();
      await pump(tester);
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      expect(find.text('¿Quién consume la unidad 1?'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('quien administra el grupo también, en el gasto ajeno', (
      tester,
    ) async {
      await sembrar();
      await pump(tester, uid: 'admin');
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      expect(find.text('¿Quién consume la unidad 1?'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('el propietario del grupo también', (tester) async {
      await sembrar();
      await pump(tester, uid: 'jefa');
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      expect(find.text('¿Quién consume la unidad 1?'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('un miembro normal NO: sigue marcando solo lo suyo', (
      tester,
    ) async {
      await sembrar();
      await pump(tester, uid: 'miembro');
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();

      expect(find.text('¿Quién consume la unidad 1?'), findsNothing);
      // Y lo que escribe es su propio consumo, como siempre.
      expect((await asignacion())['units'], {
        'u0': {'p2': true},
      });
      await cerrar(tester);
    });

    testWidgets('la contraparte de una RELACIÓN tampoco reparte por otros', (
      tester,
    ) async {
      await sembrar(kind: 'relationship');
      // La contraparte SÍ participa del reparto: tiene su participante.
      await firestore.doc('sessions/s1/participants/p2').update({
        'claimedByDevice': 'pareja',
      });
      await pump(tester, uid: 'pareja');
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();

      // Marca LO SUYO —sin enlace de invitado— pero no reparte por nadie.
      expect(find.text('¿Quién consume la unidad 1?'), findsNothing);
      expect(((await asignacion())['units'] as Map)['u0'], {'p2': true});
      await cerrar(tester);
    });

    testWidgets('a partes iguales no hay reparto por producto', (tester) async {
      await sembrar(mode: SplitMode.equal);
      await pump(tester, mode: SplitMode.equal);
      expect(unidad1, findsNothing);
      await cerrar(tester);
    });

    testWidgets('con la sesión cerrada, tampoco', (tester) async {
      await sembrar(status: 'closed');
      await pump(tester);
      expect(unidad1, findsNothing);
      await cerrar(tester);
    });
  });

  group('lo que se escribe al repartir', () {
    testWidgets('asignar a otra persona deja la asignación y quién la hizo', (
      tester,
    ) async {
      await sembrar();
      await pump(tester, uid: 'admin');
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alba'));
      await tester.pumpAndSettle();

      final assignment = await asignacion();
      expect((assignment['units'] as Map)['u0'], {'p2': true});
      expect(((assignment['by'] as Map)['u0'] as Map)['p2'], 'admin');
      // Repartir NO toca el contenido del gasto.
      final line = (await firestore.doc(linePath).get()).data()!;
      expect(line['name'], 'Cocacola');
      expect(line['totalPrice'], 1000);
      expect(line['quantityMilli'], 2000);
      await cerrar(tester);
    });

    testWidgets('a una persona MANUAL, que no tiene que entrar a nada', (
      tester,
    ) async {
      await sembrar();
      await pump(tester);
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Tete'));
      await tester.pumpAndSettle();

      expect(((await asignacion())['units'] as Map)['u0'], {'p3': true});
      await cerrar(tester);
    });

    testWidgets('compartir una unidad entre dos personas', (tester) async {
      await sembrar();
      await pump(tester);
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alba'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Tete'));
      await tester.pumpAndSettle();

      expect(((await asignacion())['units'] as Map)['u0'], {
        'p2': true,
        'p3': true,
      });
      await cerrar(tester);
    });

    testWidgets('retirar a alguien se lleva también su firma', (tester) async {
      await sembrar();
      await pump(tester);
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alba'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alba'));
      await tester.pumpAndSettle();

      final assignment = await asignacion();
      expect((assignment['units'] as Map)['u0'], isEmpty);
      expect((assignment['by'] as Map)['u0'], isEmpty);
      await cerrar(tester);
    });

    testWidgets('cada unidad se reparte por separado', (tester) async {
      await sembrar();
      await pump(tester);
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Edgar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      await tester.tap(unidad1.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alba'));
      await tester.pumpAndSettle();

      final assignment = await asignacion();
      expect((assignment['units'] as Map)['u0'], {'p1': true});
      expect((assignment['units'] as Map)['u1'], {'p2': true});
      await cerrar(tester);
    });

    testWidgets('quien ya no participa no se ofrece', (tester) async {
      await sembrar();
      await pump(tester);
      await tester.tap(unidad1.first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Retirada'), findsNothing);
      expect(find.widgetWithText(CheckboxListTile, 'Tete'), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('la escritura es quirúrgica', () {
    test('solo toca el par (unidad, persona), y firma quién lo hizo', () async {
      await sembrar();
      await firestore.doc(linePath).update({
        'assignment.units.u0.p2': true,
        'assignment.by.u0.p2': 'admin',
      });
      final repo = FirestoreSessionRepository(
        firestore: firestore,
        uid: () => 'owner',
        shareCodeFactory: () => 'X',
      );

      await repo.setUnitConsumer(
        linePath,
        unit: 0,
        participantId: 'p3',
        selected: true,
      );

      final assignment = await asignacion();
      // La asignación anterior sigue intacta, con su firma.
      expect((assignment['units'] as Map)['u0'], {'p2': true, 'p3': true});
      expect((assignment['by'] as Map)['u0'], {'p2': 'admin', 'p3': 'owner'});
    });

    // Mientras la asignación existe conserva su procedencia; cuando deja de
    // existir, la procedencia se va con ella. Una firma huérfana no explica
    // nada y las reglas rechazan la escritura entera, así que retirar el
    // consumo que asignó OTRA persona tiene que llevarse también su firma.
    test('retirar el consumo se lleva su firma y no toca la ajena', () async {
      await sembrar();
      await firestore.doc(linePath).update({
        'assignment.units.u0.p2': true,
        'assignment.by.u0.p2': 'admin',
        'assignment.units.u0.p3': true,
        'assignment.by.u0.p3': 'admin',
      });
      final repo = FirestoreSessionRepository(
        firestore: firestore,
        uid: () => 'p2-device',
        shareCodeFactory: () => 'X',
      );

      await repo.setUnitConsumer(
        linePath,
        unit: 0,
        participantId: 'p2',
        selected: false,
      );

      final assignment = await asignacion();
      expect((assignment['units'] as Map)['u0'], {'p3': true});
      expect((assignment['by'] as Map)['u0'], {'p3': 'admin'});
    });
  });
}
