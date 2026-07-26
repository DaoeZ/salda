import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/domain/space_title.dart';

/// BUG-5: el título de una relación es LA OTRA persona, y eso depende de
/// quién mire. Aquí se prueba la regla en Dart puro; los widget tests
/// comprueban que las pantallas la usan.
void main() {
  const edgar = 'uid-edgar';
  const pedro = 'uid-pedro';

  /// Relación v2 entre dos cuentas. El nombre persistido es el legado que
  /// nunca debe salir a pantalla.
  Space v2({
    String owner = edgar,
    List<String> uids = const [edgar, pedro],
    String name = 'Edgar · Pedro',
  }) => Space(
    id: 'relationship_x~y',
    name: name,
    ownerUid: owner,
    status: SpaceStatus.active,
    kind: SpaceKind.relationship,
    relationshipUids: uids,
  );

  Space v3({String manualId = 'm1', String name = 'Pablo'}) => Space(
    id: 'gen1',
    name: name,
    ownerUid: edgar,
    status: SpaceStatus.active,
    kind: SpaceKind.relationship,
    relationshipUids: const [edgar],
    relationshipManualId: manualId,
  );

  const grupo = Space(
    id: 'g1',
    name: 'Piso',
    ownerUid: edgar,
    status: SpaceStatus.active,
  );

  SpaceTitleResolution resolve(
    Space space,
    String uid, {
    List<ManualParticipant> manuals = const [],
    bool manualsLoading = false,
    bool profileLoading = false,
    String? displayName,
    String? username,
  }) => resolveSpaceTitle(
    space: space,
    currentUid: uid,
    manuals: manuals,
    manualsLoading: manualsLoading,
    profileLoading: profileLoading,
    otherDisplayName: displayName,
    otherUsername: username,
  );

  group('relación v2 (dos cuentas)', () {
    test('Edgar ve a Pedro', () {
      final r = resolve(v2(), edgar, displayName: 'Pedro');
      expect(r.source, SpaceTitleSource.person);
      expect(r.person, 'Pedro');
    });

    test('Pedro ve a Edgar en el MISMO espacio', () {
      // Mismo documento, distinto lector: por eso no puede persistirse.
      expect(spaceTitleProfileUid(space: v2(), currentUid: pedro, manuals: []),
          edgar);
      expect(spaceTitleProfileUid(space: v2(), currentUid: edgar, manuals: []),
          pedro);
      final r = resolve(v2(), pedro, displayName: 'Edgar');
      expect(r.person, 'Edgar');
    });

    test('el orden lexicográfico de los UID no decide el nombre', () {
      // El id canónico ordena la pareja; el título NO depende de ese orden.
      const alto = 'zzz-uid';
      const bajo = 'aaa-uid';
      for (final orden in [
        [bajo, alto],
        [alto, bajo],
      ]) {
        expect(
          spaceTitleProfileUid(
            space: v2(owner: bajo, uids: orden),
            currentUid: bajo,
            manuals: [],
          ),
          alto,
          reason: 'orden $orden',
        );
      }
    });

    test('nunca sale el nombre persistido ni el propio', () {
      final r = resolve(v2(), edgar, displayName: 'Pedro');
      expect(r.person, isNot(contains('·')));
      expect(r.person, isNot('Edgar'));
    });

    test('sin displayName cae al username, con @', () {
      final r = resolve(v2(), edgar, displayName: '', username: 'pedro27');
      expect(r.person, '@pedro27');
    });

    test('sin username NO se pinta un @ huérfano', () {
      final r = resolve(v2(), edgar, displayName: 'Pedro', username: '');
      expect(r.person, 'Pedro');
      expect(r.person, isNot(startsWith('@')));
    });

    test('perfil borrado o vacío: rótulo de producto, nunca un UID', () {
      final r = resolve(v2(), edgar, displayName: null, username: null);
      expect(r.source, SpaceTitleSource.unnamedPerson);
      expect(r.person, isEmpty);
    });

    test('perfil cargando: no se pinta el nombre persistido', () {
      final r = resolve(v2(), edgar, profileLoading: true);
      expect(r.source, SpaceTitleSource.pendingPerson);
    });

    test('un usuario ajeno no recibe título personalizado', () {
      final r = resolve(v2(), 'uid-ajeno', displayName: 'Pedro');
      expect(r.source, SpaceTitleSource.storedName);
      expect(r.diagnostic, isNotNull);
      expect(
        spaceTitleProfileUid(
          space: v2(),
          currentUid: 'uid-ajeno',
          manuals: [],
        ),
        isNull,
        reason: 'no debe leer el perfil de nadie',
      );
    });

    test('espacio corrupto (una o tres identidades) cae al nombre guardado', () {
      for (final uids in [
        <String>[edgar],
        [edgar, pedro, 'uid-tercero'],
      ]) {
        final r = resolve(v2(uids: uids), edgar, displayName: 'Pedro');
        expect(r.source, SpaceTitleSource.storedName, reason: '$uids');
        expect(r.diagnostic, isNotNull);
      }
    });

    test('pareja con el UID repetido no enseña el propio nombre', () {
      final r = resolve(v2(uids: const [edgar, edgar]), edgar);
      expect(r.source, SpaceTitleSource.storedName);
      expect(r.diagnostic, 'pareja-repetida');
    });
  });

  group('relación v3 (cuenta + MANUAL)', () {
    const pablo = ManualParticipant(id: 'm1', displayName: 'Pablo');

    test('el propietario ve el nombre del MANUAL', () {
      final r = resolve(v3(), edgar, manuals: const [pablo]);
      expect(r.person, 'Pablo');
      // Y no hace falta leer ningún perfil: el manual no tiene UID.
      expect(
        spaceTitleProfileUid(
          space: v3(),
          currentUid: edgar,
          manuals: const [pablo],
        ),
        isNull,
      );
    });

    test('el relationshipManualId no se muestra jamás', () {
      final r = resolve(
        v3(manualId: 'm-secreto'),
        edgar,
        manuals: const [ManualParticipant(id: 'm-secreto', displayName: 'Pablo')],
      );
      expect(r.person, 'Pablo');
      expect(r.person, isNot(contains('m-secreto')));
      expect(r.person, isNot(contains('manual:')));
    });

    test('MANUAL sin nombre: rótulo de producto, no un identificador', () {
      final r = resolve(
        v3(),
        edgar,
        manuals: const [ManualParticipant(id: 'm1', displayName: '  ')],
      );
      expect(r.source, SpaceTitleSource.unnamedPerson);
    });

    test('manuales cargando: no se pinta el nombre persistido', () {
      final r = resolve(v3(), edgar, manualsLoading: true);
      expect(r.source, SpaceTitleSource.pendingPerson);
    });

    test('no depende de que existan dos documentos de membresía', () {
      // Una v3 tiene UN solo miembro y aun así resuelve.
      final r = resolve(v3(), edgar, manuals: const [pablo]);
      expect(r.source, SpaceTitleSource.person);
    });
  });

  group('relación v3 ya VINCULADA (ADR-037)', () {
    const pabloUid = 'uid-pablo';
    const vinculado = ManualParticipant(
      id: 'm1',
      displayName: 'Pablo',
      linkedUid: pabloUid,
    );

    test('para el propietario sigue siendo el MANUAL', () {
      // El histórico no cambia: el actor sigue siendo `manual:{id}`.
      final r = resolve(v3(), edgar, manuals: const [vinculado]);
      expect(r.person, 'Pablo');
    });

    test('para el UID vinculado la otra identidad es el propietario', () {
      expect(
        spaceTitleProfileUid(
          space: v3(),
          currentUid: pabloUid,
          manuals: const [vinculado],
        ),
        edgar,
      );
      final r = resolve(
        v3(),
        pabloUid,
        manuals: const [vinculado],
        displayName: 'Edgar',
      );
      expect(r.person, 'Edgar');
    });

    test('el MANUAL y su linkedUid NO cuentan como dos personas', () {
      // Pablo no puede verse a sí mismo: ni su nombre de manual ni su perfil.
      final r = resolve(
        v3(),
        pabloUid,
        manuals: const [vinculado],
        displayName: 'Edgar',
      );
      expect(r.person, isNot('Pablo'));
    });

    test('alguien ajeno a una v3 vinculada no resuelve nada', () {
      final r = resolve(v3(), 'uid-otro', manuals: const [vinculado]);
      expect(r.source, SpaceTitleSource.storedName);
    });
  });

  group('grupos', () {
    test('conservan su nombre persistido', () {
      final r = resolve(grupo, edgar);
      expect(r.source, SpaceTitleSource.storedName);
      expect(r.diagnostic, isNull, reason: 'no es una anomalía');
    });

    test('no leen el perfil de nadie', () {
      expect(
        spaceTitleProfileUid(space: grupo, currentUid: edgar, manuals: []),
        isNull,
      );
    });
  });

  group('identificador canónico de relación', () {
    test('distingue una relación v2 de un grupo', () {
      expect(isRelationshipSpaceId(relationshipSpaceId(edgar, pedro)), isTrue);
      expect(isRelationshipSpaceId('gen1'), isFalse);
      // Una v3 usa id generado: nunca invita, así que no debe confundirse.
      expect(isRelationshipSpaceId('relationship_solo'), isFalse);
    });
  });
}
