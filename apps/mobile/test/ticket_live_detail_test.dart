// BUG-CP-05: el detalle del ticket tiene que LEER en vivo, no solo escribir.
//
// En hardware, «He terminado» persistía bien pero el banner seguía diciendo
// «Aún estáis eligiendo» durante minutos: el detalle se alimentaba de una
// lectura puntual del ticket por derecho histórico (A11d), y recompute
// escribe ese derecho para TODO participante económico, dueño incluido. Las
// pruebas de A19 montaban `TicketDetailScreen` con un `SessionTicket` hecho a
// mano y comprobaban el documento con `.get()`: la escritura, nunca la vuelta
// a la pantalla. Estas pruebas recorren la ruta real (`TicketRoute`) por el
// camino del derecho y exigen que cada cambio llegue SIN reabrir la pantalla.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue, Timestamp;
import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/application/session_providers.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/data/session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_detail_screen.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_navigation.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

const _ticketPath = 'sessions/s1/accounts/a1/tickets/t1';
const _key = (sid: 's1', tid: 't1');

FirebaseException _denegado() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

/// Repositorio real con las Rules de un ex-miembro simuladas en el único
/// punto que importa aquí: no puede LISTAR las cuentas de la sesión, así que
/// solo llega al ticket por su derecho. fake_cloud_firestore no aplica Rules
/// y, sin esto, el repliegue por cuentas taparía cualquier fallo del derecho.
class _SinListarCuentas extends FirestoreSessionRepository {
  _SinListarCuentas(FakeFirebaseFirestore fake, String uid)
    : super(
        firestore: fake,
        uid: () => uid,
        shareCodeFactory: () => 'TEST-CODE-1234567890',
      );

  @override
  Stream<List<SessionAccount>> watchAccounts(String sessionId) =>
      Stream.error(_denegado());
}

/// Como [_SinListarCuentas], pero el ticket lo sirve la prueba: permite
/// cortar el permiso a mitad de vida del listener.
class _TicketControlado extends _SinListarCuentas {
  _TicketControlado(super.fake, super.uid, this.ticket);

  final StreamController<SessionTicket?> ticket;

  @override
  Stream<SessionTicket?> watchTicket(
    String sessionId,
    String accountId,
    String ticketId,
  ) => ticket.stream;
}

/// Gasto bajo el protocolo A19 con Edgar (dueño, p1) y Alba (p2) pendientes.
Future<FakeFirebaseFirestore> _seed({
  bool protocolo = true,
  String? derechoPara = 'owner',
}) async {
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
  await fake.doc('sessions/s1/accounts/a1').set({
    'name': 'Cena',
    'order': 0,
    'totals': <String, Object?>{},
  });
  await fake.doc(_ticketPath).set({
    'kind': 'manual',
    'grandTotal': 400,
    'paidByParticipantId': 'p1',
    'merchant': {'name': 'Bar Manolo'},
    if (protocolo) 'pickingModelVersion': 1,
    if (protocolo)
      'picking': {
        'open': {'p1': true, 'p2': true},
      },
  });
  await fake.doc('$_ticketPath/lines/l1').set({
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
  if (derechoPara != null) await _derecho(fake, derechoPara);
  return fake;
}

/// Todo el mundo ha terminado. Clave a clave, como `finishPicking`:
/// fake_cloud_firestore FUSIONA un mapa vacío en vez de sustituirlo.
Future<void> _nadiePendiente(FakeFirebaseFirestore fake) =>
    fake.doc(_ticketPath).update({
      'picking.open.p1': FieldValue.delete(),
      'picking.open.p2': FieldValue.delete(),
    });

/// Lo que recompute escribe para cada participante económico (A11d).
Future<void> _derecho(FakeFirebaseFirestore fake, String uid) =>
    fake.doc('sessions/s1/ticketEntitlements/t1_$uid').set({
      'uid': uid,
      'ticketId': 't1',
      'accountId': 'a1',
      'participantNames': {'p1': 'Edgar', 'p2': 'Alba'},
      'schemaVersion': 1,
    });

Future<void> _pump(
  WidgetTester tester,
  FakeFirebaseFirestore fake, {
  String uid = 'owner',
  SessionRepository? repository,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: loggedInOverrides(
        firestore: fake,
        uid: uid,
        sessionRepository: repository,
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

/// El estado del detalle montado. Si la pantalla se desmontara y volviera
/// a montar (esqueleto de por medio), sería OTRO objeto.
State _detalle(WidgetTester tester) =>
    tester.state(find.byType(TicketDetailScreen));

Future<void> _cerrar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('BUG-CP-05: el dueño con derecho histórico ve el reparto en vivo', () {
    testWidgets('«He terminado» y «Terminar por» cierran el reparto en '
        'pantalla, sin salir y volver a entrar', (tester) async {
      final fake = await _seed();
      await _pump(tester, fake);
      final detalle = _detalle(tester);

      expect(find.text('Aún estáis eligiendo'), findsOneWidget);
      expect(find.textContaining('Falta Edgar, Alba'), findsOneWidget);

      await tester.tap(find.text('He terminado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Falta Alba'), findsOneWidget);
      expect(find.textContaining('Edgar, Alba'), findsNothing);

      // A10: el dueño cierra por Alba, que no puede pulsar.
      await tester.tap(find.text('Terminar por Alba'));
      await tester.pumpAndSettle();
      expect(find.text('Reparto cerrado'), findsOneWidget);
      expect(find.text('Aún estáis eligiendo'), findsNothing);

      // La MISMA pantalla: ni se reabrió ni pasó por un esqueleto.
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });

    testWidgets('la reapertura desde otro dispositivo también llega', (
      tester,
    ) async {
      final fake = await _seed();
      await _nadiePendiente(fake);
      await _pump(tester, fake);
      final detalle = _detalle(tester);
      expect(find.text('Reparto cerrado'), findsOneWidget);

      // Alba vuelve a tocar su consumo en la web: recompute/Rules la
      // devuelven a «eligiendo».
      await fake.doc(_ticketPath).update({'picking.open.p2': true});
      await tester.pumpAndSettle();
      expect(find.text('Aún estáis eligiendo'), findsOneWidget);
      expect(find.textContaining('Falta Alba'), findsOneWidget);
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });

    testWidgets('el resto del ticket tampoco se congela: una corrección '
        '(A11c) cambia comercio e importe en pantalla', (tester) async {
      final fake = await _seed();
      await _pump(tester, fake);
      final detalle = _detalle(tester);
      expect(find.text('Bar Manolo'), findsWidgets);

      await FirestoreSessionRepository(
        firestore: fake,
        uid: () => 'owner',
        shareCodeFactory: () => 'TEST-CODE-1234567890',
      ).correctTicketHeader(
        _ticketPath,
        merchantName: 'Bar Pepe',
        grandTotal: const Money(650),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bar Pepe'), findsWidgets);
      expect(find.text('Bar Manolo'), findsNothing);
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });

    testWidgets('si recompute escribe el derecho con la pantalla abierta, el '
        'detalle no se desmonta y sigue en vivo', (tester) async {
      // Gasto recién creado: todavía sin derecho, se llega por las cuentas.
      final fake = await _seed(derechoPara: null);
      await _pump(tester, fake);
      final detalle = _detalle(tester);
      expect(find.text('Aún estáis eligiendo'), findsOneWidget);

      await _derecho(fake, 'owner');
      await tester.pumpAndSettle();
      expect(_detalle(tester), same(detalle));

      await _nadiePendiente(fake);
      await tester.pumpAndSettle();
      expect(find.text('Reparto cerrado'), findsOneWidget);
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });
  });

  group('BUG-CP-05: el camino normal y el legacy siguen vivos', () {
    testWidgets('sin derecho y sin protocolo (ticket antiguo) se llega por las '
        'cuentas y los cambios también llegan', (tester) async {
      final fake = await _seed(protocolo: false, derechoPara: null);
      await _pump(tester, fake);
      final detalle = _detalle(tester);
      expect(find.text('Bar Manolo'), findsWidgets);
      // Un gasto anterior a A19 no habla de terminar el reparto.
      expect(find.text('Aún estáis eligiendo'), findsNothing);

      await fake.doc(_ticketPath).update({'merchant.name': 'Bar Pepe'});
      await tester.pumpAndSettle();
      expect(find.text('Bar Pepe'), findsWidgets);
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });
  });

  group('BUG-CP-07: firma de corrección del ticket', () {
    testWidgets('un ticket legacy sin firma no inventa una corrección', (
      tester,
    ) async {
      final fake = await _seed();
      await _pump(tester, fake);

      expect(find.textContaining('Corregido por'), findsNothing);
      await _cerrar(tester);
    });

    testWidgets('mapea la firma y la muestra en vivo sin reabrir el detalle', (
      tester,
    ) async {
      final fake = await _seed();
      await _pump(tester, fake);
      final detalle = _detalle(tester);

      expect(find.textContaining('Corregido por'), findsNothing);
      await fake.doc('profiles/uid-alba').set({
        'displayName': 'Alba García',
        'username': 'alba',
      });
      await fake.doc(_ticketPath).update({
        'lastEditedByUid': 'uid-alba',
        'lastEditedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 29)),
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Corregido por Alba García'), findsOneWidget);
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });

    testWidgets('si el perfil del actor ya no existe, usa el fallback público', (
      tester,
    ) async {
      final fake = await _seed();
      await fake.doc(_ticketPath).update({
        'lastEditedByUid': 'uid-eliminado',
        'lastEditedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 29)),
      });
      await _pump(tester, fake);

      expect(find.textContaining('Corregido por Alguien'), findsOneWidget);
      await _cerrar(tester);
    });
  });

  group('BUG-CP-05: derecho histórico, autoridad y revocación', () {
    testWidgets('un ex-miembro llega SOLO por su derecho y ve los cambios en '
        'vivo', (tester) async {
      final fake = await _seed(derechoPara: 'uid-jorge');
      await _pump(
        tester,
        fake,
        uid: 'uid-jorge',
        repository: _SinListarCuentas(fake, 'uid-jorge'),
      );
      final detalle = _detalle(tester);
      expect(find.text('Bar Manolo'), findsWidgets);

      await fake.doc(_ticketPath).update({'merchant.name': 'Bar Pepe'});
      await tester.pumpAndSettle();
      expect(find.text('Bar Pepe'), findsWidgets);
      expect(_detalle(tester), same(detalle));
      await _cerrar(tester);
    });

    testWidgets('sin derecho ni acceso normal no se gana nada, ni siquiera '
        'cuando el ticket cambia después', (tester) async {
      final fake = await _seed();
      await _pump(
        tester,
        fake,
        uid: 'uid-ajeno',
        repository: _SinListarCuentas(fake, 'uid-ajeno'),
      );
      expect(find.text('Este gasto ya no está disponible'), findsOneWidget);
      expect(find.byType(TicketDetailScreen), findsNothing);

      await _nadiePendiente(fake);
      await tester.pumpAndSettle();
      expect(find.byType(TicketDetailScreen), findsNothing);
      expect(find.text('Bar Manolo'), findsNothing);
      await _cerrar(tester);
    });

    testWidgets('si el gasto se elimina (A2) con la pantalla abierta, se dice '
        'que ya no está en vez de enseñar el último estado', (tester) async {
      final fake = await _seed(derechoPara: 'uid-jorge');
      await _pump(
        tester,
        fake,
        uid: 'uid-jorge',
        repository: _SinListarCuentas(fake, 'uid-jorge'),
      );
      expect(find.byType(TicketDetailScreen), findsOneWidget);

      // A2 borra el ticket y `cleanup` limpia el derecho con él.
      await fake.doc(_ticketPath).delete();
      await fake.doc('sessions/s1/ticketEntitlements/t1_uid-jorge').delete();
      await tester.pumpAndSettle();
      expect(find.byType(TicketDetailScreen), findsNothing);
      expect(find.text('Este gasto ya no está disponible'), findsOneWidget);
      await _cerrar(tester);
    });

    testWidgets('si se pierde el permiso de lectura a mitad de vida, no se '
        'sigue pintando el ticket congelado', (tester) async {
      final fake = await _seed(derechoPara: 'uid-jorge');
      final ticket = StreamController<SessionTicket?>();
      // Sin esperar: `close()` no completa si nadie llegó a escuchar, y eso
      // colgaría el runner justo en el caso que esta prueba debe detectar.
      addTearDown(() => unawaited(ticket.close()));
      await _pump(
        tester,
        fake,
        uid: 'uid-jorge',
        repository: _TicketControlado(fake, 'uid-jorge', ticket),
      );
      ticket.add(
        const SessionTicket(
          id: 't1',
          path: _ticketPath,
          merchantName: 'Bar Manolo',
          grandTotal: Money(400),
          paidBy: 'p1',
          kind: 'manual',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TicketDetailScreen), findsOneWidget);

      // Riverpod conserva el último dato tras un error: si la ruta lo
      // mirase antes que el error, esto seguiría enseñando «Bar Manolo».
      ticket.addError(_denegado());
      await tester.pumpAndSettle();
      expect(find.byType(TicketDetailScreen), findsNothing);
      expect(find.text('Este gasto ya no está disponible'), findsOneWidget);
      await _cerrar(tester);
    });
  });

  group('BUG-CP-05: historicTicketProvider es un stream', () {
    test(
      'emite el ticket inicial y cada cambio posterior sin recrearse',
      () async {
        final fake = await _seed();
        final container = ProviderContainer(
          overrides: loggedInOverrides(firestore: fake),
        );
        addTearDown(container.dispose);

        final emitidos = <Set<String>>[];
        container.listen(historicTicketProvider(_key), (_, next) {
          final ticket = next.value?.ticket;
          if (ticket != null) emitidos.add(ticket.pickingOpen);
        }, fireImmediately: true);

        await container.read(historicTicketProvider(_key).future);
        await fake.doc(_ticketPath).update({
          'picking.open.p1': FieldValue.delete(),
        });
        await pumpEventQueue();
        await _nadiePendiente(fake);
        await pumpEventQueue();

        expect(emitidos.first, {'p1', 'p2'});
        expect(emitidos, contains(equals({'p2'})));
        expect(emitidos.last, isEmpty);
        expect(emitidos, hasLength(greaterThanOrEqualTo(3)));
      },
    );

    test('perder el derecho deja de resolver el ticket por esa vía', () async {
      final fake = await _seed(derechoPara: 'uid-jorge');
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: fake, uid: 'uid-jorge'),
      );
      addTearDown(container.dispose);
      final sub = container.listen(historicTicketProvider(_key), (_, _) {});
      addTearDown(sub.close);

      expect(
        (await container.read(historicTicketProvider(_key).future))?.ticket.id,
        't1',
      );
      await fake.doc('sessions/s1/ticketEntitlements/t1_uid-jorge').delete();
      await pumpEventQueue();
      expect(await container.read(historicTicketProvider(_key).future), isNull);
    });
  });
}
