import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/domain/ticket_correction.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_navigation.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// A11c: corregir el gasto de otro.
///
/// La autoridad la aplican las Rules (group_ticket_correction.test.mjs) y el
/// dinero lo rehace la function (ticketCorrection.test.ts). Aquí se fija lo
/// que le toca a la app: a quién se le ofrece corregir, que el reparto no se
/// destruya en silencio y que la escritura deje firma.
class _AdminSessionRepository extends FirestoreSessionRepository {
  _AdminSessionRepository({
    required super.firestore,
    required super.uid,
    required super.shareCodeFactory,
  });

  // Quien administra el grupo NO es dueño de la sesión: ese documento le
  // está vedado porque guarda el shareCode (A11b).
  @override
  Stream<SessionDetail?> watchSession(String sessionId) => Stream.error(
    Exception('permission-denied: sessions/$sessionId'),
    StackTrace.current,
  );
}

const _ticketPath = 'sessions/s1/accounts/a1/tickets/t1';

Future<FakeFirebaseFirestore> _seed({String roleOfViewer = 'admin'}) async {
  final fake = FakeFirebaseFirestore();
  await fake.doc('spaces/gr1').set({
    'name': 'Piso',
    'ownerUid': 'uid-alba',
    'kind': 'group',
    'status': 'active',
    'schemaVersion': 2,
  });
  await fake.doc('spaces/gr1/members/uid-alba').set({'uid': 'uid-alba'});
  await fake.doc('spaces/gr1/members/owner').set({
    'uid': 'owner',
    if (roleOfViewer.isNotEmpty) 'role': roleOfViewer,
  });
  await fake.doc('sessions/s1').set({
    'ownerUid': 'uid-alba',
    'kind': 'single',
    'name': 'Compra',
    'status': 'open',
    'splitModeDefault': 'byItem',
    'shareCode': 'TEST-CODE-1234567890',
    'currency': 'EUR',
    'contextModelVersion': 1,
    'spaceId': 'gr1',
  });
  await fake.doc('sessions/s1/participants/p1').set({
    'name': 'Alba',
    'isOwner': true,
    'order': 0,
    'claimedByDevice': 'uid-alba',
  });
  await fake.doc('sessions/s1/participants/p2').set({
    'name': 'Jorge',
    'isOwner': false,
    'order': 1,
    'claimedByDevice': 'owner',
  });
  await fake.doc('sessions/s1/accounts/a1').set({'name': 'Súper', 'order': 0});
  await fake.doc(_ticketPath).set({
    'kind': 'manual',
    'grandTotal': 1596,
    'paidByParticipantId': 'p1',
    'merchant': {'name': 'Familycas'},
    'spaceId': 'gr1',
    'contextModelVersion': 1,
    'splitModeOverride': 'byItem',
  });
  // «2 × Coca-Cola»: la unidad 1 es de Alba y la 2 de Jorge.
  await fake.doc('$_ticketPath/lines/l1').set({
    'name': 'Coca-Cola',
    'order': 0,
    'quantityMilli': 2000,
    'unitPrice': 150,
    'totalPrice': 300,
    'unitIds': ['u0', 'u1'],
    'assignment': {
      'type': 'units',
      'schemaVersion': 2,
      'units': {
        'u0': {'p1': true},
        'u1': {'p2': true},
      },
    },
  });
  await fake.doc('$_ticketPath/lines/l2').set({
    'name': 'Patatas',
    'order': 1,
    'quantityMilli': 1000,
    'totalPrice': 1296,
    'unitIds': ['u0'],
    'assignment': {
      'type': 'units',
      'schemaVersion': 2,
      'units': {
        'u0': {'p2': true},
      },
    },
  });
  return fake;
}

Future<void> _pump(
  WidgetTester tester,
  FakeFirebaseFirestore fake, {
  bool asAdmin = true,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  resetTicketNavigationDebounce();
  await tester.pumpWidget(
    ProviderScope(
      overrides: loggedInOverrides(
        firestore: fake,
        sessionRepository: asAdmin
            ? _AdminSessionRepository(
                firestore: fake,
                uid: () => 'owner',
                shareCodeFactory: () => 'X',
              )
            : null,
      ),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TicketRoute(sessionId: 's1', ticketId: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<TicketLine> _line(FakeFirebaseFirestore fake, String id) async {
  final repo = FirestoreSessionRepository(
    firestore: fake,
    uid: () => 'owner',
    shareCodeFactory: () => 'X',
  );
  final lines = await repo.watchTicketLines(_ticketPath).first;
  return lines.firstWhere((l) => l.id == id);
}

void main() {
  group('qué destruye una corrección', () {
    late FakeFirebaseFirestore fake;
    setUp(() async => fake = await _seed());

    test(
      'bajar de 2 a 1 unidad deja sin consumo a quien tenía la segunda',
      () async {
        final impacto = impactOfQuantityChange(await _line(fake, 'l1'), 1000);

        expect(impacto.isDestructive, isTrue);
        expect(impacto.affectedPids, ['p2']);
        expect(impacto.lostUnitsByPid['p2'], [1]);
        expect(impacto.removedUnitIds, ['u1']);
      },
    );

    test(
      'subir la cantidad no destruye nada ni inventa consumidores',
      () async {
        final line = await _line(fake, 'l1');
        final impacto = impactOfQuantityChange(line, 4000);

        expect(impacto.isDestructive, isFalse);
        expect(impacto.removedUnitIds, isEmpty);
        expect(unitIdsFor(4000), ['u0', 'u1', 'u2', 'u3']);
      },
    );

    test('la poda nombra la unidad que se va, no la que se queda', () async {
      // Se borra u1 y NADA más: u0 ni se menciona, así que nadie puede
      // acabar en una unidad que no eligió.
      final impacto = impactOfQuantityChange(await _line(fake, 'l1'), 1000);
      expect(impacto.removedUnitIds, ['u1']);
      expect(unitIdsFor(1000), ['u0']);
    });

    test('retirar el producto se lleva todas sus asignaciones', () async {
      final impacto = impactOfRemovingLine(await _line(fake, 'l1'));

      expect(impacto.affectedPids, ['p1', 'p2']);
    });
  });

  group('escritura de la corrección', () {
    late FakeFirebaseFirestore fake;
    late FirestoreSessionRepository repo;

    setUp(() async {
      fake = await _seed();
      repo = FirestoreSessionRepository(
        firestore: fake,
        uid: () => 'owner',
        shareCodeFactory: () => 'X',
      );
    });

    test(
      'corregir el precio deja el total intacto y firma la corrección',
      () async {
        await repo.correctLine(
          '$_ticketPath/lines/l1',
          name: 'Coca-Cola',
          quantityMilli: 2000,
          totalPrice: const Money(400),
        );

        final line = (await fake.doc('$_ticketPath/lines/l1').get()).data()!;
        final ticket = (await fake.doc(_ticketPath).get()).data()!;
        expect(line['totalPrice'], 400);
        // El reparto no se toca: cada unidad sigue con su dueño.
        expect((line['assignment'] as Map)['units'], {
          'u0': {'p1': true},
          'u1': {'p2': true},
        });
        // El precio unitario deja de constar en vez de quedar falso.
        expect(line.containsKey('unitPrice'), isFalse);
        // Y lo importante: el ticket ponía 15,96 € y SIGUE poniendo 15,96 €.
        // Corregir un producto mal leído no inventa dinero pagado; solo cambia
        // con qué pesos se reparte ese dinero.
        expect(ticket['grandTotal'], 1596);
        expect(ticket['lastEditedByUid'], 'owner');
        expect(ticket['lastEditedAt'], isNotNull);
      },
    );

    test('reducir la cantidad poda solo la unidad perdida', () async {
      final line = await _line(fake, 'l1');
      await repo.correctLine(
        line.path,
        name: line.name,
        quantityMilli: 1000,
        totalPrice: const Money(150),
        removedUnitIds: impactOfQuantityChange(line, 1000).removedUnitIds,
        unitIds: unitIdsFor(1000),
      );

      final after = (await fake.doc('$_ticketPath/lines/l1').get()).data()!;
      expect(after['unitIds'], ['u0']);
      expect((after['assignment'] as Map)['units'], {
        'u0': {'p1': true},
      });
      expect((await fake.doc(_ticketPath).get()).data()!['grandTotal'], 1596);
    });

    test('retirar un producto no devuelve dinero: el total sigue siendo el '
        'del ticket', () async {
      await repo.removeLine('$_ticketPath/lines/l2');

      expect((await fake.doc('$_ticketPath/lines/l2').get()).exists, isFalse);
      final ticket = (await fake.doc(_ticketPath).get()).data()!;
      expect(ticket['grandTotal'], 1596);
      expect(ticket['lastEditedByUid'], 'owner');
    });

    test(
      'el total SOLO cambia por la corrección explícita de la cabecera',
      () async {
        // El caso en que el ticket físico también estaba mal leído: se corrige
        // a conciencia, en su propia acción, y queda firmado.
        await repo.correctTicketHeader(
          _ticketPath,
          merchantName: 'Familycash',
          grandTotal: const Money(1650),
        );

        final ticket = (await fake.doc(_ticketPath).get()).data()!;
        expect(ticket['grandTotal'], 1650);
        expect(ticket['lastEditedByUid'], 'owner');
      },
    );

    test('corregir la cabecera cambia comercio y total, y firma', () async {
      await repo.correctTicketHeader(
        _ticketPath,
        merchantName: 'Familycash',
        date: '18/08/2026',
        grandTotal: const Money(1700),
      );

      final ticket = (await fake.doc(_ticketPath).get()).data()!;
      expect((ticket['merchant'] as Map)['name'], 'Familycash');
      expect(ticket['date'], '18/08/2026');
      expect(ticket['grandTotal'], 1700);
      expect(ticket['lastEditedByUid'], 'owner');
      // Ni el espacio ni el pagador se mueven al corregir.
      expect(ticket['spaceId'], 'gr1');
      expect(ticket['paidByParticipantId'], 'p1');
    });
  });

  group('interfaz', () {
    testWidgets('el administrador del grupo puede corregir el gasto ajeno', (
      tester,
    ) async {
      await _pump(tester, await _seed());
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('un miembro normal no ve la corrección', (tester) async {
      await _pump(tester, await _seed(roleOfViewer: ''));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      // Pero sigue auditando el ticket (A11b).
      expect(find.text('Coca-Cola'), findsOneWidget);
    });

    testWidgets('en modo corrección la fila corrige, no selecciona consumo', (
      tester,
    ) async {
      final fake = await _seed();
      await _pump(tester, fake);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Ni chips de unidad ni selección: el toque abre la corrección.
      expect(find.byType(FilterChip), findsNothing);
      await tester.tap(find.text('Coca-Cola'));
      await tester.pumpAndSettle();
      expect(find.text('Editar producto'), findsOneWidget);
    });

    testWidgets('al corregir se ven los dos importes: suma de productos y '
        'total del ticket', (tester) async {
      final fake = await _seed();
      await _pump(tester, fake);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // 3,00 + 12,96 = 15,96 → cuadra con el total del ticket.
      expect(find.textContaining('Suma de productos: 15,96'), findsOneWidget);
      // A15: el estado verde dice lo que de verdad comprueba —la aritmética—
      // y ya no se presenta como un certificado del ticket entero.
      expect(find.text('El total cuadra'), findsOneWidget);
    });

    testWidgets('si la corrección descuadra el ticket, se dice; el total no '
        'se toca solo', (tester) async {
      final fake = await _seed();
      await _pump(tester, fake);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coca-Cola'));
      await tester.pumpAndSettle();

      // 3,00 € → 3,50 €: el ticket físico sigue diciendo 15,96 €.
      await tester.enterText(find.widgetWithText(TextField, 'Importe'), '3,50');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect((await fake.doc(_ticketPath).get()).data()!['grandTotal'], 1596);
      expect(find.textContaining('Descuadre de 0,50'), findsOneWidget);
      expect(find.textContaining('Suma de productos: 16,46'), findsOneWidget);
    });

    testWidgets('corregir el total a conciencia vuelve a cuadrar el ticket', (
      tester,
    ) async {
      final fake = await _seed();
      // Producto ya corregido: la suma de líneas es 16,46 y el total 15,96.
      await fake.doc('$_ticketPath/lines/l1').update({'totalPrice': 350});
      await _pump(tester, fake);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('Descuadre de 0,50'), findsOneWidget);

      await tester.tap(find.text('Corregir el ticket'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Total del ticket'),
        '16,46',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      final ticket = (await fake.doc(_ticketPath).get()).data()!;
      expect(ticket['grandTotal'], 1646);
      // Y esa corrección del total queda firmada como cualquier otra.
      expect(ticket['lastEditedByUid'], 'owner');
    });

    testWidgets('reducir la cantidad avisa de las asignaciones afectadas', (
      tester,
    ) async {
      final fake = await _seed();
      await _pump(tester, fake);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coca-Cola'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '1');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Se nombra a quien pierde su consumo, y nada se ha escrito todavía.
      expect(find.text('Se perderán asignaciones'), findsOneWidget);
      expect(find.textContaining('Jorge'), findsWidgets);
      expect(
        (await fake.doc('$_ticketPath/lines/l1').get())
            .data()!['quantityMilli'],
        2000,
      );

      // Cancelar (el del diálogo, encima de la hoja) no cambia nada.
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar').last);
      await tester.pumpAndSettle();
      expect(
        (await fake.doc('$_ticketPath/lines/l1').get())
            .data()!['quantityMilli'],
        2000,
      );
    });

    testWidgets('confirmar aplica la poda y solo la poda', (tester) async {
      final fake = await _seed();
      await _pump(tester, fake);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coca-Cola'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '1');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar').last);
      await tester.pumpAndSettle();

      final line = (await fake.doc('$_ticketPath/lines/l1').get()).data()!;
      expect(line['quantityMilli'], 1000);
      expect((line['assignment'] as Map)['units'], {
        'u0': {'p1': true},
      });
      // Y la firma queda en el ticket.
      expect(
        (await fake.doc(_ticketPath).get()).data()!['lastEditedByUid'],
        'owner',
      );
    });
  });
}
