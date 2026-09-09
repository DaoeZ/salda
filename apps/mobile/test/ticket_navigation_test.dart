import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/activity/domain/activity_models.dart';
import 'package:salda_mobile/features/activity/presentation/activity_tile.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_navigation.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// El ticket se veía en el espacio pero no se abría. Estas pruebas van sobre
/// las superficies REALES —no sobre helpers— y comprueban que todas llegan
/// al mismo detalle con el identificador correcto.
void main() {
  const yo = 'owner';
  late FakeFirebaseFirestore firestore;
  late List<String> rutas;
  late GoRouter router;
  late ProviderContainer contenedor;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    rutas = [];
    resetTicketNavigationDebounce();
  });

  /// Sesión con UN ticket dentro de [spaceId]. Devuelve (sessionId, ticketId).
  Future<(String, String)> seedTicket(
    String spaceId, {
    String merchant = 'BAR CONTINENTAL',
  }) async {
    await firestore.doc('sessions/s1').set({
      'ownerUid': yo,
      'kind': 'single',
      'status': 'open',
      'splitModeDefault': 'byItem',
      'currency': 'EUR',
      'spaceId': spaceId,
      'name': 'Cena',
      'totals': {'grandTotal': 3000},
      'balances': {},
    });
    await firestore.doc('sessions/s1/participants/p1').set({
      'name': 'Edgar',
      'isOwner': true,
      'order': 0,
      'active': true,
      'claimedByDevice': yo,
    });
    await firestore.doc('sessions/s1/accounts/a1').set({
      'name': 'Cena',
      'totals': {},
    });
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
      'kind': 'manual',
      'grandTotal': 3000,
      'paidByParticipantId': 'p1',
      'merchant': {'name': merchant},
      'date': '2026-07-20',
      'spaceId': spaceId,
    });
    return ('s1', 't1');
  }

  Future<void> seedRelacionV2() async {
    await firestore.doc('spaces/rel2').set({
      'name': 'Pedro',
      'ownerUid': yo,
      'kind': 'relationship',
      'relationshipUids': [yo, 'uid-pedro'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/rel2/members/$yo').set({'uid': yo});
    await firestore.doc('spaces/rel2/members/uid-pedro').set({
      'uid': 'uid-pedro',
    });
    await firestore.doc('profiles/uid-pedro').set({'displayName': 'Pedro'});
    await firestore.doc('profiles/$yo').set({'displayName': 'Edgar'});
  }

  Future<void> seedRelacionV3() async {
    await firestore.doc('spaces/rel3').set({
      'name': 'Pablo',
      'ownerUid': yo,
      'kind': 'relationship',
      'relationshipUids': [yo],
      'relationshipManualId': 'm1',
      'status': 'active',
      'schemaVersion': 3,
    });
    await firestore.doc('spaces/rel3/members/$yo').set({'uid': yo});
    await firestore.doc('spaces/rel3/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Pablo',
      'linkedUid': null,
      'createdByUid': yo,
      'schemaVersion': 1,
    });
  }

  Future<void> seedGrupo() async {
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': yo,
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/g1/members/$yo').set({'uid': yo});
    await firestore.doc('spaces/g1/members/uid-ana').set({'uid': 'uid-ana'});
  }

  /// Monta [home] con un router real que registra cada ruta visitada. La
  /// pantalla de ticket se sustituye por un marcador para que la prueba mida
  /// NAVEGACIÓN, no el detalle (que ya tiene sus propias pruebas).
  Future<void> pump(WidgetTester tester, Widget home, {String uid = yo}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore, uid: uid),
    );
    contenedor = container;
    addTearDown(container.dispose);
    router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => home),
        GoRoute(
          path: '/home/session/:sid/ticket/:tid',
          builder: (_, state) {
            rutas.add(state.uri.path);
            return Scaffold(
              appBar: AppBar(title: const Text('detalle-ticket')),
              body: Text(
                '${state.pathParameters['sid']}/${state.pathParameters['tid']}',
              ),
            );
          },
        ),
        GoRoute(
          path: '/home/session/:sid',
          builder: (_, state) {
            rutas.add(state.uri.path);
            return const Scaffold(body: Text('detalle-sesion'));
          },
        ),
        GoRoute(
          path: '/home/spaces/:sid',
          builder: (_, state) {
            rutas.add(state.uri.path);
            return const Scaffold(body: Text('detalle-espacio'));
          },
        ),
        GoRoute(
          path: '/home/economy',
          builder: (_, state) {
            rutas.add(state.uri.path);
            return const Scaffold(body: Text('economia'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// Pulsa el ticket listado en el detalle del espacio.
  Future<void> pulsarTicket(WidgetTester tester, String merchant) async {
    final fila = find.widgetWithText(ListTile, merchant);
    await tester.ensureVisible(fila);
    await tester.pumpAndSettle();
    await tester.tap(fila);
    await tester.pumpAndSettle();
  }

  group('tickets del espacio', () {
    testWidgets('relación v2: abre el detalle del ticket', (tester) async {
      await seedRelacionV2();
      await seedTicket('rel2');
      await pump(tester, const SpaceDetailScreen(spaceId: 'rel2'));
      await pulsarTicket(tester, 'BAR CONTINENTAL');
      expect(rutas, ['/home/session/s1/ticket/t1']);
      expect(find.text('s1/t1'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('la SEGUNDA cuenta abre el mismo ticket', (tester) async {
      await seedRelacionV2();
      await seedTicket('rel2');
      await pump(
        tester,
        const SpaceDetailScreen(spaceId: 'rel2'),
        uid: 'uid-pedro',
      );
      await pulsarTicket(tester, 'BAR CONTINENTAL');
      // Mismo destino: no depende de quién mire ni del orden de los UID.
      expect(rutas, ['/home/session/s1/ticket/t1']);
      await cerrar(tester);
    });

    testWidgets('relación v3: el propietario abre el ticket', (tester) async {
      await seedRelacionV3();
      await seedTicket('rel3');
      await pump(tester, const SpaceDetailScreen(spaceId: 'rel3'));
      await pulsarTicket(tester, 'BAR CONTINENTAL');
      expect(rutas, ['/home/session/s1/ticket/t1']);
      await cerrar(tester);
    });

    testWidgets('grupo: abre el ticket igual que una relación', (tester) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(tester, const SpaceDetailScreen(spaceId: 'g1'));
      await pulsarTicket(tester, 'GURUGU');
      // El tipo de espacio no cambia el destino.
      expect(rutas, ['/home/session/s1/ticket/t1']);
      await cerrar(tester);
    });

    testWidgets('doble pulsación no abre dos pantallas', (tester) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(tester, const SpaceDetailScreen(spaceId: 'g1'));
      final fila = find.widgetWithText(ListTile, 'GURUGU');
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(fila);
      await tester.tap(fila, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(rutas.length, 1);
      await cerrar(tester);
    });

    testWidgets('la fila llega al objetivo táctil mínimo', (tester) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(tester, const SpaceDetailScreen(spaceId: 'g1'));
      final alto = tester
          .getSize(find.widgetWithText(ListTile, 'GURUGU'))
          .height;
      expect(alto, greaterThanOrEqualTo(48));
      await cerrar(tester);
    });

    testWidgets('volver deja el espacio en pie', (tester) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(tester, const SpaceDetailScreen(spaceId: 'g1'));
      await pulsarTicket(tester, 'GURUGU');
      expect(find.text('detalle-ticket'), findsOneWidget);
      // `push` apila: al volver se recupera la MISMA pantalla del espacio.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('GURUGU'), findsOneWidget);
      expect(find.byType(SpaceDetailScreen), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('un cambio en el ticket se refleja al volver', (tester) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(tester, const SpaceDetailScreen(spaceId: 'g1'));
      await pulsarTicket(tester, 'GURUGU');
      // Mientras se está dentro, el ticket cambia de importe.
      await firestore.doc('sessions/s1/accounts/a1/tickets/t1').update({
        'grandTotal': 4500,
      });
      router.pop();
      await tester.pumpAndSettle();
      // fake_cloud_firestore no re-emite un collectionGroup cuando cambia un
      // documento ya existente (Firestore real sí), así que se fuerza la
      // re-suscripción igual que en `spaces_screen_test`. Lo que se prueba
      // es que la lista pinta el estado ACTUAL del almacén sin reiniciar la
      // app ni reconstruir el espacio.
      contenedor.invalidate(spaceTicketsProvider('g1'));
      await tester.pumpAndSettle();
      // Aparece en la fila del ticket y también en «Gastado aquí»: lo que
      // importa es que la portada refleje el importe nuevo.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'GURUGU'),
          matching: find.textContaining('45,00'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SpaceDetailScreen), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('actividad', () {
    ActivityEvent evento({String? sessionId, String? ticketId}) =>
        ActivityEvent(
          id: 'e1',
          type: ActivityType.ticketCreated,
          actorUid: yo,
          spaceId: 'g1',
          sessionId: sessionId,
          ticketId: ticketId,
          ticketName: 'GURUGU',
          at: DateTime(2026, 7, 20),
        );

    testWidgets('un evento de ticket abre ESE ticket', (tester) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(
        tester,
        Scaffold(
          body: ActivityTile(
            event: evento(sessionId: 's1', ticketId: 't1'),
          ),
        ),
      );
      await tester.tap(find.byType(ActivityTile));
      await tester.pumpAndSettle();
      expect(rutas, ['/home/session/s1/ticket/t1']);
      await cerrar(tester);
    });

    testWidgets('evento LEGACY sin ticketId no abre un ticket erróneo', (
      tester,
    ) async {
      await seedGrupo();
      await seedTicket('g1', merchant: 'GURUGU');
      await pump(
        tester,
        Scaffold(
          body: ActivityTile(event: evento(sessionId: 's1')),
        ),
      );
      await tester.tap(find.byType(ActivityTile));
      await tester.pumpAndSettle();
      // Cae al espacio, que es lo único que el evento identifica de verdad.
      // NUNCA se adivina un ticket por su nombre o su importe.
      expect(rutas, ['/home/spaces/g1']);
      await cerrar(tester);
    });

    testWidgets('un evento de PAGO sigue yendo a economía', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: ActivityTile(
            event: ActivityEvent(
              id: 'e2',
              type: ActivityType.paymentConfirmed,
              actorUid: yo,
              spaceId: 'g1',
              paymentId: 'pay1',
              at: DateTime(2026, 7, 20),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ActivityTile));
      await tester.pumpAndSettle();
      expect(rutas, ['/home/economy']);
      await cerrar(tester);
    });
  });

  group('contrato de la ruta', () {
    test('la ruta se construye desde identificadores', () {
      expect(
        ticketRoute(sessionId: 's1', ticketId: 't1'),
        '/home/session/s1/ticket/t1',
      );
    });

    testWidgets('sin identificadores no se navega a ninguna parte', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openTicket(context, sessionId: '', ticketId: 't1'),
              child: const Text('vacío'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('vacío'));
      await tester.pumpAndSettle();
      expect(rutas, isEmpty);
      await cerrar(tester);
    });
  });
}
