import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai/presentation/ai_providers_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/guest_name_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/activity/presentation/activity_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/economy/presentation/economic_overview_screen.dart';
import '../../features/economy/presentation/economic_relation_screen.dart';
import '../../features/friends/presentation/friends_screen.dart';
import '../../features/friends/presentation/public_profile_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/presentation/people_search_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/review/presentation/review_screen.dart';
import '../../features/sessions/presentation/session_detail_screen.dart';
import '../../features/sessions/presentation/share_screen.dart';
import '../../features/sessions/presentation/ticket_detail_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/spaces/presentation/space_detail_screen.dart';
import '../../features/spaces/presentation/create_relationship_screen.dart';
import '../../features/spaces/presentation/spaces_screen.dart';

/// Rutas ANIDADAS bajo /home: navegar con go() a cualquier destino construye
/// la pila completa (home debajo), así SIEMPRE hay "atrás" y nunca se queda
/// el flujo atrapado (bug 4 del MVP: go() a rutas planas vaciaba la pila).
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  return GoRouter(
    initialLocation: '/auth-loading',
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (auth.isLoading) {
        return location == '/auth-loading' ? null : '/auth-loading';
      }
      final user = auth.value;
      final isPublic =
          location == '/login' ||
          location == '/register' ||
          location == '/forgot-password';
      if (user == null) {
        return isPublic ? null : '/login';
      }
      if (user.needsEmailVerification) {
        return location == '/verify-email' ? null : '/verify-email';
      }
      if (user.isAnonymous) {
        // GUEST (ADR-034): participa en contextos, balances y cronología,
        // pero NUNCA en lo que exige cuenta — perfil público, amistades y
        // búsqueda de personas siguen fuera de su alcance.
        final isAccountOnlyRoute =
            location == '/home/profile' ||
            location == '/home/friends' ||
            location == '/home/people' ||
            location.startsWith('/home/person/');
        if (isAccountOnlyRoute) return '/home';
        if (location == '/register' || location.startsWith('/home')) {
          return null;
        }
        return '/home';
      }
      if (isPublic ||
          location == '/verify-email' ||
          location == '/auth-loading') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth-loading',
        builder: (_, _) => const AuthLoadingScreen(),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordScreen(
          initialEmail: state.extra is String ? state.extra! as String : '',
        ),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(path: 'review', builder: (_, _) => const ReviewScreen()),
          GoRoute(
            path: 'history',
            builder: (_, _) => const LegacySessionsScreen(),
          ),
          GoRoute(
            path: 'relationship/new',
            builder: (_, _) => const CreateRelationshipScreen(),
          ),
          GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen()),
          // Identidad del invitado: su nombre visible (ADR-034).
          GoRoute(
            path: 'guest-name',
            builder: (_, _) => const GuestNameScreen(),
          ),
          GoRoute(path: 'friends', builder: (_, _) => const FriendsScreen()),
          GoRoute(path: 'activity', builder: (_, _) => const ActivityScreen()),
          GoRoute(
            path: 'economy',
            builder: (_, _) => const EconomicOverviewScreen(),
            routes: [
              GoRoute(
                path: ':uid',
                builder: (_, state) => EconomicRelationScreen(
                  otherUid: state.pathParameters['uid']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'people',
            builder: (_, _) => const PeopleSearchScreen(),
          ),
          GoRoute(
            path: 'person/:uid',
            builder: (_, state) =>
                PublicProfileScreen(profileUid: state.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'spaces',
            builder: (_, _) => const SpacesScreen(),
            routes: [
              GoRoute(
                path: ':sid',
                builder: (_, state) =>
                    SpaceDetailScreen(spaceId: state.pathParameters['sid']!),
                routes: [
                  GoRoute(
                    path: 'activity',
                    builder: (_, state) =>
                        ActivityScreen(spaceId: state.pathParameters['sid']!),
                  ),
                  GoRoute(
                    path: 'chat',
                    builder: (_, state) =>
                        ChatScreen(spaceId: state.pathParameters['sid']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'ai', builder: (_, _) => const AiProvidersScreen()),
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
                builder: (_, state) =>
                    TicketDetailScreen(ticket: state.extra! as TicketRef),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
