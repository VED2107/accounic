import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/activity_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/people_screen.dart';
import 'screens/person_screen.dart';
import 'screens/profile_screen.dart';
import 'shell.dart';

/// Routing (context.md §20, §29).
///
/// Real URLs rather than an imperative navigator stack: Android's back gesture,
/// Windows' Alt+Left and deep links all then behave without special cases, and
/// the route names line up with the web client's.
///
/// The redirect is the app's front door, not its lock — RLS is (context.md §3).

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  refreshListenable: _AuthListenable(Supabase.instance.client.auth.onAuthStateChange),
  redirect: (context, state) {
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    final atLogin = state.matchedLocation == '/login';

    if (!signedIn) return atLogin ? null : '/login';
    if (atLogin) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    // Person detail sits above the shell: on a phone it is a pushed page with a
    // back button, which is what a drill-down should feel like.
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/people/:id',
      builder: (context, state) => PersonScreen(personId: state.pathParameters['id']!),
    ),

    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => AppShell(
        location: state.matchedLocation,
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/people',
          pageBuilder: (context, state) => const NoTransitionPage(child: PeopleScreen()),
        ),
        GoRoute(
          path: '/activity',
          pageBuilder: (context, state) => const NoTransitionPage(child: ActivityScreen()),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => const NoTransitionPage(child: ProfileScreen()),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('That screen does not exist.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go to dashboard'),
          ),
        ],
      ),
    ),
  ),
);

/// Bridges the Supabase auth stream to something GoRouter can listen to.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Stream<AuthState> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
