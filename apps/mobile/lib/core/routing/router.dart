import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai/presentation/ai_providers_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/review/presentation/review_screen.dart';
import '../../features/sessions/presentation/session_detail_screen.dart';
import '../../features/sessions/presentation/share_screen.dart';
import '../../features/sessions/presentation/ticket_detail_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// Rutas ANIDADAS bajo /home: navegar con go() a cualquier destino construye
/// la pila completa (home debajo), así SIEMPRE hay "atrás" y nunca se queda
/// el flujo atrapado (bug 4 del MVP: go() a rutas planas vaciaba la pila).
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      if (auth.isLoading) return null;
      final loggedIn = auth.value != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/home',
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(
              path: 'review', builder: (_, _) => const ReviewScreen()),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(
                  path: 'ai',
                  builder: (_, _) => const AiProvidersScreen()),
            ],
          ),
          GoRoute(
            path: 'session/:sid',
            builder: (_, state) =>
                SessionDetailScreen(sessionId: state.pathParameters['sid']!),
            routes: [
              GoRoute(
                path: 'share',
                builder: (_, state) =>
                    ShareScreen(sessionId: state.pathParameters['sid']!),
              ),
              GoRoute(
                path: 'ticket',
                builder: (_, state) => TicketDetailScreen(
                    ticket: state.extra! as TicketRef),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
