import 'package:design_tokens/design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/config/app_environment.dart';

void main() {
  group('configuración de enlaces por entorno', () {
    test('debug usa salda-dev y producción usa salda-prod', () {
      expect(
        AppEnvironment.resolveHostingDomain(
          release: false,
          environment: 'development',
        ),
        Brand.developmentHostingDomain,
      );
      expect(
        AppEnvironment.resolveHostingDomain(
          release: true,
          environment: 'production',
        ),
        Brand.productionHostingDomain,
      );
    });

    test('una release no puede apuntar al hosting de desarrollo', () {
      expect(
        () => AppEnvironment.resolveHostingDomain(
          release: true,
          environment: 'development',
        ),
        throwsStateError,
      );
      expect(
        () => AppEnvironment.resolveHostingDomain(
          release: true,
          environment: 'production',
          override: Brand.developmentHostingDomain,
        ),
        throwsStateError,
      );
    });

    test('rechaza nombres de entorno desconocidos', () {
      expect(
        () => AppEnvironment.resolveHostingDomain(
          release: false,
          environment: 'staging',
        ),
        throwsStateError,
      );
    });

    test('el proyecto Firebase debe coincidir con el dominio compartido', () {
      expect(
        () => AppEnvironment.validateFirebaseProject('salda-dev'),
        returnsNormally,
      );
      expect(
        () => AppEnvironment.validateFirebaseProject('salda-prod'),
        throwsStateError,
      );
    });
  });
}
