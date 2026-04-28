import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'models/user_model.dart';
import 'providers/app_state.dart';
import 'services/auth_service.dart';
import 'screens/auth_wrapper.dart';
import 'screens/coordinator/coordinator_dashboard_screen.dart';
import 'screens/coordinator/community_graph_screen.dart';
import 'screens/coordinator/heatmap_screen.dart';
import 'screens/coordinator/sdg_dashboard_screen.dart';
import 'screens/coordinator/coordinator_profile_screen.dart';
import 'screens/volunteer/task_feed_screen.dart';
import 'screens/volunteer/volunteer_profile_screen.dart';
import 'screens/ngo_worker/report_submission_screen.dart';
import 'screens/ngo_worker/ngo_worker_profile_screen.dart';

class SevasetuApp extends StatelessWidget {
  const SevasetuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SevaSetu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: _buildAppBar(context, state),
          body: AnimatedSwitcher(
            duration: AppMotion.standard,
            switchInCurve: AppMotion.easeStandard,
            switchOutCurve: AppMotion.easeStandard,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('${state.currentRole}_${state.currentNavIndex}'),
              child: _buildBody(state),
            ),
          ),
          bottomNavigationBar: _buildBottomNav(context, state),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // App bar
  // ─────────────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    return AppBar(
      titleSpacing: AppSpacing.lg,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdR,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, Color(0xFF3B62F0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.spa_rounded, color: AppColors.onPrimary, size: 18),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              'SevaSetu',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (state.currentRole == UserRole.volunteer) _buildLocationToggle(state),
        const SizedBox(width: AppSpacing.xs),
        _buildRolePill(theme, state, isSmallScreen),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: AppColors.error),
          onPressed: () => AuthService().signOut(),
          tooltip: 'Sign out',
        ),
        SizedBox(width: isSmallScreen ? AppSpacing.xs : AppSpacing.sm),
      ],
    );
  }

  Widget _buildLocationToggle(AppState state) {
    final tracking = state.locationService?.isTracking ?? false;
    return Tooltip(
      message: tracking ? 'Live location on' : 'Live location off',
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: AppRadius.pillR,
          color: tracking
              ? AppColors.errorContainer
              : AppColors.surfaceContainerLow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.my_location_rounded,
              size: 16,
              color: tracking ? AppColors.error : AppColors.onSurfaceVariant,
            ),
            Switch(
              value: tracking,
              activeThumbColor: AppColors.error,
              onChanged: (_) => state.toggleLocationTracking(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolePill(ThemeData theme, AppState state, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? AppSpacing.md : AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(state.currentRole), size: 16, color: AppColors.primary),
          if (!isSmallScreen) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              _roleName(state.currentRole),
              style: theme.textTheme.labelMedium?.copyWith(color: AppColors.onPrimaryContainer),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Body routing
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBody(AppState state) {
    switch (state.currentRole) {
      case UserRole.coordinator:
        return _buildCoordinatorBody(state);
      case UserRole.volunteer:
        return _buildVolunteerBody(state);
      case UserRole.ngoWorker:
        return _buildNgoWorkerBody(state);
    }
  }

  Widget _buildCoordinatorBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0:
        return const CoordinatorDashboard();
      case 1:
        return const HeatmapScreen();
      case 2:
        return const CommunityGraphScreen();
      case 3:
        return const SDGDashboardScreen();
      case 4:
        return const CoordinatorProfileScreen();
      default:
        return const CoordinatorDashboard();
    }
  }

  Widget _buildVolunteerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0:
        return const VolunteerTaskFeed();
      case 1:
        return const VolunteerProfileScreen();
      default:
        return const VolunteerTaskFeed();
    }
  }

  Widget _buildNgoWorkerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0:
        return const ReportSubmissionScreen();
      case 1:
        return const NGOWorkerProfileScreen();
      default:
        return const ReportSubmissionScreen();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom nav — Material 3 NavigationBar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBottomNav(BuildContext context, AppState state) {
    final items = _getNavItems(state.currentRole);
    final selectedIndex = state.currentNavIndex.clamp(0, items.length - 1);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        boxShadow: AppElevation.floating,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => state.setNavIndex(i),
          destinations: items.map((item) {
            return NavigationDestination(
              icon: Icon(item['icon'] as IconData),
              selectedIcon: Icon(item['selectedIcon'] as IconData? ?? item['icon'] as IconData),
              label: item['label'] as String,
              tooltip: item['label'] as String,
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getNavItems(UserRole role) {
    switch (role) {
      case UserRole.coordinator:
        return [
          {'icon': Icons.dashboard_outlined, 'selectedIcon': Icons.dashboard_rounded, 'label': 'Dashboard'},
          {'icon': Icons.map_outlined, 'selectedIcon': Icons.map_rounded, 'label': 'Heatmap'},
          {'icon': Icons.hub_outlined, 'selectedIcon': Icons.hub_rounded, 'label': 'Network'},
          {'icon': Icons.insights_outlined, 'selectedIcon': Icons.insights_rounded, 'label': 'Impact'},
          {'icon': Icons.person_outline_rounded, 'selectedIcon': Icons.person_rounded, 'label': 'Profile'},
        ];
      case UserRole.volunteer:
        return [
          {'icon': Icons.assignment_outlined, 'selectedIcon': Icons.assignment_rounded, 'label': 'Tasks'},
          {'icon': Icons.person_outline_rounded, 'selectedIcon': Icons.person_rounded, 'label': 'Profile'},
        ];
      case UserRole.ngoWorker:
        return [
          {'icon': Icons.add_circle_outline_rounded, 'selectedIcon': Icons.add_circle_rounded, 'label': 'Report'},
          {'icon': Icons.person_outline_rounded, 'selectedIcon': Icons.person_rounded, 'label': 'Profile'},
        ];
    }
  }

  IconData _roleIcon(UserRole r) => switch (r) {
        UserRole.coordinator => Icons.admin_panel_settings_rounded,
        UserRole.volunteer => Icons.volunteer_activism_rounded,
        UserRole.ngoWorker => Icons.people_alt_rounded,
      };

  String _roleName(UserRole r) => switch (r) {
        UserRole.coordinator => 'Coordinator',
        UserRole.volunteer => 'Volunteer',
        UserRole.ngoWorker => 'NGO Worker',
      };
}
