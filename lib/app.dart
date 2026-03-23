import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import 'config/theme.dart';
import 'models/user_model.dart';
import 'providers/app_state.dart';
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
      theme: AppTheme.darkTheme,
      home: const AppShell(),
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
          appBar: _buildAppBar(context, state),
          body: _buildBody(state),
          bottomNavigationBar: _buildBottomNav(state),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppState state) {
    return AppBar(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: AppDecorations.primaryGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.volunteer_activism, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        const Text('SevaSetu'),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('AI', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ]),
      actions: [
        // Role switcher
        PopupMenuButton<UserRole>(
          icon: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_roleIcon(state.currentRole), size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(_roleName(state.currentRole),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.textMuted),
            ]),
          ),
          itemBuilder: (context) => UserRole.values.map((role) => PopupMenuItem(
                value: role,
                child: Row(children: [
                  Icon(_roleIcon(role), size: 16, color: state.currentRole == role ? AppColors.primary : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(_roleName(role), style: TextStyle(
                    color: state.currentRole == role ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: state.currentRole == role ? FontWeight.w700 : FontWeight.w400,
                  )),
                ]),
              )).toList(),
          onSelected: (role) => state.switchRole(role),
          color: AppColors.bgCard,
        ),
        const SizedBox(width: 8),
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
      case 1: return const VolunteerProfilePlaceholder();
      default: return const VolunteerTaskFeed();
    }
  }

  Widget _buildNgoWorkerBody(AppState state) {
    switch (state.currentNavIndex) {
      case 0: return const ReportSubmissionScreen();
      case 1: return const ReportsListPlaceholder();
      default: return const ReportSubmissionScreen();
    }
  }

  Widget _buildBottomNav(AppState state) {
    final items = _getNavItems(state.currentRole);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(top: BorderSide(color: AppColors.glassBorder, width: 0.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              final isSelected = state.currentNavIndex == entry.key;
              return GestureDetector(
                onTap: () => state.setNavIndex(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.value['icon'] as IconData, size: 20,
                        color: isSelected ? AppColors.primary : AppColors.textMuted),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      Text(entry.value['label'] as String,
                          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
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
          {'icon': Icons.dashboard_outlined, 'label': 'Dashboard'},
          {'icon': Icons.map_outlined, 'label': 'Heatmap'},
          {'icon': Icons.analytics_outlined, 'label': 'Impact'},
        ];
      case UserRole.volunteer:
        return [
          {'icon': Icons.assignment_outlined, 'label': 'Tasks'},
          {'icon': Icons.person_outline, 'label': 'Profile'},
        ];
      case UserRole.ngoWorker:
        return [
          {'icon': Icons.add_circle_outline, 'label': 'Report'},
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

// Placeholder screens
class VolunteerProfilePlaceholder extends StatelessWidget {
  const VolunteerProfilePlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final user = state.currentUser;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          FadeInDown(duration: const Duration(milliseconds: 600), child: Container(
            padding: const EdgeInsets.all(24),
            decoration: AppDecorations.glassCard,
            child: Column(children: [
              CircleAvatar(radius: 40, backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: Text(user.name[0], style: const TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(user.email, style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _profileStat('${user.tasksCompleted}', 'Tasks Done'),
                _profileStat('${user.totalHoursVolunteered}h', 'Hours'),
                _profileStat('${user.trustScore}', 'Trust Score'),
              ]),
            ]),
          )),
          const SizedBox(height: 16),
          FadeInUp(duration: const Duration(milliseconds: 600), delay: const Duration(milliseconds: 200), child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppDecorations.glassCard,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Skills', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: user.skills.map((s) => Chip(
                label: Text(s), backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                labelStyle: const TextStyle(color: AppColors.primary, fontSize: 12),
              )).toList()),
            ]),
          )),
        ]),
      );
    });
  }

  static Widget _profileStat(String value, String label) => Column(children: [
    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
    const SizedBox(height: 4),
    Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
  ]);
}

class ReportsListPlaceholder extends StatelessWidget {
  const ReportsListPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: state.reports.length,
        itemBuilder: (context, i) {
          final r = state.reports[i];
          final uc = switch (r.urgency) {
            'Critical' => AppColors.urgencyCritical, 'High' => AppColors.urgencyHigh,
            'Medium' => AppColors.urgencyMedium, _ => AppColors.urgencyLow,
          };
          return FadeInUp(
            duration: const Duration(milliseconds: 500),
            delay: Duration(milliseconds: 80 * i),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: AppDecorations.glassCard,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: uc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(r.urgency.toUpperCase(), style: TextStyle(color: uc, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text(r.needType, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  Text(r.ward, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Text('${r.estimatedPeopleAffected} people · ${r.location}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
          );
        },
      );
    });
  }
}
