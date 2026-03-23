import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../../config/theme.dart';
import '../../providers/app_state.dart';
import '../../models/task_model.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/task_card.dart';
import '../../widgets/crisis_alert_card.dart';

class CoordinatorDashboard extends StatelessWidget {
  const CoordinatorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return CustomScrollView(
          slivers: [
            // Welcome header
            SliverToBoxAdapter(
              child: FadeInDown(
                duration: const Duration(milliseconds: 600),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Welcome back, ',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                          Text(
                            state.currentUser.name.split(' ').first,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Here\'s what needs your attention today',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textMuted,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Stats Grid
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FadeInUp(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 200),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      StatCard(
                        title: 'Open Tasks',
                        value: '${state.openTasks.length}',
                        icon: Icons.assignment_outlined,
                        color: AppColors.warning,
                        subtitle: '${state.criticalTaskCount} critical',
                      ),
                      StatCard(
                        title: 'Active Volunteers',
                        value: '${state.availableVolunteers.length}',
                        icon: Icons.people_outline,
                        color: AppColors.primary,
                        subtitle: 'of ${state.volunteers.length} total',
                      ),
                      StatCard(
                        title: 'People Affected',
                        value: _formatNumber(state.totalPeopleAffected),
                        icon: Icons.groups_outlined,
                        color: AppColors.error,
                        subtitle: 'across ${state.reports.length} reports',
                      ),
                      StatCard(
                        title: 'Crisis Alerts',
                        value: '${state.activeAlerts.length}',
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.urgencyCritical,
                        subtitle: 'AI-predicted',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Crisis Alerts
            if (state.activeAlerts.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: FadeInLeft(
                    duration: const Duration(milliseconds: 600),
                    delay: const Duration(milliseconds: 400),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.crisis_alert,
                                  size: 14, color: AppColors.error),
                              const SizedBox(width: 4),
                              Text(
                                'AI CRISIS PREDICTIONS',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: state.activeAlerts.length,
                    itemBuilder: (context, index) {
                      return FadeInRight(
                        duration: const Duration(milliseconds: 500),
                        delay: Duration(milliseconds: 100 * index),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: CrisisAlertCard(
                              alert: state.activeAlerts[index]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            // Recent Tasks
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: FadeInLeft(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 600),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Active Tasks',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      TextButton(
                        onPressed: () => state.setNavIndex(1),
                        child: Text(
                          'View All →',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Task list
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final task = state.tasks[index];
                    return FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: Duration(milliseconds: 100 * index),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(task: task),
                      ),
                    );
                  },
                  childCount: state.tasks.length.clamp(0, 5),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
