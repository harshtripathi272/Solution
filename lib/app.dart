import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'models/user_model.dart';
import 'providers/app_state.dart';
import 'services/auth_service.dart';
import 'screens/auth_wrapper.dart';
import 'screens/coordinator/coordinator_dashboard_screen.dart';
import 'screens/coordinator/heatmap_screen.dart';
import 'screens/coordinator/sdg_dashboard_screen.dart';
import 'screens/volunteer/task_feed_screen.dart';
import 'screens/ngo_worker/report_submission_screen.dart';

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
    return AppBar(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.spa, color: AppColors.onPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Text('SevaSetu', style: Theme.of(context).textTheme.headlineSmall),
      ]),
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_roleIcon(state.currentRole), size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(_roleName(state.currentRole),
                style: Theme.of(context).textTheme.labelLarge),
          ]),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.logout, color: AppColors.error),
          onPressed: () => AuthService().signOut(),
        ),
        const SizedBox(width: 12),
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
      case 1: return const HeatmapScreen();
      case 2: return const SDGDashboardScreen();
      default: return const CoordinatorDashboard();
    }
  }

  Widget _buildVolunteerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0: return const VolunteerTaskFeed();
      case 1: return const Scaffold(body: Center(child: Text('Profile View')));
      default: return const VolunteerTaskFeed();
    }
  }

  Widget _buildNgoWorkerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0: return const ReportSubmissionScreen();
      case 1: return const Scaffold(body: Center(child: Text('History View')));
      default: return const ReportSubmissionScreen();
    }
  }

  Widget _buildBottomNav(BuildContext context, AppState state) {
    final items = _getNavItems(state.currentRole);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        boxShadow: AppDecorations.ambientShadow,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              final isSelected = state.currentNavIndex == entry.key;
              return GestureDetector(
                onTap: () => state.setNavIndex(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.surfaceContainerLow : Colors.transparent,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.value['icon'] as IconData, size: 24,
                        color: isSelected ? AppColors.primary : AppColors.outlineVariant),
                    if (isSelected) ...[
                      const SizedBox(width: 12),
                      Text(entry.value['label'] as String,
                          style: Theme.of(context).textTheme.labelLarge),
                    ],
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
          {'icon': Icons.map, 'label': 'Areas'},
          {'icon': Icons.analytics, 'label': 'Impact'},
        ];
      case UserRole.volunteer:
        return [
          {'icon': Icons.assignment, 'label': 'Tasks'},
          {'icon': Icons.person, 'label': 'Profile'},
        ];
      case UserRole.ngoWorker:
        return [
          {'icon': Icons.add_circle, 'label': 'Report'},
          {'icon': Icons.list_alt, 'label': 'History'},
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
