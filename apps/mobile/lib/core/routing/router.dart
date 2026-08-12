import 'package:flutter/material.dart';
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
import '../../features/sessions/data/ticket_links_repository.dart';
import '../../features/sessions/presentation/join_ticket_screen.dart';
import '../../features/sessions/presentation/linked_ticket_screen.dart';
import '../../features/sessions/presentation/session_detail_screen.dart';
import '../../features/sessions/presentation/share_screen.dart';
import '../../features/sessions/presentation/ticket_navigation.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/account_hub_screen.dart';
import '../../features/spaces/data/spaces_repository.dart';
import '../../features/spaces/presentation/space_detail_screen.dart';
import '../../features/spaces/presentation/create_relationship_screen.dart';
import '../../features/spaces/presentation/join_space_screen.dart';
import '../../features/spaces/presentation/space_link_screen.dart';
import '../../features/spaces/presentation/spaces_screen.dart';
import '../../l10n/generated/app_localizations.dart';

/// Rutas ANIDADAS bajo /home: navegar con go() a cualquier destino construye
/// la pila completa (home debajo), así SIEMPRE hay "atrás" y nunca se queda
/// el flujo atrapado (bug 4 del MVP: go() a rutas planas vaciaba la pila).
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  // Enlace de grupo a medio canjear (ADR-035): quien toca "iniciar sesión" o
  // "crear cuenta" desde el enlace vuelve a él en cuanto se identifica, en
  // vez de aterrizar en /home habiendo perdido el enlace del chat.
  final pendingGroupLink = ref.watch(pendingGroupLinkProvider);
  final pendingTicketLink = ref.watch(pendingTicketLinkProvider);
  return GoRouter(
    initialLocation: '/auth-loading',
    errorBuilder: (_, _) => const _ProductRouteError(),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (auth.isLoading) {
        return location == '/auth-loading' ? null : '/auth-loading';
      }
      final user = auth.value;
      // El enlace de grupo (ADR-035) es público a propósito: quien lo abre
      // sin sesión decide EN la propia pantalla si entra con cuenta o como
      // invitado. Mandarlo al login perdería el enlace por el camino.
      final isJoinLink =
          location.startsWith('/join') || location.startsWith('/g/');
      // Enlace de TICKET (ADR-036): mismo trato que el de grupo.
      final isTicketLink =
          location.startsWith('/t/') || location.startsWith('/ticket/');
      final isPublic =
          location == '/login' ||
          location == '/register' ||
          location == '/forgot-password' ||
          isJoinLink ||
          isTicketLink;
      if (user == null) {
        return isPublic ? null : '/login';
      }
      // La pantalla del enlace se queda en pie para CUALQUIER sesión, aunque
      // esté a medio verificar: es ella la que recuerda el token. Si aquí se
      // desviara a /verify-email, quien acaba de crear la cuenta perdería el
      // enlace justo en el paso donde más fácil es perderlo.
      if (isJoinLink || isTicketLink) return null;
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
            location == '/home/people-search' ||
            location == '/home/personas' ||
            location.startsWith('/home/person/');
        if (isAccountOnlyRoute) return '/home';
        if (location == '/register' ||
            isJoinLink ||
            isTicketLink ||
            location.startsWith('/home')) {
          return null;
        }
        return _afterAuth(pendingGroupLink, pendingTicketLink);
      }
      if (isJoinLink) return null;
      if (isPublic ||
          location == '/verify-email' ||
          location == '/auth-loading') {
        // Ya identificado y con un enlace a medias: de vuelta al enlace.
        return _afterAuth(pendingGroupLink, pendingTicketLink);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth-loading',
        builder: (_, _) => const AuthLoadingScreen(),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // Enlace de grupo. `/g/:token` es la ruta CANÓNICA — la misma que
      // lleva la URL compartida, para que el deep link resuelva en cuanto
      // Hosting sirva la página y Android verifique los App Links. `/join`
      // es la entrada manual (pegar el enlace), que es lo que funciona hoy.
      GoRoute(
        path: '/g/:token',
        builder: (_, state) =>
            JoinSpaceScreen(token: state.pathParameters['token']),
      ),
      // Enlace de TICKET (ADR-036). Ruta propia y pública por el mismo
      // motivo que /g/: quien lo abre sin sesión decide ahí mismo.
      GoRoute(
        path: '/t/:token',
        builder: (_, state) =>
            JoinTicketScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(
        path: '/ticket/:token',
        builder: (_, state) =>
            LinkedTicketScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(
        path: '/join',
        builder: (_, _) => const JoinSpaceScreen(),
        routes: [
          GoRoute(
            path: ':token',
            builder: (_, state) =>
                JoinSpaceScreen(token: state.pathParameters['token']),
          ),
        ],
      ),
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
          GoRoute(path: 'account', builder: (_, _) => const AccountHubScreen()),
          // Identidad del invitado: su nombre visible (ADR-034).
          GoRoute(
            path: 'guest-name',
            builder: (_, _) => const GuestNameScreen(),
          ),
          GoRoute(path: 'friends', builder: (_, _) => const FriendsScreen()),
          GoRoute(path: 'personas', builder: (_, _) => const FriendsScreen()),
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
            path: 'people-search',
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
                    path: 'link',
                    builder: (_, state) =>
                        SpaceLinkScreen(spaceId: state.pathParameters['sid']!),
                  ),
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
              // Por IDENTIFICADOR, no por objeto: así cualquier
              // superficie puede enlazar a un ticket y el enlace es
              // reconstruible (volver atrás, restaurar estado).
              GoRoute(
                path: 'ticket/:tid',
                builder: (_, state) => TicketRoute(
                  sessionId: state.pathParameters['sid']!,
                  ticketId: state.pathParameters['tid']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// A dónde va alguien que acaba de identificarse. Un enlace a medias —de
/// grupo o de ticket— manda sobre el inicio: perderlo obligaría a volver a
/// buscarlo en el chat, que es justo el punto donde el flujo se rompía.
String _afterAuth(String? groupToken, String? ticketToken) {
  if (ticketToken != null) return '/t/$ticketToken';
  if (groupToken != null) return '/g/$groupToken';
  return '/home';
}

/// Error de navegación de producto. Solo cubre ubicaciones que GoRouter no
/// reconoce; no atrapa excepciones de widgets en debug.
class _ProductRouteError extends StatelessWidget {
  const _ProductRouteError();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.travel_explore_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                l10n.routeNotFoundTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(l10n.routeNotFoundBody, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: Text(l10n.routeGoHome),
              ),
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
                child: Text(l10n.routeBack),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
