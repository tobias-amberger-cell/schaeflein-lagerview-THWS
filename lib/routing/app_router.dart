import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/state/app_state.dart';
import '../features/auth/presentation/screens/access_denied_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/profile/presentation/screens/settings_screen.dart';

import '../features/viewer/presentation/screens/viewer_screen.dart';
import '../features/viewer/presentation/screens/viewer_tour_fullscreen_screen.dart';
import '../features/warehouses/presentation/screens/warehouses_screen.dart';
import '../shared/widgets/app_scaffold.dart';

GoRouter createAppRouter(AppState appState) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: appState,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isLogin = location == '/login';
      final isAccessDenied = location == '/access-denied';
      final isPublic = isSplash || isLogin;

      if (!appState.isAuthenticated && !isPublic && !isAccessDenied) {
        return '/login';
      }
      if (appState.isAuthenticated && (isSplash || isLogin)) {
        return '/dashboard';
      }
      if (appState.isAuthenticated &&
          !isPublic &&
          !isAccessDenied &&
          !_hasAccessForRole(location: location, appState: appState)) {
        final encodedPath = Uri.encodeComponent(location);
        return '/access-denied?from=$encodedPath';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _buildAnimatedPage(
          state: state,
          child: const SplashScreen(),
          beginOffset: Offset.zero,
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildAnimatedPage(
          state: state,
          child: const LoginScreen(),
          beginOffset: const Offset(0, 0.01),
        ),
      ),
      GoRoute(
        path: '/access-denied',
        pageBuilder: (context, state) {
          final fromPath = state.uri.queryParameters['from'];
          return _buildAnimatedPage(
            state: state,
            child: AccessDeniedScreen(fromPath: fromPath),
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _buildAnimatedPage(
              state: state,
              child: const DashboardScreen(),
            ),
          ),
          
          GoRoute(
            path: '/warehouses',
            pageBuilder: (context, state) => _buildAnimatedPage(
              state: state,
              child: const WarehousesScreen(),
            ),
          ),
          GoRoute(
            path: '/warehouses/:warehouseId',
            redirect: (context, state) => '/warehouses',
          ),
          GoRoute(
            path: '/viewer',
            pageBuilder: (context, state) => _buildAnimatedPage(
              state: state,
              child: const ViewerScreen(),
            ),
          ),
          GoRoute(
            path: '/viewer/tour',
            pageBuilder: (context, state) => _buildAnimatedPage(
              state: state,
              child: const ViewerTourFullscreenScreen(),
              beginOffset: const Offset(0, 0.02),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _buildAnimatedPage(
              state: state,
              child: const ProfileScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _buildAnimatedPage(
          state: state,
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => _buildAnimatedPage(
          state: state,
          child: const NotificationsScreen(),
        ),
      ),
    ],
  );
}

CustomTransitionPage<void> _buildAnimatedPage({
  required GoRouterState state,
  required Widget child,
  Offset beginOffset = const Offset(0, 0.012),
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 190),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slideAnimation = Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: slideAnimation,
          child: child,
        ),
      );
    },
  );
}

bool _hasAccessForRole({
  required String location,
  required AppState appState,
}) {
  return true;
}
