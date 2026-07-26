import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/data/ticket_links_repository.dart';
import 'package:salda_mobile/features/sessions/domain/ticket_link_models.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart'
    show JoinLinkLifetime;

/// Enlaces de TICKET (Sprint 5, ADR-036) — contrato del repositorio.
///
/// Que un extraño no pueda saltarse nada de esto lo demuestran las Rules
/// contra el emulador (bloque «enlaces de ticket»); aquí se fija QUÉ escribe
/// la app y, sobre todo, qué NO toca.
void main() {
  late FakeFirebaseFirestore firestore;

  TicketLinksRepository repoFor(String uid) =>
      TicketLinksRepository(firestore: firestore, uid: () => uid);

  const marta = EligibleManual(pid: 'p5', manualId: 'm1', displayName: 'Marta');
  const luis = EligibleManual(pid: 'p6', manualId: 'm2', displayName: 'Luis');

  Future<TicketJoinLink> seedLink({
    JoinLinkLifetime lifetime = JoinLinkLifetime.never,
    List<EligibleManual> manuals = const [marta, luis],
  }) => repoFor('owner').createLink(
    sessionId: 's1',
    accountId: 'a1',
    ticketId: 't1',
    merchantName: 'Mercadona',
    manuals: manuals,
    lifetime: lifetime,
  );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    // Sesión con dos cuentas, un invitado y DOS manuales.
    await firestore.doc('sessions/s1/participants/p1').set({
      'name': 'Edgar',
      'isOwner': true,
      'claimedByDevice': 'owner',
    });
    await firestore.doc('sessions/s1/participants/p2').set({
      'name': 'Alba',
      'isOwner': false,
      'claimedByDevice': 'guest-1',
    });
    await firestore.doc('sessions/s1/participants/p5').set({
      'name': 'Marta',
      'isOwner': false,
      'claimedByDevice': '',
      'manualId': 'm1',
      'active': true,
    });
    await firestore.doc('sessions/s1/participants/p6').set({
      'name': 'Luis',
      'isOwner': false,
      'claimedByDevice': '',
      'manualId': 'm2',
      'active': true,
    });
    // Proyección AUTORITATIVA que escribe recompute (aquí sembrada a mano):
    // es la fuente que Rules consulta y la que la app usa para reconocer a
    // quien ya participa, en vez del array del enlace.
    for (final entry in [
      ('t1_p1', 'p1', 'owner'),
      ('t1_p2', 'p2', 'guest-1'),
      ('t1_p5', 'p5', ''),
      ('t1_p6', 'p6', ''),
    ]) {
      await firestore.doc('sessions/s1/ticketParticipants/${entry.$1}').set({
        'ticketId': 't1',
        'pid': entry.$2,
        'schemaVersion': 1,
        if (entry.$3.isNotEmpty) 'claimedByDevice': entry.$3,
      });
    }
    // Señal de proyección PREPARADA (recompute la escribe en el mismo batch
    // que las entradas). Sin ella no se puede crear el enlace.
    await firestore.doc('sessions/s1/ticketParticipantProjections/t1').set({
      'ticketId': 't1',
      'ready': true,
      'fingerprint': 'p1,p2,p5,p6',
      'schemaVersion': 1,
    });
  });

  group('creación y alcance', () {
    test('el enlace apunta a UN ticket y solo publica el comercio', () async {
      final link = await seedLink();
      final raw = (await firestore.doc('ticketLinks/${link.token}').get())
          .data()!;

      expect(link.token.length, 22);
      expect(raw['sessionId'], 's1');
      expect(raw['ticketId'], 't1');
      expect(raw['merchantName'], 'Mercadona');
      // Nada económico viaja en el enlace: ni importe, ni líneas.
      expect(raw.containsKey('grandTotal'), isFalse);
      expect(raw.containsKey('lines'), isFalse);
      expect(link.ticketPath, 'sessions/s1/accounts/a1/tickets/t1');
    });

    test('solo se denormalizan los MANUAL: ni cuentas ni invitados', () async {
      final link = await seedLink();
      final names = link.manuals.map((m) => m.displayName).toList();

      expect(names, ['Marta', 'Luis']);
      // Edgar (cuenta) y Alba (invitada) NO aparecen, aunque participen.
      expect(names, isNot(contains('Edgar')));
      expect(names, isNot(contains('Alba')));
      // Y no se filtra cuánta gente hay en total.
      expect(link.manuals.length, 2);
    });

    test('revocado y caducado se presentan igual que inexistente', () async {
      final owner = repoFor('owner');
      final vivo = await seedLink();
      expect(await owner.preview(vivo.token), isNotNull);

      await owner.revokeLink(vivo.token);
      expect(await owner.preview(vivo.token), isNull);

      final caduco = await seedLink();
      await firestore.doc('ticketLinks/${caduco.token}').update({
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
      });
      expect(await owner.preview(caduco.token), isNull);
      expect(await owner.preview('inventado'), isNull);
    });

    test('acepta la URL completa pegada', () async {
      final link = await seedLink();
      final url = TicketLinksRepository.linkUrlFor(
        'salda-dev.web.app',
        link.token,
      );
      expect(url, endsWith('/t/${link.token}'));
      expect((await repoFor('ana').preview(url))!.ticketId, 't1');
    });
  });

  group('proyección preparada', () {
    test('no se crea un enlace que fuera a fallar por consistencia', () async {
      // Ticket recién creado: recompute todavía no ha proyectado nada.
      await expectLater(
        repoFor('owner').createLink(
          sessionId: 's1',
          accountId: 'a1',
          ticketId: 't9',
          merchantName: 'Recien',
          manuals: const [marta],
          // Sin espera: el timeout corto solo acota, no garantiza nada.
        ),
        throwsA(isA<TicketLinkNotReady>()),
      );
      expect((await firestore.collection('ticketLinks').get()).docs, isEmpty);
    });

    test('en cuanto la señal aparece, el enlace se crea', () async {
      expect(await repoFor('owner').isProjectionReady('s1', 't1'), isTrue);
      expect(await repoFor('owner').isProjectionReady('s1', 't9'), isFalse);
      final link = await seedLink();
      expect(link.ticketId, 't1');
    });

    test(
      'la espera es por EVENTO: se resuelve al escribirse la señal',
      () async {
        final pending = repoFor('owner').awaitProjectionReady('s1', 't9');
        // Nadie duerme: la escritura es la que desbloquea.
        await firestore.doc('sessions/s1/ticketParticipantProjections/t9').set({
          'ticketId': 't9',
          'ready': true,
          'schemaVersion': 1,
        });
        expect(await pending, isTrue);
      },
    );
  });

  group('identificación temporal', () {
    test('un participante YA conocido entra sin elegir nada', () async {
      final link = await seedLink();
      final guest = repoFor('guest-1');
      // 'guest-1' reclamó p2, que participa en t1 según la proyección.
      final pid = await guest.knownParticipantPid(link);
      expect(pid, 'p2');
      await guest.enterAsKnownParticipant(link, pid!);

      final access = await guest.myAccess('s1', 't1');
      expect(access!.pid, 'p2');
      // Entra representando a alguien, pero SIN suplantar a un manual.
      expect(access.identifiesAManual, isFalse);
    });

    test('un desconocido no es participante y tendrá que elegir', () async {
      final link = await seedLink();
      expect(await repoFor('ana').knownParticipantPid(link), isNull);
    });

    test('abrir un 2o ticket NO invalida el acceso al 1o', () async {
      final link = await seedLink();
      final ana = repoFor('ana');
      await ana.identifyAsManual(link, marta);
      // La clave incluye el ticketId, así que ambos accesos coexisten.
      expect((await ana.myAccess('s1', 't1'))!.manualId, 'm1');
      expect(await ana.myAccess('s1', 't2'), isNull);
    });

    test('elegir un MANUAL escribe prueba y cerrojo', () async {
      final link = await seedLink();
      final outcome = await repoFor('ana').identifyAsManual(link, marta);
      expect(outcome, TicketLinkOutcome.opened);

      final access =
          (await firestore.doc('sessions/s1/ticketAccess/t1_ana').get())
              .data()!;
      expect(access['manualId'], 'm1');
      expect(access['pid'], 'p5');
      expect(access['token'], link.token);
      expect(access['ticketId'], 't1');

      final claim =
          (await firestore.doc('sessions/s1/ticketClaims/t1_m1').get()).data()!;
      expect(claim['uid'], 'ana');
    });

    test('otro dispositivo NO se queda con el mismo manual', () async {
      final link = await seedLink();
      await repoFor('ana').identifyAsManual(link, marta);

      expect(
        await repoFor('bruno').identifyAsManual(link, marta),
        TicketLinkOutcome.manualTaken,
      );
      // Pero sí puede coger otro libre.
      expect(
        await repoFor('bruno').identifyAsManual(link, luis),
        TicketLinkOutcome.opened,
      );
    });

    test('reabrir el enlace en el mismo dispositivo es idempotente', () async {
      final link = await seedLink();
      final ana = repoFor('ana');
      expect(await ana.identifyAsManual(link, marta), TicketLinkOutcome.opened);
      expect(await ana.identifyAsManual(link, marta), TicketLinkOutcome.opened);
    });

    test(
      'soltar la identificación borra prueba y cerrojo, y NADA más',
      () async {
        final link = await seedLink();
        final ana = repoFor('ana');
        await ana.identifyAsManual(link, marta);
        await ana.release(link, (await ana.myAccess('s1', 't1'))!);

        expect(
          (await firestore.doc('sessions/s1/ticketAccess/t1_ana').get()).exists,
          isFalse,
        );
        expect(
          (await firestore.doc('sessions/s1/ticketClaims/t1_m1').get()).exists,
          isFalse,
        );
        // El participante MANUAL sigue exactamente igual.
        final p5 = (await firestore.doc('sessions/s1/participants/p5').get())
            .data()!;
        expect(p5['manualId'], 'm1');
        expect(p5['claimedByDevice'], '');
      },
    );
  });

  group('el modelo económico NO se toca (P5 intacto)', () {
    test('identificarse no escribe claimedByDevice ni linkedUid', () async {
      final link = await seedLink();
      await repoFor('ana').identifyAsManual(link, marta);

      final p5 = (await firestore.doc('sessions/s1/participants/p5').get())
          .data()!;
      // ESTA es la línea roja: `claimedByDevice` tiene precedencia sobre
      // `manualId` en recompute, así que escribirlo aquí habría migrado el
      // actor económico a un UID — una vinculación definitiva por la puerta
      // de atrás, que es justo lo que decide el Sprint 6.
      expect(p5['claimedByDevice'], '');
      expect(p5.containsKey('linkedUid'), isFalse);
      // El actor sigue siendo el manual.
      expect(p5['manualId'], 'm1');
    });

    test(
      'el flujo no escribe en economicEntries ni economicPayments',
      () async {
        final link = await seedLink();
        await repoFor('ana').identifyAsManual(link, marta);

        expect(
          (await firestore.collection('economicEntries').get()).docs,
          isEmpty,
        );
        expect(
          (await firestore.collection('economicPayments').get()).docs,
          isEmpty,
        );
        // Ni en los agregados de la sesión.
        final session = (await firestore.doc('sessions/s1').get()).data();
        expect(session?['balances'], isNull);
      },
    );
  });
}
