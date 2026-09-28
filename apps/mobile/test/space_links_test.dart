import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';

/// Enlaces de grupo (Sprint 4, ADR-035).
///
/// Aquí se verifica el CONTRATO del repositorio: qué documentos escribe y
/// qué decide. Que un extraño no pueda saltárselo lo demuestran las Rules
/// contra el emulador (`rules.test.mjs`, bloque "enlaces de grupo").
void main() {
  late FakeFirebaseFirestore firestore;

  SpacesRepository accountRepo(String uid) => SpacesRepository(
    firestore: firestore,
    uid: () => uid,
    isFullAccount: () => true,
  );

  SpacesRepository guestRepo(String uid, {String? name}) => SpacesRepository(
    firestore: firestore,
    uid: () => uid,
    isFullAccount: () => false,
    guestDisplayName: name == null ? null : () => name,
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<String> newGroup() => accountRepo('owner').createSpace('Cena viernes');

  group('creación y ciclo de vida del enlace', () {
    test('el token es opaco y el documento nace activo', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');

      // 128 bits en base64url sin padding: 22 caracteres URL-safe.
      expect(link.token.length, 22);
      expect(link.token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(link.usableAt(DateTime.now().toUtc()), isTrue);
      expect(link.expiresAt, isNull); // sin caducidad por defecto

      final raw = (await firestore.doc('spaceLinks/${link.token}').get())
          .data()!;
      expect(raw['spaceId'], spaceId);
      expect(raw['status'], 'active');
      expect(raw['createdByUid'], 'owner');
      expect(raw['schemaVersion'], 1);
      // El enlace NO contiene identidades: compartirlo no revela quién está
      // dentro (restricción que ADR-034 exige revisar al cerrar el sprint).
      expect(raw.containsKey('memberUids'), isFalse);
      expect(raw.containsKey('ownerUid'), isFalse);
    });

    test('revocar deja el enlace inservible para la vista previa', () async {
      final spaceId = await newGroup();
      final repo = accountRepo('owner');
      final link = await repo.createJoinLink(spaceId, 'Cena viernes');

      expect(await repo.previewJoinLink(link.token), isNotNull);
      await repo.revokeJoinLink(link.token);
      expect(await repo.previewJoinLink(link.token), isNull);
    });

    test('rotar mata el anterior y entrega un token DISTINTO', () async {
      final spaceId = await newGroup();
      final repo = accountRepo('owner');
      final first = await repo.createJoinLink(spaceId, 'Cena viernes');
      final second = await repo.rotateJoinLink(
        spaceId,
        'Cena viernes',
        previousToken: first.token,
      );

      expect(second.token, isNot(first.token));
      expect(await repo.previewJoinLink(first.token), isNull);
      expect(await repo.previewJoinLink(second.token), isNotNull);
      // El viejo se conserva revocado: queda demostrablemente muerto en vez
      // de reciclarse.
      final old = (await firestore.doc('spaceLinks/${first.token}').get())
          .data()!;
      expect(old['status'], 'revoked');
    });

    test('solo hay un enlace vivo tras rotar', () async {
      final spaceId = await newGroup();
      final repo = accountRepo('owner');
      final first = await repo.createJoinLink(spaceId, 'Cena viernes');
      final second = await repo.rotateJoinLink(
        spaceId,
        'Cena viernes',
        previousToken: first.token,
      );

      final active = await repo.watchActiveJoinLink(spaceId).first;
      expect(active!.token, second.token);
    });
  });

  group('caducidad', () {
    test('sin caducidad es el valor por defecto', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');

      final raw = (await firestore.doc('spaceLinks/${link.token}').get())
          .data()!;
      expect(raw.containsKey('expiresAt'), isFalse);
    });

    test('una caducidad elegida se guarda en el futuro', () async {
      final spaceId = await newGroup();
      final link = await accountRepo('owner').createJoinLink(
        spaceId,
        'Cena viernes',
        lifetime: JoinLinkLifetime.sevenDays,
      );

      expect(link.expiresAt, isNotNull);
      expect(link.expiresAt!.isAfter(DateTime.now().toUtc()), isTrue);
      final raw = (await firestore.doc('spaceLinks/${link.token}').get())
          .data()!;
      expect(raw['expiresAt'], isA<Timestamp>());
    });

    test('un enlace caducado no admite a nadie ni se previsualiza', () async {
      final spaceId = await newGroup();
      final owner = accountRepo('owner');
      final link = await owner.createJoinLink(spaceId, 'Cena viernes');
      // Se retrasa la caducidad al pasado sin tocar `status`: caducar y
      // revocar son cosas distintas y ambas deben cerrar la puerta.
      await firestore.doc('spaceLinks/${link.token}').update({
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
      });

      expect(await owner.previewJoinLink(link.token), isNull);
      expect(
        await accountRepo('ana').joinWithLink(link.token),
        JoinLinkOutcome.invalid,
      );
      expect(
        (await firestore.doc('spaces/$spaceId/members/ana').get()).exists,
        isFalse,
      );
    });

    test('el enlace caducado desaparece de la vista del propietario', () async {
      final spaceId = await newGroup();
      final owner = accountRepo('owner');
      final link = await owner.createJoinLink(spaceId, 'Cena viernes');
      await firestore.doc('spaceLinks/${link.token}').update({
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
      });

      expect(await owner.watchActiveJoinLink(spaceId).first, isNull);
    });

    test('usableAt distingue caducado de revocado', () {
      final now = DateTime.utc(2026, 7, 25, 12);
      final vigente = SpaceJoinLink(
        token: 't',
        spaceId: 's',
        spaceName: 'G',
        createdByUid: 'o',
        revoked: false,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final caducado = SpaceJoinLink(
        token: 't',
        spaceId: 's',
        spaceName: 'G',
        createdByUid: 'o',
        revoked: false,
        expiresAt: now.subtract(const Duration(hours: 1)),
      );
      final revocado = SpaceJoinLink(
        token: 't',
        spaceId: 's',
        spaceName: 'G',
        createdByUid: 'o',
        revoked: true,
      );
      final eterno = SpaceJoinLink(
        token: 't',
        spaceId: 's',
        spaceName: 'G',
        createdByUid: 'o',
        revoked: false,
      );

      expect(vigente.usableAt(now), isTrue);
      expect(caducado.usableAt(now), isFalse);
      expect(caducado.isExpiredAt(now), isTrue);
      expect(revocado.usableAt(now), isFalse);
      expect(revocado.isExpiredAt(now), isFalse); // revocado ≠ caducado
      expect(eterno.usableAt(now), isTrue);
    });
  });

  group('canje del enlace', () {
    test('una CUENTA entra con prueba de conocimiento y membresía', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');

      final outcome = await accountRepo('ana').joinWithLink(link.token);
      expect(outcome, JoinLinkOutcome.joined);

      final member = (await firestore.doc('spaces/$spaceId/members/ana').get())
          .data()!;
      expect(member['uid'], 'ana');
      // Una cuenta NO congela nombre: se lee en vivo de su perfil público.
      expect(member.containsKey('displayName'), isFalse);
      expect(member.containsKey('kind'), isFalse);

      final grant =
          (await firestore.doc('spaces/$spaceId/joinGrants/ana').get()).data()!;
      expect(grant['token'], link.token);
      expect(grant['uid'], 'ana');
    });

    test('un INVITADO entra igual y congela su nombre visible', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');

      final outcome = await guestRepo(
        'guest-1',
        name: 'Alba',
      ).joinWithLink(link.token);
      expect(outcome, JoinLinkOutcome.joined);

      final member =
          (await firestore.doc('spaces/$spaceId/members/guest-1').get())
              .data()!;
      expect(member['kind'], 'guest');
      expect(member['displayName'], 'Alba');
    });

    test('un anónimo SIN nombre visible no entra todavía', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');

      final outcome = await guestRepo('guest-2').joinWithLink(link.token);
      expect(outcome, JoinLinkOutcome.needsGuestName);
      expect(
        (await firestore.doc('spaces/$spaceId/members/guest-2').get()).exists,
        isFalse,
      );
    });

    test('un enlace revocado ya no admite a nadie', () async {
      final spaceId = await newGroup();
      final owner = accountRepo('owner');
      final link = await owner.createJoinLink(spaceId, 'Cena viernes');
      await owner.revokeJoinLink(link.token);

      expect(
        await accountRepo('ana').joinWithLink(link.token),
        JoinLinkOutcome.invalid,
      );
      expect(
        (await firestore.doc('spaces/$spaceId/members/ana').get()).exists,
        isFalse,
      );
    });

    test('un token inventado no abre nada', () async {
      await newGroup();
      expect(
        await accountRepo('ana').joinWithLink('token-que-no-existe'),
        JoinLinkOutcome.invalid,
      );
    });

    test('pulsar dos veces no duplica ni falla', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');
      final ana = accountRepo('ana');

      expect(await ana.joinWithLink(link.token), JoinLinkOutcome.joined);
      expect(await ana.joinWithLink(link.token), JoinLinkOutcome.alreadyMember);
    });

    test('acepta la URL completa pegada desde WhatsApp', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');
      final url = SpacesRepository.joinUrlFor('salda-dev.web.app', link.token);

      expect(url, endsWith('/g/${link.token}'));
      final preview = await accountRepo('ana').previewJoinLink('  $url  ');
      expect(preview!.spaceId, spaceId);
    });
  });

  group('un invitado puede llegar a sus grupos', () {
    test('watchMySpaces ya no exige cuenta', () async {
      final spaceId = await newGroup();
      final link = await accountRepo(
        'owner',
      ).createJoinLink(spaceId, 'Cena viernes');
      final guest = guestRepo('guest-1', name: 'Alba');
      await guest.joinWithLink(link.token);

      final spaces = await guest.watchMySpaces().first;
      expect(spaces.single.id, spaceId);
    });

    test('un anónimo sin identidad de invitado sigue fuera', () async {
      await newGroup();
      expect(
        () => guestRepo('guest-2').watchMySpaces(),
        throwsA(
          isA<SpaceFailure>().having(
            (failure) => failure.code,
            'code',
            SpaceFailureCode.accountRequired,
          ),
        ),
      );
    });
  });
}
