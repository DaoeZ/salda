import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/core/routing/incoming_link.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/sessions/data/ticket_links_repository.dart';
import 'package:salda_mobile/features/sessions/domain/ticket_link_models.dart';
import 'package:salda_mobile/features/sessions/presentation/join_ticket_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// BUG 2: un enlace de ticket dirigido a una persona permitía elegir y
/// reclamar a cualquier otro participante del ticket.
///
/// El enlace publicaba la lista completa de MANUAL y la pantalla la pintaba
/// como «¿Quién eres?». Rules solo comprobaba «ese pid participa en el
/// ticket», así que consentía la elección: un enlace hecho para Pedro servía
/// para quedarse con la identidad económica de Ana.
///
/// Estas pruebas recorren la pantalla REAL con el repositorio REAL. La otra
/// mitad —que un cliente modificado tampoco pueda— vive en `rules.test.mjs`,
/// que es donde se puede saltar la interfaz.
void main() {
  late FakeFirebaseFirestore firestore;

  // El enlace se genera para PEDRO. Ana y Luis existen en el ticket a
  // propósito: son justo los que antes se podían reclamar con este enlace.
  const pedro = EligibleManual(pid: 'p6', manualId: 'm2', displayName: 'Pedro');

  TicketLinksRepository repoFor(String uid) =>
      TicketLinksRepository(firestore: firestore, uid: () => uid);

  /// Ticket con UNA cuenta (el anfitrión) y TRES participantes manuales,
  /// cada uno con su línea. Es el caso del enunciado.
  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('sessions/s1/participants/p1').set({
      'name': 'Edgar',
      'isOwner': true,
      'order': 0,
      'claimedByDevice': 'owner',
    });
    for (final (pid, nombre, manualId, orden) in [
      ('p5', 'Ana', 'm1', 1),
      ('p6', 'Pedro', 'm2', 2),
      ('p7', 'Luis', 'm3', 3),
    ]) {
      await firestore.doc('sessions/s1/participants/$pid').set({
        'name': nombre,
        'isOwner': false,
        'order': orden,
        'claimedByDevice': '',
        'manualId': manualId,
        'active': true,
      });
    }
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
      'kind': 'manual',
      'grandTotal': 3000,
      'paidByParticipantId': 'p1',
      'merchant': {'name': 'Mercadona'},
    });
    // Una línea por persona: sirve para comprobar que vincular no mueve nada.
    for (final (lid, nombre, pid, precio) in [
      ('l1', 'Ensalada', 'p5', 1000),
      ('l2', 'Pizza', 'p6', 1200),
      ('l3', 'Postre', 'p7', 800),
    ]) {
      await firestore.doc('sessions/s1/accounts/a1/tickets/t1/lines/$lid').set({
        'name': nombre,
        'order': 0,
        'quantityMilli': 1000,
        'totalPrice': precio,
        'unitIds': ['u0'],
        'assignment': {
          'type': 'units',
          'schemaVersion': 2,
          'units': {
            'u0': {pid: true},
          },
        },
      });
    }
    for (final pid in ['p1', 'p5', 'p6', 'p7']) {
      await firestore.doc('sessions/s1/ticketParticipants/t1_$pid').set({
        'ticketId': 't1',
        'pid': pid,
        'schemaVersion': 1,
        if (pid == 'p1') 'claimedByDevice': 'owner',
      });
    }
    await firestore.doc('sessions/s1/ticketParticipantProjections/t1').set({
      'ticketId': 't1',
      'ready': true,
      'fingerprint': 'p1,p5,p6,p7',
      'schemaVersion': 1,
    });
  });

  Future<TicketJoinLink> enlacePara(EligibleManual target) =>
      repoFor('owner').createLink(
        sessionId: 's1',
        accountId: 'a1',
        ticketId: 't1',
        merchantName: 'Mercadona',
        target: target,
      );

  /// Navegación REAL: la pantalla termina llamando a `context.go`, así que
  /// sin router no se puede comprobar a dónde acaba llevando el enlace.
  late String ruta;

  Future<void> abrir(WidgetTester tester, String token, {String uid = 'ana'}) {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/t/$token',
      routes: [
        GoRoute(
          path: '/t/:token',
          builder: (_, state) =>
              JoinTicketScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/ticket/:token',
          builder: (_, state) =>
              Scaffold(body: Text('TICKET ${state.pathParameters['token']}')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    addTearDown(router.dispose);
    router.routerDelegate.addListener(() {
      ruta = router.state.uri.toString();
    });
    ruta = '/t/$token';
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...loggedInOverrides(firestore: firestore, uid: uid),
          ticketLinksRepositoryProvider.overrideWithValue(repoFor(uid)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// Foto del estado economico del ticket, para comprobar que vincular no
  /// mueve un cent.
  Future<Map<String, Object?>> retratoEconomico() async {
    final lines = await firestore
        .collection('sessions/s1/accounts/a1/tickets/t1/lines')
        .get();
    final participants = await firestore
        .collection('sessions/s1/participants')
        .get();
    return {
      'lineas': {
        for (final d in lines.docs) d.id: d.data()['assignment'].toString(),
      },
      'importes': {for (final d in lines.docs) d.id: d.data()['totalPrice']},
      'participantes': {
        for (final d in participants.docs)
          d.id:
              '${d.data()['manualId']}|${d.data()['claimedByDevice']}|'
              '${d.data()['linkedUid']}',
      },
      'entradas':
          (await firestore.collection('economicEntries').get()).docs.length,
      'pagos':
          (await firestore.collection('economicPayments').get()).docs.length,
      'total': (await firestore.doc('sessions/s1/accounts/a1/tickets/t1').get())
          .data()!['grandTotal'],
    };
  }

  group('el enlace representa a UNA persona', () {
    testWidgets('no aparece ningun selector de participantes', (tester) async {
      final link = await enlacePara(pedro);
      await abrir(tester, link.token);
      await tester.pumpAndSettle();

      // El destinatario, y solo el.
      expect(find.textContaining('Pedro'), findsWidgets);
      // Los otros dos NO se nombran: ni como opcion ni como dato.
      expect(find.textContaining('Ana'), findsNothing);
      expect(find.textContaining('Luis'), findsNothing);
      // Y no hay lista de la que elegir: una confirmacion y una salida.
      expect(find.byType(FilledButton), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('confirmar identifica al destinatario y abre el ticket', (
      tester,
    ) async {
      final link = await enlacePara(pedro);
      await abrir(tester, link.token);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final access = await repoFor('ana').myAccess('s1', 't1');
      expect(access!.manualId, 'm2');
      expect(access.pid, 'p6');
      expect(access.token, link.token);
      // Y termina en la ruta canónica del ticket, con SU token.
      expect(ruta, '/ticket/${link.token}');
      expect(find.text('TICKET ${link.token}'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('«no soy esa persona» no identifica a nadie', (tester) async {
      final link = await enlacePara(pedro);
      await abrir(tester, link.token);
      await tester.pumpAndSettle();
      // La salida existe: un enlace reenviado por error no obliga a mentir.
      expect(find.text('No soy esa persona'), findsOneWidget);
      expect(await repoFor('ana').myAccess('s1', 't1'), isNull);
      await cerrar(tester);
    });

    testWidgets('nunca se enseña el identificador interno', (tester) async {
      final link = await enlacePara(pedro);
      await abrir(tester, link.token);
      await tester.pumpAndSettle();
      expect(find.textContaining('manual:'), findsNothing);
      expect(find.textContaining('m2'), findsNothing);
      expect(find.textContaining('p6'), findsNothing);
      await cerrar(tester);
    });
  });

  group('tokens invalidos', () {
    testWidgets('token inexistente: mensaje, no pantalla rota', (tester) async {
      await abrir(tester, 'NOEXISTEAAAAAAAAAAAAAA');
      await tester.pumpAndSettle();
      expect(find.textContaining('Este enlace ya no sirve'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await cerrar(tester);
    });

    testWidgets('token manipulado no resuelve a otro enlace', (tester) async {
      final link = await enlacePara(pedro);
      // Un carácter cambiado: el id del documento ES el secreto.
      final roto = 'X${link.token.substring(1)}';
      await abrir(tester, roto);
      await tester.pumpAndSettle();
      expect(find.textContaining('Este enlace ya no sirve'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('enlace revocado: cerrado', (tester) async {
      final link = await enlacePara(pedro);
      await repoFor('owner').revokeLink(link.token);
      await abrir(tester, link.token);
      await tester.pumpAndSettle();
      expect(find.textContaining('Este enlace ya no sirve'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('participante eliminado del ticket: no se ofrece nada', (
      tester,
    ) async {
      final link = await enlacePara(pedro);
      // recompute rehace el reparto y Pedro deja de participar.
      await firestore.doc('sessions/s1/ticketParticipants/t1_p6').delete();
      await firestore.doc('sessions/s1/participants/p6').delete();
      await abrir(tester, link.token);
      await tester.pumpAndSettle();
      // El enlace sigue existiendo, pero confirmarlo lo rechazaria Rules.
      // Aqui basta con que no aparezca ningun OTRO participante ofrecido.
      expect(find.textContaining('Ana'), findsNothing);
      expect(find.textContaining('Luis'), findsNothing);
      await cerrar(tester);
    });
  });

  group('idempotencia y segunda cuenta', () {
    testWidgets('reabrir con la MISMA cuenta entra directo, sin repetir', (
      tester,
    ) async {
      final link = await enlacePara(pedro);
      await repoFor('ana').identifyAsTarget(link);
      final antes = await retratoEconomico();

      await abrir(tester, link.token);
      await tester.pumpAndSettle();
      // Ya identificado: no se vuelve a preguntar, se entra directo.
      expect(find.textContaining('¿Eres'), findsNothing);
      expect(ruta, '/ticket/${link.token}');
      // Y no se ha duplicado nada.
      expect(
        (await firestore.collection('sessions/s1/ticketClaims').get()).docs,
        hasLength(1),
      );
      expect(await retratoEconomico(), antes);
      await cerrar(tester);
    });

    testWidgets('OTRA cuenta con el mismo enlace: error controlado', (
      tester,
    ) async {
      final link = await enlacePara(pedro);
      await repoFor('ana').identifyAsTarget(link);

      await abrir(tester, link.token, uid: 'bruno');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('Otra persona ya usó'), findsOneWidget);
      // No se le ofrece otra identidad como premio de consolación.
      expect(find.textContaining('Ana'), findsNothing);
      expect(find.textContaining('Luis'), findsNothing);
      expect(await repoFor('bruno').myAccess('s1', 't1'), isNull);
      await cerrar(tester);
    });
  });

  group('la economía no se mueve', () {
    test(
      'identificarse conserva líneas, importes, actores e histórico',
      () async {
        final link = await enlacePara(pedro);
        final antes = await retratoEconomico();

        await repoFor('ana').identifyAsTarget(link);

        final despues = await retratoEconomico();
        expect(despues, antes);
        // Explícitamente: el actor de Pedro sigue siendo su manual.
        final p6 = (await firestore.doc('sessions/s1/participants/p6').get())
            .data()!;
        expect(p6['manualId'], 'm2');
        expect(p6['claimedByDevice'], '');
        expect(p6.containsKey('linkedUid'), isFalse);
      },
    );

    test('soltar la identificación tampoco mueve nada', () async {
      final link = await enlacePara(pedro);
      final antes = await retratoEconomico();
      final ana = repoFor('ana');
      await ana.identifyAsTarget(link);
      await ana.release(link, (await ana.myAccess('s1', 't1'))!);
      expect(await retratoEconomico(), antes);
    });
  });

  group('lo que NO cambia', () {
    test('la navegación canónica del ticket sigue igual', () {
      // El enlace no lleva sessionId ni ticketId: manipular la URL no cambia
      // de ticket. La ruta canónica se alcanza tras validar el token.
      final link = IncomingLinkParser.parse('https://salda-dev.web.app/t/Tk1')!;
      expect(link, isA<ManualParticipantClaimLink>());
      expect(link.route, '/t/Tk1');
      expect(link.route.contains('session'), isFalse);
    });

    test('los enlaces de GRUPO siguen funcionando', () {
      final link = IncomingLinkParser.parse('https://salda-dev.web.app/g/Tk1');
      expect(link, isA<GroupInvitationLink>());
      expect(link!.token, 'Tk1');
    });

    test('pegar el enlace a mano sigue funcionando', () async {
      final link = await enlacePara(pedro);
      final url = TicketLinksRepository.linkUrlFor(
        'salda-dev.web.app',
        link.token,
      );
      final resuelto = await repoFor('ana').preview('  $url  ');
      expect(resuelto!.target!.manualId, 'm2');
    });
  });
}
