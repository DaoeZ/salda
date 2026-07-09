import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';

/// Rutas de la app (ESPECIFICACION.md §4.3). M0: solo /home como placeholder;
/// el resto de rutas (sesiones, escaneo, ajustes) se añaden en sus fases.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);
