import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
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

    test('la audiencia solo contiene cuentas reales, ordenada y sin repetir',
        () {
      expect(
        accountUidsOf(['uid-b', 'manual:mp-1', 'uid-a', 'uid-b']),
        ['uid-a', 'uid-b'],
      );
      // Cuenta ↔ manual: un solo lector posible.
      expect(accountUidsOf(['uid-a', 'manual:mp-1']), ['uid-a']);
      // Manual ↔ manual: nadie puede leerla (vive en su sesión).
      expect(accountUidsOf(['manual:mp-1', 'manual:mp-2']), isEmpty);
    });

    test('renombrar no afecta a la identidad: el actor deriva del id', () {
      const id = 'mp-estable';
      expect(manualActor(id), manualActor(id));
      expect(manualIdOf(manualActor(id)), id);
    });
  });
}
