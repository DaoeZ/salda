import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  bug6();
  group('actor económico (ADR-033)', () {
    test('una cuenta es su propio UID; un manual lleva prefijo', () {
      expect(accountActor('aBc123'), 'aBc123');
      expect(manualActor('mp-1'), 'manual:mp-1');
      expect(isAccountActor('aBc123'), isTrue);
      expect(isManualActor('aBc123'), isFalse);
      expect(isManualActor('manual:mp-1'), isTrue);
      expect(isAccountActor('manual:mp-1'), isFalse);
    });

    test('los documentos económicos anteriores siguen siendo válidos', () {
      // Un valor sin prefijo (todo lo escrito antes de ADR-033) se
      // interpreta como cuenta: no hace falta migrar nada.
      expect(isAccountActor('uid-edgar'), isTrue);
      expect(manualIdOf('uid-edgar'), isNull);
      expect(manualIdOf('manual:mp-7'), 'mp-7');
    });

    test('el prefijo no puede colisionar ni falsificarse', () {
      // Los UID de Firebase son alfanuméricos: ':' está reservado.
      expect(() => manualActor('con:dospuntos'), throwsArgumentError);
      expect(() => manualActor(''), throwsArgumentError);
      expect(() => accountActor('manual:x'), throwsArgumentError);
      expect(() => accountActor(''), throwsArgumentError);
    });

    test(
      'la audiencia solo contiene cuentas reales, ordenada y sin repetir',
      () {
        expect(accountUidsOf(['uid-b', 'manual:mp-1', 'uid-a', 'uid-b']), [
          'uid-a',
          'uid-b',
        ]);
        // Cuenta ↔ manual: un solo lector posible.
        expect(accountUidsOf(['uid-a', 'manual:mp-1']), ['uid-a']);
        // Manual ↔ manual: nadie puede leerla (vive en su sesión).
        expect(accountUidsOf(['manual:mp-1', 'manual:mp-2']), isEmpty);
      },
    );

    test('renombrar no afecta a la identidad: el actor deriva del id', () {
      const id = 'mp-estable';
      expect(manualActor(id), manualActor(id));
      expect(manualIdOf(manualActor(id)), id);
    });
  });
}

/// BUG-6: cuántas PERSONAS hay en un contexto. Contar membresías respondía a
/// otra pregunta y dejaba fuera a quien no tiene cuenta.
void bug6() {
  group('effectiveEconomicIdentities', () {
    test('una cuenta sola es UNA identidad', () {
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar'],
        manualLinks: const {},
      );
      expect(ids, ['edgar']);
    });

    test('cuenta + MANUAL son DOS: el caso de Pablo', () {
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar'],
        manualLinks: const {'m-pablo': null},
      );
      expect(ids.length, 2);
      expect(ids, contains('manual:m-pablo'));
    });

    test('cuenta + INVITADO son DOS (un invitado tiene UID)', () {
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar', 'uid-invitado'],
        manualLinks: const {},
      );
      expect(ids.length, 2);
    });

    test('dos manuales además del propietario son TRES', () {
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar'],
        manualLinks: const {'m1': null, 'm2': null},
      );
      expect(ids.length, 3);
    });

    test('un MANUAL vinculado y su cuenta son UNA persona, no dos', () {
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar', 'uid-pablo'],
        manualLinks: const {'m-pablo': 'uid-pablo'},
      );
      expect(ids, ['edgar', 'uid-pablo']);
      expect(ids, isNot(contains('manual:m-pablo')));
    });

    test('vinculado a alguien que aún NO es miembro sigue siendo uno', () {
      // ADR-037 no da membresía: la persona es una identidad igual.
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar'],
        manualLinks: const {'m-pablo': 'uid-pablo'},
      );
      expect(ids, ['edgar', 'uid-pablo']);
    });

    test('quitar el manual deja una sola identidad', () {
      expect(
        effectiveEconomicIdentities(
          accountUids: const ['edgar'],
          manualLinks: const {},
        ).length,
        1,
      );
    });

    test('membresías repetidas no inflan la cuenta', () {
      final ids = effectiveEconomicIdentities(
        accountUids: const ['edgar', 'edgar'],
        manualLinks: const {},
      );
      expect(ids, ['edgar']);
    });

    test('documentos legacy inválidos no cuentan como personas', () {
      final ids = effectiveEconomicIdentities(
        // Vacíos y con ':' — un actor no puede construirse con ellos.
        accountUids: const ['edgar', '', 'con:dospuntos'],
        manualLinks: const {'': null, 'roto:id': null, 'm1': ''},
      );
      expect(ids, ['edgar', 'manual:m1']);
    });

    test('es el MISMO criterio con el que se consolidan saldos', () {
      // Si divergiera, la app dejaría repartir entre dos personas que
      // recompute trataría como una (o al revés).
      const aliases = {'m-pablo': 'uid-pablo'};
      expect(
        resolveActorIdentity('manual:m-pablo', aliases),
        effectiveEconomicIdentities(
          accountUids: const [],
          manualLinks: const {'m-pablo': 'uid-pablo'},
        ).single,
      );
    });
  });
}
