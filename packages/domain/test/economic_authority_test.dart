import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('autoridad económica sobre un actor', () {
    test('una cuenta solo responde por sí misma', () {
      expect(
        economicActingRole(actor: 'alba', viewerUid: 'alba'),
        EconomicActingRole.self,
      );
      expect(
        economicActingRole(actor: 'alba', viewerUid: 'edgar'),
        EconomicActingRole.none,
      );
    });

    test('ser administrador NO permite actuar sobre una cuenta registrada', () {
      expect(
        economicActingRole(
          actor: 'alba',
          viewerUid: 'edgar',
          viewerIsSpaceAdmin: true,
        ),
        EconomicActingRole.none,
      );
    });

    test('un administrador representa a un manual sin vincular', () {
      expect(
        economicActingRole(
          actor: manualActor('javi'),
          viewerUid: 'edgar',
          viewerIsSpaceAdmin: true,
        ),
        EconomicActingRole.representative,
      );
    });

    test('sin autoridad sobre el espacio no hay representación', () {
      expect(
        economicActingRole(actor: manualActor('javi'), viewerUid: 'edgar'),
        EconomicActingRole.none,
      );
    });

    test('vincular el manual termina la representación (ADR-037)', () {
      expect(
        economicActingRole(
          actor: manualActor('javi'),
          viewerUid: 'edgar',
          viewerIsSpaceAdmin: true,
          linkedUid: 'javi-uid',
        ),
        EconomicActingRole.none,
      );
      expect(
        economicActingRole(
          actor: manualActor('javi'),
          viewerUid: 'javi-uid',
          viewerIsSpaceAdmin: false,
          linkedUid: 'javi-uid',
        ),
        EconomicActingRole.self,
      );
    });

    test('identificadores vacíos nunca autorizan', () {
      expect(
        economicActingRole(actor: '', viewerUid: 'edgar'),
        EconomicActingRole.none,
      );
      expect(
        economicActingRole(actor: 'alba', viewerUid: ''),
        EconomicActingRole.none,
      );
    });
  });

  group('confirmar la recepción de un cobro', () {
    // Los tres ejemplos del contrato de producto, tal cual.
    test('Alba (cuenta) debe a Javi (manual): confirma el administrador', () {
      expect(
        canConfirmReceipt(
          creditorActor: manualActor('javi'),
          viewerUid: 'edgar',
          viewerIsSpaceAdmin: true,
        ),
        isTrue,
      );
    });

    test('Javi (manual) debe a Alba (cuenta): solo confirma Alba', () {
      expect(
        canConfirmReceipt(creditorActor: 'alba', viewerUid: 'alba'),
        isTrue,
      );
      expect(
        canConfirmReceipt(
          creditorActor: 'alba',
          viewerUid: 'edgar',
          viewerIsSpaceAdmin: true,
        ),
        isFalse,
      );
    });

    test('entre dos manuales, el administrador gestiona la liquidación', () {
      expect(
        canConfirmReceipt(
          creditorActor: manualActor('pablo'),
          viewerUid: 'edgar',
          viewerIsSpaceAdmin: true,
        ),
        isTrue,
      );
    });
  });
}
