import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/foundation.dart';

/// Configuración de enlaces por entorno. La marca y los dominios viven en
/// brand.json; aquí solo se decide cuál corresponde a cada tipo de build.
abstract final class AppEnvironment {
  static const _requested = String.fromEnvironment(
    'SALDA_ENV',
    defaultValue: kReleaseMode ? 'production' : 'development',
  );
  static const _domainOverride = String.fromEnvironment('SALDA_HOSTING_DOMAIN');

  static String get hostingDomain => resolveHostingDomain(
    release: kReleaseMode,
    environment: _requested,
    override: _domainOverride,
  );

  static String get expectedFirebaseProjectId => hostingDomain.split('.').first;

  /// Se ejecuta antes de Firebase para que una release mal configurada falle
  /// al arrancar, en vez de generar enlaces de desarrollo silenciosamente.
  static void validate() => hostingDomain;

  /// Impide que una release comparta enlaces de producción mientras escribe
  /// datos en salda-dev (o la combinación inversa).
  static void validateFirebaseProject(String projectId) {
    if (projectId != expectedFirebaseProjectId) {
      throw StateError(
        'Firebase ($projectId) y Hosting ($hostingDomain) pertenecen a entornos distintos',
      );
    }
  }

  @visibleForTesting
  static String resolveHostingDomain({
    required bool release,
    required String environment,
    String override = '',
  }) {
    if (environment != 'development' && environment != 'production') {
      throw StateError('SALDA_ENV debe ser development o production');
    }
    final domain = override.trim().isNotEmpty
        ? override.trim()
        : environment == 'production'
        ? Brand.productionHostingDomain
        : Brand.developmentHostingDomain;
    if (release && domain == Brand.developmentHostingDomain) {
      throw StateError(
        'Una build release no puede compartir enlaces de salda-dev',
      );
    }
    return domain;
  }
}
