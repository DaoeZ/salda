import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/review/presentation/review_screen.dart';

/// Rutas de la app (ESPECIFICACION.md §4.3). Se amplían por fases.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/review',
      builder: (context, state) => const ReviewScreen(),
    ),
  ],
);
