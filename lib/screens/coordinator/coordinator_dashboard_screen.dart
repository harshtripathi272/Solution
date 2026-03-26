import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../config/theme.dart';
import '../../models/task_model.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/task_card.dart';
import '../../widgets/crisis_alert_card.dart';

class CoordinatorDashboard extends StatelessWidget {
  const CoordinatorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.isLoading) return const Center(child: CircularProgressIndicator());

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Here is the latest snapshot of your community.',
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    Text('Overview', style: theme.textTheme.displayMedium),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatCard(
                      title: 'Open Needs',
                      value: '${state.tasks.where((t) => t.status == TaskStatus.open).length}',
                      icon: Icons.assignment_late,
                      color: AppColors.warning,
                      subtitle: '+2 since yesterday',
                    ),
                    StatCard(
                      title: 'Active Volunteers',
                      value: '${state.volunteers.where((v) => v.isAvailable).length}',
                      icon: Icons.people,
                      color: AppColors.primary,
                      subtitle: '98% capacity',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Crisis Alerts
              if (state.crisisAlerts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text('Predictive Alerts', style: theme.textTheme.headlineLarge),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: Text('${state.crisisAlerts.length} Active', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 240,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: state.crisisAlerts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
                    itemBuilder: (context, index) => CrisisAlertCard(alert: state.crisisAlerts[index]),
                  ),
                ),
                const SizedBox(height: 48),
              ],
              
              // Recent Tasks
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('Recent Needs', style: theme.textTheme.headlineLarge),
              ),
              const SizedBox(height: 24),
              
              ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.tasks.take(5).length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: TaskCard(task: state.tasks[index]),
                  );
                },
              ),
              
              const SizedBox(height: 48),
            ],
          ),
        );
      },
    );
  }
}
