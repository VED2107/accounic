import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/activity_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/people_screen.dart';
import 'screens/person_screen.dart';
import 'screens/profile_screen.dart';
import 'motion.dart';
import 'shell.dart';

/// Routing (context.md §20, §29).
///
/// Real URLs rather than an imperative navigator stack: Android's back gesture,
/// Windows' Alt+Left and deep links all then behave without special cases, and
/// the route names line up with the web client's.
///
/// The redirect is the app's front door, not its lock — RLS is (context.md §3).
///
/// Tab switches inside the shell cross-fade rather than slide: the four
/// destinations are siblings, and a horizontal slide would imply an order they
/// do not have. The person drill-down keeps the platform's push, because that
/// one *is* a hierarchy and the gesture to come back depends on it.

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

    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => AppShell(
        location: state.matchedLocation,
        child: child,
      ),
      routes: [
        // Person detail is a child of the shell, not a sibling of it: the web
        // client keeps its sidebar on `/people/[id]` and so does this. Pushing
        // it above the shell instead cost the rail on every drill-down, which
        // left a desktop window with a column of content and half a screen of
        // nothing beside it — and took the user's navigation away at the exact
        // moment they were most likely to want it.
        //
        // It is still a *push*, so Android's back gesture and Alt+Left return
        // to the list rather than cross-fading to a sibling tab.
        GoRoute(
          path: '/people/:id',
          parentNavigatorKey: _shellKey,
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Motion.component,
            reverseTransitionDuration: Motion.micro,
            transitionsBuilder: drillIn,
            child: PersonScreen(personId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Motion.component,
            reverseTransitionDuration: Motion.micro,
            transitionsBuilder: fadeThrough,
            child: const DashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/people',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Motion.component,
            reverseTransitionDuration: Motion.micro,
            transitionsBuilder: fadeThrough,
            child: const PeopleScreen(),
          ),
        ),
        GoRoute(
          path: '/activity',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Motion.component,
            reverseTransitionDuration: Motion.micro,
            transitionsBuilder: fadeThrough,
            child: const ActivityScreen(),
          ),
        ),
        GoRoute(
          path: '/admin',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Motion.component,
            reverseTransitionDuration: Motion.micro,
            transitionsBuilder: fadeThrough,
            child: const AdminScreen(),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Motion.component,
            reverseTransitionDuration: Motion.micro,
            transitionsBuilder: fadeThrough,
            child: const ProfileScreen(),
          ),
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
