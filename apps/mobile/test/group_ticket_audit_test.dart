import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_navigation.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// A11b: un miembro del grupo AUDITA el ticket de otro.
///
/// La autoridad la aplican Rules (backend/firestore/test/group_ticket_audit
/// y storage_receipt_access): `fake_cloud_firestore` no las evalúa. Lo que
/// se fija aquí es la otra mitad — que la pantalla muestre la evidencia
/// completa y NO ofrezca ni una acción que el auditor no pueda ejecutar.
///
/// El auditor se simula por donde de verdad se distingue: no puede leer
/// `sessions/{sid}` (ahí vive el shareCode), así que ese stream falla.
class _AuditorSessionRepository extends FirestoreSessionRepository {
  _AuditorSessionRepository({
    required super.firestore,
    required super.uid,
    required super.shareCodeFactory,
  });

  @override
  Stream<SessionDetail?> watchSession(String sessionId) => Stream.error(
    Exception('permission-denied: sessions/$sessionId'),
    StackTrace.current,
  );
}

const _ticketPath = 'sessions/s1/accounts/a1/tickets/t1';

Future<FakeFirebaseFirestore> _seed({String modo = 'byItem'}) async {
  final fake = FakeFirebaseFirestore();
  await fake.doc('spaces/gr1').set({
    'name': 'Piso',
    'ownerUid': 'uid-alba',
    'kind': 'group',
    'status': 'active',
    'schemaVersion': 2,
  });
  for (final uid in ['uid-alba', 'owner']) {
    await fake.doc('spaces/gr1/members/$uid').set({'uid': uid});
  }
  // La sesión la creó Alba dentro del grupo; quien mira es 'owner' (Jorge).
  await fake.doc('sessions/s1').set({
    'ownerUid': 'uid-alba',
    'kind': 'single',
    'name': 'Compra',
    'status': 'open',
    'splitModeDefault': modo,
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
    'grandTotal': 550,
    'paidByParticipantId': 'p1',
    'merchant': {'name': 'Familycash'},
    'spaceId': 'gr1',
    'contextModelVersion': 1,
    // Modo efectivo en el ticket: es lo único por lo que un miembro —que no
    // puede leer la sesión— sabe que el gasto se reparte por líneas.
    'splitModeOverride': modo,
  });
  // Consumida ENTERA por Alba: Jorge no participa y aun así debe verla.
  await fake.doc('$_ticketPath/lines/l1').set({
    'name': 'Coca-Cola',
    'order': 0,
    'quantityMilli': 1000,
    'unitPrice': 250,
    'totalPrice': 250,
    'unitIds': ['u0'],
    'assignment': {
      'type': 'units',
      'schemaVersion': 2,
      'units': {
        'u0': {'p1': true},
      },
    },
  });
  // Dos unidades sin reclamar: el creador las reparte con chips; el auditor
  // ve el mismo estado sin un solo control.
  await fake.doc('$_ticketPath/lines/l2').set({
    'name': 'Patatas',
    'order': 1,
    'quantityMilli': 2000,
    'unitPrice': 150,
    'totalPrice': 300,
    'unitIds': ['u0', 'u1'],
    'assignment': {
      'type': 'units',
      'schemaVersion': 2,
      'units': <String, Object?>{},
    },
  });
  return fake;
}

Future<void> _pump(
  WidgetTester tester,
  FakeFirebaseFirestore fake, {
  required bool auditor,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  resetTicketNavigationDebounce();
  await tester.pumpWidget(
    ProviderScope(
      overrides: loggedInOverrides(
        firestore: fake,
        sessionRepository: auditor
            ? _AuditorSessionRepository(
                firestore: fake,
                uid: () => 'owner',
                shareCodeFactory: () => 'X',
              )
            : null,
      ),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Por identificadores, como cualquier superficie del producto: el
        // auditor llega desde la lista de tickets del grupo, sin conocer la
        // cuenta en la que vive el ticket.
        home: const TicketRoute(sessionId: 's1', ticketId: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el auditor ve el ticket entero: productos, precios y reparto', (
    tester,
  ) async {
    await _pump(tester, await _seed(), auditor: true);

    expect(find.text('Familycash'), findsWidgets);
    expect(find.text('Coca-Cola'), findsOneWidget);
    expect(find.text('Patatas'), findsOneWidget);
    // Precio por línea y total del ticket.
    expect(find.textContaining('2,50'), findsWidgets);
    expect(find.textContaining('3,00'), findsWidgets);
    expect(find.textContaining('5,50'), findsWidgets);
    // Y de quién es cada unidad: sin los nombres el reparto es ilegible.
    expect(find.textContaining('Alba'), findsWidgets);
  });

  testWidgets('no se le ofrece ninguna acción de EDICIÓN del ticket ajeno', (
    tester,
  ) async {
    await _pump(tester, await _seed(), auditor: true);

    // Compartir por enlace y vincular a un espacio son del dueño.
    expect(find.byIcon(Icons.link), findsNothing);
    expect(find.byIcon(Icons.group_work), findsNothing);
    expect(find.byIcon(Icons.group_work_outlined), findsNothing);
    // Migrar la línea al modelo de unidades reescribe la asignación entera:
    // es edición, no selección.
    expect(find.text('Repartir por unidades'), findsNothing);
  });

  // El núcleo de la corrección: leer y elegir son autoridades distintas.
  testWidgets('pero SÍ puede elegir su propio consumo, y lo firma como él', (
    tester,
  ) async {
    final fake = await _seed();
    await _pump(tester, fake, auditor: true);

    // Coca-Cola: una unidad, se marca tocando la fila.
    await tester.tap(find.text('Coca-Cola'));
    await tester.pumpAndSettle();
    // Patatas: dos unidades, se marca por chip.
    await tester.tap(find.widgetWithText(FilterChip, '1'));
    await tester.pumpAndSettle();

    final coca = await fake.doc('$_ticketPath/lines/l1').get();
    final patatas = await fake.doc('$_ticketPath/lines/l2').get();
    final cocaUnits =
        (coca.data()!['assignment'] as Map)['units'] as Map<String, dynamic>;
    final patatasAssignment = patatas.data()!['assignment'] as Map;

    // Marca SU unidad, con SU participante, sin tocar la de Alba.
    expect((cocaUnits['u0'] as Map)['p2'], true);
    expect((cocaUnits['u0'] as Map)['p1'], true);
    expect((coca.data()!['assignment'] as Map)['lastEditorPid'], 'p2');
    expect(
      ((patatasAssignment['units'] as Map)['u0'] as Map)['p2'],
      true,
    );
    expect(patatasAssignment['lastEditorPid'], 'p2');
    // Y nada del dato fuente se ha movido.
    expect(coca.data()!['name'], 'Coca-Cola');
    expect(coca.data()!['totalPrice'], 250);
  });

  // Reparto GLOBAL: aquí las líneas no deciden nada. Antes la pantalla
  // rotulaba cada producto como «sin reclamar (para Alba)» —la lectura del
  // otro modo— y quien auditaba concluía que no le tocaba nada.
  testWidgets('en un ticket a medias se explica el reparto y su parte', (
    tester,
  ) async {
    final fake = await _seed(modo: 'equal');
    // 15,96 € a medias entre Alba y Jorge.
    await fake.doc(_ticketPath).update({'grandTotal': 1596});
    await fake.doc('$_ticketPath/lines/l2').update({'totalPrice': 1346});
    await _pump(tester, fake, auditor: true);

    expect(
      find.textContaining('se reparte a partes iguales entre 2 personas'),
      findsOneWidget,
    );
    expect(find.textContaining('Te corresponden 7,98'), findsOneWidget);
    // Sigue auditando la compra: productos y precios originales.
    expect(find.text('Coca-Cola'), findsOneWidget);
    expect(find.text('Patatas'), findsOneWidget);
    expect(find.textContaining('2,50'), findsWidgets);
    expect(find.textContaining('15,96'), findsWidgets);
    // Sin controles de selección y sin rótulos del otro modo de reparto.
    expect(find.byType(FilterChip), findsNothing);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .every((tile) => tile.onTap == null),
      isTrue,
    );
    expect(find.textContaining('sin reclamar'), findsNothing);
  });

  testWidgets('sin participante propio no hay nada que elegir', (tester) async {
    final fake = await _seed();
    // Jorge está en el grupo, pero el anfitrión no lo metió en ESTE gasto.
    await fake.doc('sessions/s1/participants/p2').update({
      'claimedByDevice': 'uid-nadie',
    });
    await _pump(tester, fake, auditor: true);

    expect(find.text('Coca-Cola'), findsOneWidget); // lo sigue auditando
    expect(find.byType(FilterChip), findsNothing);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .every((tile) => tile.onTap == null),
      isTrue,
    );
  });

  testWidgets('el dueño de la sesión conserva sus acciones y su selección', (
    tester,
  ) async {
    final fake = await _seed();
    // Mismo ticket, pero ahora quien mira es su creador.
    await fake.doc('sessions/s1').update({'ownerUid': 'owner'});
    await fake.doc('sessions/s1/participants/p1').update({
      'name': 'Edgar',
      'claimedByDevice': 'owner',
    });
    await fake.doc('sessions/s1/participants/p2').update({
      'claimedByDevice': 'uid-jorge',
    });
    await _pump(tester, fake, auditor: false);

    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('Coca-Cola'), findsOneWidget);
    // El creador sí elige lo que consumió (P2.1): chips en la línea de dos
    // unidades y fila pulsable en la de una.
    expect(
      tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .any((chip) => chip.onSelected != null),
      isTrue,
    );
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .any((tile) => tile.onTap != null),
      isTrue,
    );
  });
}
