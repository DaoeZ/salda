import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai/presentation/ai_providers_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/review/presentation/review_screen.dart';
import '../../features/sessions/presentation/session_detail_screen.dart';
import '../../features/sessions/presentation/share_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// Rutas de la app (ESPECIFICACION.md §4.3) con guardia de autenticación.
/// El router se reconstruye al cambiar el estado de auth (patrón Riverpod);
/// a esta escala es más simple y seguro que refreshListenable.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      if (auth.isLoading) return null; // aún restaurando la sesión
      final loggedIn = auth.value != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
          path: '/settings/ai',
          builder: (_, _) => const AiProvidersScreen()),
      GoRoute(
        path: '/session/:sid',
        builder: (_, state) =>
            SessionDetailScreen(sessionId: state.pathParameters['sid']!),
      ),
      GoRoute(
        path: '/session/:sid/share',
        builder: (_, state) =>
            ShareScreen(sessionId: state.pathParameters['sid']!),
      ),
    ],
  );
});
