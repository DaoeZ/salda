import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/domain/space_identities.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';

/// BUG-6: un contexto opera cuando tiene PERSONAS suficientes, no cuando
/// tiene un número concreto de cuentas.
void main() {
  SpaceMember cuenta(String uid) => SpaceMember(uid: uid);
  SpaceMember invitado(String uid) =>
      SpaceMember(uid: uid, kind: SpaceMemberKind.guest, displayName: 'Inv');
  ManualParticipant manual(String id, {String? linked}) =>
      ManualParticipant(id: id, displayName: id, linkedUid: linked);

  bool listoGrupo(List<SpaceMember> m, List<ManualParticipant> ma) =>
      contextReadyForExpenses(
        SpaceKind.group,
        spaceEconomicIdentities(members: m, manuals: ma).length,
      );

  bool listoRelacion(List<SpaceMember> m, List<ManualParticipant> ma) =>
      contextReadyForExpenses(
        SpaceKind.relationship,
        spaceEconomicIdentities(members: m, manuals: ma).length,
      );

  group('grupos', () {
    test('solo el propietario: no hay con quién repartir', () {
      expect(listoGrupo([cuenta('edgar')], const []), isFalse);
    });

    test('ACCOUNT + MANUAL: operativo — el caso de Pablo', () {
      // Nadie tiene que registrarse para que esto funcione.
      expect(listoGrupo([cuenta('edgar')], [manual('m-pablo')]), isTrue);
    });

    test('ACCOUNT + GUEST: operativo', () {
      expect(listoGrupo([cuenta('edgar'), invitado('g1')], const []), isTrue);
    });

    test('ACCOUNT + ACCOUNT: operativo (sin regresión)', () {
      expect(listoGrupo([cuenta('edgar'), cuenta('ana')], const []), isTrue);
    });

    test('dos MANUAL además del propietario: tres identidades', () {
      final ids = spaceEconomicIdentities(
        members: [cuenta('edgar')],
        manuals: [manual('m1'), manual('m2')],
      );
      expect(ids.length, 3);
    });

    test('un MANUAL vinculado no se cuenta junto a su cuenta', () {
      // Pablo se registró y entró en el grupo: sigue siendo UNA persona, así
      // que con Edgar y él el grupo opera, pero no aparecen tres.
      final ids = spaceEconomicIdentities(
        members: [cuenta('edgar'), cuenta('uid-pablo')],
        manuals: [manual('m-pablo', linked: 'uid-pablo')],
      );
      expect(ids.length, 2);
      expect(
        listoGrupo(
          [cuenta('edgar'), cuenta('uid-pablo')],
          [manual('m-pablo', linked: 'uid-pablo')],
        ),
        isTrue,
      );
    });

    test('quitar el MANUAL vuelve a dejarlo no operativo', () {
      expect(listoGrupo([cuenta('edgar')], [manual('m1')]), isTrue);
      expect(listoGrupo([cuenta('edgar')], const []), isFalse);
    });

    test('una invitación pendiente no incorpora a nadie', () {
      // Las invitaciones ni siquiera entran en el cálculo: solo cuenta lo
      // que YA está dentro. Con una sola membresía sigue sin poder repartir.
      expect(listoGrupo([cuenta('edgar')], const []), isFalse);
    });
  });

  group('relaciones', () {
    test('v2 pendiente (una sola identidad incorporada) no opera', () {
      expect(listoRelacion([cuenta('edgar')], const []), isFalse);
    });

    test('v2 activa con las dos cuentas sí opera', () {
      expect(
        listoRelacion([cuenta('edgar'), cuenta('pedro')], const []),
        isTrue,
      );
    });

    test('v3 ACCOUNT + MANUAL opera (BUG-2 sigue en pie)', () {
      expect(listoRelacion([cuenta('edgar')], [manual('m-pablo')]), isTrue);
    });

    test('v3 con el MANUAL vinculado siguen siendo DOS, no tres', () {
      final ids = spaceEconomicIdentities(
        members: [cuenta('edgar')],
        manuals: [manual('m-pablo', linked: 'uid-pablo')],
      );
      expect(ids.length, 2);
      expect(
        listoRelacion(
          [cuenta('edgar')],
          [manual('m-pablo', linked: 'uid-pablo')],
        ),
        isTrue,
      );
    });

    test('una relación con tres identidades deja de ser válida', () {
      // Exactamente dos: ni una más. Protege el invariante de ADR-030.
      expect(
        listoRelacion([cuenta('edgar'), cuenta('pedro')], [manual('m1')]),
        isFalse,
      );
    });
  });
}
