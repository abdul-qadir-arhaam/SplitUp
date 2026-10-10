import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/auth/presentation/phone_otp_screen.dart';
import '../../features/auth/presentation/merge_explainer_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/friends/presentation/friend_detail_screen.dart';
import '../../features/expenses/presentation/add_expense_screen.dart';
import '../../features/expenses/domain/expense_model.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/groups/presentation/create_group_screen.dart';
import '../../features/groups/presentation/group_detail_screen.dart';
import '../../features/groups/presentation/group_settle_graph_screen.dart';
import '../../features/trips/presentation/trips_screen.dart';
import '../../features/trips/presentation/create_trip_screen.dart';
import '../../features/trips/presentation/trip_detail_screen.dart';
import '../../features/trips/presentation/trip_settle_graph_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../theme/colors.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

Page<dynamic> _buildPageWithTransition({
  required GoRouterState state,
  required Widget child,
  bool slideUp = false,
  bool isTab = false,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Duration(milliseconds: isTab ? 260 : 340),
    reverseTransitionDuration: Duration(milliseconds: isTab ? 220 : 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      if (isTab) {
        return FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curve),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.04),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      }

      if (slideUp) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.22),
            end: Offset.zero,
          ).animate(curve),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curve),
            child: child,
          ),
        );
      }

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.16, 0.0),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}

GoRouter createAppRouter({
  required ThemeMode currentThemeMode,
  required ValueChanged<ThemeMode> onThemeModeChanged,
}) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      // Auth routes (outside shell)
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => _buildPageWithTransition(
          state: state,
          child: const WelcomeScreen(),
          slideUp: true,
        ),
      ),
      GoRoute(
        path: '/phone-otp',
        pageBuilder: (context, state) => _buildPageWithTransition(
          state: state,
          child: const PhoneOtpScreen(),
          slideUp: true,
        ),
      ),
      GoRoute(
        path: '/welcome-back',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return _buildPageWithTransition(
            state: state,
            child: MergeExplainerScreen(
              expenseCount: extra?['expenseCount'] as int? ?? 3,
              totalPaise: extra?['totalPaise'] as int? ?? 185000,
              inviterName: extra?['inviterName'] as String? ?? 'Your friends',
            ),
          );
        },
      ),

      // 4-Tab Main Shell
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ScaffoldWithBottomNavBar(child: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _buildPageWithTransition(
              state: state,
              child: const HomeScreen(),
              isTab: true,
            ),
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (context, state) => _buildPageWithTransition(
              state: state,
              child: const GroupsScreen(),
              isTab: true,
            ),
          ),
          GoRoute(
            path: '/trips',
            pageBuilder: (context, state) => _buildPageWithTransition(
              state: state,
              child: const TripsScreen(),
              isTab: true,
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _buildPageWithTransition(
              state: state,
              child: ProfileScreen(
                currentThemeMode: currentThemeMode,
                onThemeModeChanged: onThemeModeChanged,
              ),
              isTab: true,
            ),
          ),
        ],
      ),

      // Deep Screens (outside shell so bottom bar is hidden)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/friend/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _buildPageWithTransition(
            state: state,
            child: FriendDetailScreen(friendId: id),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/add-expense',
        pageBuilder: (context, state) {
          final friendId = state.uri.queryParameters['friendId'];
          final initialLedgerId = state.uri.queryParameters['ledgerId'];
          final friendIdsParam = state.uri.queryParameters['friendIds'];
          final friendIds = friendIdsParam != null && friendIdsParam.isNotEmpty
              ? friendIdsParam.split(',')
              : null;
          final extra = state.extra as Map<String, dynamic>?;
          return _buildPageWithTransition(
            state: state,
            child: AddExpenseScreen(
              friendId: friendId ?? extra?['friendId'],
              initialLedgerId: initialLedgerId ?? extra?['initialLedgerId'],
              friendIds: friendIds ?? (extra?['friendIds'] as List<String>?),
              initialMembers: extra?['initialMembers'] as List<Map<String, dynamic>>?,
              existingExpense: extra?['existingExpense'] as ExpenseModel?,
            ),
            slideUp: true,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/groups/create',
        pageBuilder: (context, state) => _buildPageWithTransition(
          state: state,
          child: const CreateGroupScreen(),
          slideUp: true,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/groups/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _buildPageWithTransition(
            state: state,
            child: GroupDetailScreen(groupId: id),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/groups/:id/graph',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _buildPageWithTransition(
            state: state,
            child: GroupSettleGraphScreen(groupId: id),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/trips/create',
        pageBuilder: (context, state) => _buildPageWithTransition(
          state: state,
          child: const CreateTripScreen(),
          slideUp: true,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/trips/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _buildPageWithTransition(
            state: state,
            child: TripDetailScreen(tripId: id),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/trips/:id/graph',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _buildPageWithTransition(
            state: state,
            child: TripSettleGraphScreen(tripId: id),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/notifications',
        pageBuilder: (context, state) => _buildPageWithTransition(
          state: state,
          child: const NotificationsScreen(),
        ),
      ),
    ],
  );
}

class ScaffoldWithBottomNavBar extends StatelessWidget {
  final Widget child;

  const ScaffoldWithBottomNavBar({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/groups')) return 1;
    if (location.startsWith('/trips')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/groups');
        break;
      case 2:
        context.go('/trips');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (tabChild, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.035),
                end: Offset.zero,
              ).animate(animation),
              child: tabChild,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(selectedIndex),
          child: child,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surfaceFlat.withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(color: colors.divider, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavBarItem(
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet_rounded,
                  label: 'Friends',
                  isSelected: selectedIndex == 0,
                  colors: colors,
                  onTap: () => _onItemTapped(0, context),
                ),
                _NavBarItem(
                  icon: Icons.group_outlined,
                  activeIcon: Icons.group_rounded,
                  label: 'Groups',
                  isSelected: selectedIndex == 1,
                  colors: colors,
                  onTap: () => _onItemTapped(1, context),
                ),
                _NavBarItem(
                  icon: Icons.flight_takeoff_outlined,
                  activeIcon: Icons.flight_takeoff_rounded,
                  label: 'Trips',
                  isSelected: selectedIndex == 2,
                  colors: colors,
                  onTap: () => _onItemTapped(2, context),
                ),
                _NavBarItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: selectedIndex == 3,
                  colors: colors,
                  onTap: () => _onItemTapped(3, context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final SplitUpColors colors;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = colors.accentReceive;
    final inactiveColor = colors.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              scale: isSelected ? 1.12 : 1.0,
              child: Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
