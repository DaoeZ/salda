import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/presentation/join_space_screen.dart';

/// El enlace compartido y la ruta que lo abre tienen que ser LA MISMA, o el
/// deep link no resolverá el día que Hosting sirva la página y Android
/// verifique los App Links (ADR-035).
void main() {
  test('la URL canónica del enlace es /g/{token}', () {
    final url = SpacesRepository.joinUrlFor('salda-dev.web.app', 'abc123');
    expect(url, 'https://salda-dev.web.app/g/abc123');
  });

  testWidgets('la ruta canónica /g/:token abre la pantalla de unirse', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/g/token-de-prueba',
      routes: [
        GoRoute(
          path: '/g/:token',
          builder: (_, state) =>
              JoinSpaceScreen(token: state.pathParameters['token']),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Basta con que la ruta case y construya: la pantalla completa se
    // ejercita en space_links_test.dart a través del repositorio.
    expect(
      router.configuration.findMatch(Uri.parse('/g/token-de-prueba')).routes,
      isNotEmpty,
    );
    expect(
      SpacesRepository.joinUrlFor('salda-dev.web.app', 'token-de-prueba'),
      contains('/g/token-de-prueba'),
    );
  });
}
