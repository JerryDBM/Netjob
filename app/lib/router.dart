import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'features/admin/admin_screens.dart';
import 'features/auth/auth_screens.dart';
import 'features/calendar/calendar_screens.dart';
import 'features/claims/claims_screens.dart';
import 'features/client/client_screens.dart';
import 'features/common/benefits_screens.dart';
import 'features/common/common_screens.dart';
import 'features/pro/plan_screens.dart';
import 'features/pro/pro_screens.dart';
import 'features/requests/request_screens.dart';
import 'features/requests/route_screen.dart';
import 'features/requests/track_screen.dart';
import 'features/trust/trust_screens.dart';
import 'features/reviews/reviews_screens.dart';
import 'state/auth_state.dart';

const _publicRoutes = {'/login', '/register', '/forgot'};
const _proOnly = [
  '/pro/services', '/pro/profile', '/pro/subscription', '/pro/onboarding', '/pro/training', '/pro/guides',
  '/pro/verification', '/pro/insights', '/pro/promotions',
];

/// Durante el registro del profesional solo se puede estar en su perfil o en la capacitación.
const _onboardingRoutes = {'/pro/onboarding', '/pro/training'};

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      if (!auth.ready) return null;
      final loc = state.matchedLocation;
      final public = _publicRoutes.contains(loc);
      if (!auth.loggedIn) return public ? null : '/login';
      if (public) return '/home';
      if (auth.isAdmin && loc != '/admin') return '/admin';
      if (_proOnly.any(loc.startsWith) && !auth.isPro) return '/home';
      // El profesional debe completar su perfil antes de usar la app
      if (auth.needsOnboarding && !_onboardingRoutes.contains(loc)) return '/pro/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminHomeScreen()),

      // Navegación principal con barra inferior (distinta para cliente y profesional)
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => context.read<AuthState>().isPro ? const ProDashboardScreen() : const ClientHomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/requests', builder: (_, _) => const RequestsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/agenda', builder: (_, _) => const AgendaScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),

      GoRoute(
        path: '/search',
        builder: (_, s) => SearchScreen(
          q: s.uri.queryParameters['q'],
          categoryId: s.uri.queryParameters['categoryId'],
          title: s.uri.queryParameters['title'],
        ),
      ),
      GoRoute(path: '/pro/services', builder: (_, _) => const MyServicesScreen()),
      GoRoute(path: '/pro/services/edit', builder: (_, s) => ServiceFormScreen(service: s.extra as Map?)),
      GoRoute(path: '/pro/profile', builder: (_, _) => const ProProfileEditScreen()),
      GoRoute(path: '/pro/onboarding', builder: (_, _) => const ProProfileEditScreen(onboarding: true)),
      GoRoute(path: '/pro/subscription', builder: (_, _) => const SubscriptionScreen()),
      GoRoute(path: '/pro/training', builder: (_, _) => const TrainingScreen()),
      GoRoute(path: '/pro/guides', builder: (_, _) => const TrainingScreen(guidesOnly: true)),
      GoRoute(path: '/pro/verification', builder: (_, _) => const VerificationScreen()),
      GoRoute(path: '/pro/insights', builder: (_, _) => const InsightsScreen()),
      GoRoute(path: '/pro/promotions', builder: (_, _) => const PromotionsScreen()),
      GoRoute(path: '/claims', builder: (_, _) => const ClaimsScreen()),
      GoRoute(path: '/benefits', builder: (_, _) => const BenefitsScreen()),
      GoRoute(path: '/clients/:id/reviews', builder: (_, s) => ClientReviewsScreen(userId: s.pathParameters['id']!)),
      GoRoute(path: '/pro/:id/reviews', builder: (_, s) => ReviewsScreen(professionalId: s.pathParameters['id']!)),
      GoRoute(path: '/pro/:id', builder: (_, s) => ProfessionalScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/request/new', builder: (_, s) => NewRequestScreen(service: s.extra as Map)),
      GoRoute(path: '/requests/:id', builder: (_, s) => RequestDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/requests/:id/route', builder: (_, s) => RouteScreen(requestId: s.pathParameters['id']!)),
      GoRoute(path: '/requests/:id/track', builder: (_, s) => TrackScreen(requestId: s.pathParameters['id']!)),
      GoRoute(
        path: '/requests/:id/chat',
        builder: (_, s) => ChatScreen(requestId: s.pathParameters['id']!, title: s.extra as String?),
      ),
      GoRoute(path: '/payments', builder: (_, _) => const PaymentsScreen()),
      GoRoute(path: '/payments/:id/receipt', builder: (_, s) => ReceiptScreen(paymentId: s.pathParameters['id']!)),
      GoRoute(path: '/account/edit', builder: (_, _) => const EditAccountScreen()),
      GoRoute(path: '/account/password', builder: (_, _) => const ChangePasswordScreen()),
    ],
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;
  @override
  State<_Shell> createState() => _ShellState();
}

/// Al cambiar de pestaña, el contenido aparece con un desvanecido y un leve desplazamiento.
class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 360), value: 1);
  late int _index = widget.shell.currentIndex;

  @override
  void didUpdateWidget(covariant _Shell old) {
    super.didUpdateWidget(old);
    if (widget.shell.currentIndex != _index) {
      _index = widget.shell.currentIndex;
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final auth = context.watch<AuthState>();
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    return Scaffold(
      body: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.025), end: Offset.zero).animate(curve),
          child: shell,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          if (i == 3) auth.refreshUnread();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: [
          NavigationDestination(
            icon: Icon(auth.isPro ? Icons.dashboard_outlined : Icons.search),
            selectedIcon: Icon(auth.isPro ? Icons.dashboard : Icons.search),
            label: auth.isPro ? 'Panel' : 'Buscar',
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: auth.isPro ? 'Trabajos' : 'Solicitudes',
          ),
          const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Agenda'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: auth.unreadNotifications > 0,
              label: Text('${auth.unreadNotifications}'),
              child: const Icon(Icons.notifications_none),
            ),
            label: 'Avisos',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cuenta'),
        ],
      ),
    );
  }
}
