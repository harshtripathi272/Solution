import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'config/theme.dart';
import 'models/user_model.dart';
import 'providers/app_state.dart';
import 'services/auth_service.dart';
import 'screens/auth_wrapper.dart';
import 'screens/coordinator/coordinator_dashboard_screen.dart';
import 'screens/coordinator/community_graph_screen.dart';
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
          body: _buildBody(state),
          bottomNavigationBar: _buildBottomNav(context, state),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppState state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380; // S8+ width is roughly 360 logical pixels
    
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min, // Prevents row from infinitely expanding
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.spa, color: AppColors.onPrimary, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text('SevaSetu', 
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (state.currentRole == UserRole.volunteer)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on, 
                size: 16, 
                color: state.locationService?.isTracking == true ? AppColors.error : AppColors.outline
              ),
              Switch(
                value: state.locationService?.isTracking ?? false,
                activeThumbColor: AppColors.error,
                onChanged: (_) => state.toggleLocationTracking(),
              ),
            ],
          ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_roleIcon(state.currentRole), size: 16, color: AppColors.primary),
            if (!isSmallScreen) ...[
              const SizedBox(width: 8),
              Text(_roleName(state.currentRole),
                  style: Theme.of(context).textTheme.labelMedium),
            ],
          ]),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.logout, color: AppColors.error),
          onPressed: () => AuthService().signOut(),
          tooltip: 'Sign Out',
        ),
        SizedBox(width: isSmallScreen ? 4 : 12),
      ],
    );
  }

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
      case 0: return const CoordinatorDashboard();
      case 1: return const CommunityGraphScreen();
      case 2: return const SDGDashboardScreen();
      case 3: return const CoordinatorProfileScreen();
      default: return const CoordinatorDashboard();
    }
  }

  Widget _buildVolunteerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0: return const VolunteerTaskFeed();
      case 1: return const VolunteerProfileScreen();
      default: return const VolunteerTaskFeed();
    }
  }

  Widget _buildNgoWorkerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0: return const ReportSubmissionScreen();
      case 1: return const NGOWorkerProfileScreen();
      default: return const ReportSubmissionScreen();
    }
  }

  Widget _buildBottomNav(BuildContext context, AppState state) {
    final items = _getNavItems(state.currentRole);
    final isSmallScreen = MediaQuery.of(context).size.width < 380;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        boxShadow: AppDecorations.ambientShadow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.asMap().entries.map((entry) {
              final isSelected = state.currentNavIndex == entry.key;
              return GestureDetector(
                onTap: () => state.setNavIndex(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCirc,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? (isSmallScreen ? 18 : 28) : 12, 
                    vertical: 12
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryContainer.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.value['icon'] as IconData, size: 24,
                        color: isSelected ? AppColors.primary : AppColors.outlineVariant)
                      .animate(target: isSelected ? 1 : 0)
                      .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 300.ms, curve: Curves.easeOutBack),
                    if (isSelected) 
                      Padding(
                        padding: EdgeInsets.only(left: isSmallScreen ? 6.0 : 12.0),
                        child: Text(entry.value['label'] as String,
                            style: Theme.of(context).textTheme.labelLarge,
                            overflow: TextOverflow.ellipsis)
                          .animate()
                          .fadeIn(duration: 300.ms, curve: Curves.easeOut)
                          .slideX(begin: 0.2, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
                      ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getNavItems(UserRole role) {
    switch (role) {
      case UserRole.coordinator:
        return [
          {'icon': Icons.home_filled, 'label': 'Dashboard'},
          {'icon': Icons.hub, 'label': 'Network'},
          {'icon': Icons.analytics, 'label': 'Impact'},
          {'icon': Icons.person, 'label': 'Profile'},
        ];
      case UserRole.volunteer:
        return [
          {'icon': Icons.assignment, 'label': 'Tasks'},
          {'icon': Icons.person, 'label': 'Profile'},
        ];
      case UserRole.ngoWorker:
        return [
          {'icon': Icons.add_circle, 'label': 'Report'},
          {'icon': Icons.person, 'label': 'Profile'},
        ];
    }
  }

  IconData _roleIcon(UserRole r) => switch (r) {
    UserRole.coordinator => Icons.admin_panel_settings, UserRole.volunteer => Icons.volunteer_activism,
    UserRole.ngoWorker => Icons.people_alt,
  };

  String _roleName(UserRole r) => switch (r) {
    UserRole.coordinator => 'Coordinator', UserRole.volunteer => 'Volunteer',
    UserRole.ngoWorker => 'NGO Worker',
  };
}
