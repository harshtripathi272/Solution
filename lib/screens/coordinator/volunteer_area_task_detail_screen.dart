import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/task_model.dart';

/// Read-only task detail for coordinators (data from volunteer-area pipeline).
class VolunteerAreaTaskDetailScreen extends StatelessWidget {
  const VolunteerAreaTaskDetailScreen({super.key, required this.task});

  final VolunteerTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgencyColor = _urgencyCol(task.urgency);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(task.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [urgencyColor.withValues(alpha: 0.92), urgencyColor.withValues(alpha: 0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadius.xlR,
                boxShadow: [
                  BoxShadow(
                    color: urgencyColor.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _heroChip(theme, task.urgency.toUpperCase()),
                      _heroChip(theme, task.status.name.toUpperCase()),
                      if (task.matchScore != null)
                        _heroChip(theme, '${(task.matchScore! * 100).round()}% match'),
                      if (task.distanceKm != null)
                        _heroChip(theme, '${task.distanceKm!.toStringAsFixed(1)} km'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    task.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    task.ward,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _section(theme, 'About this need', Icons.info_outline_rounded),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppDecorations.baseCard,
              child: Text(task.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ),
            const SizedBox(height: AppSpacing.lg),
            _section(theme, 'Details', Icons.fact_check_outlined),
            const SizedBox(height: AppSpacing.sm),
            _kvTile(theme, 'Need type', task.needType),
            const SizedBox(height: AppSpacing.sm),
            _kvTile(theme, 'Approx. people affected', '${task.estimatedPeopleAffected}'),
            if (task.requiredSkills.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _section(theme, 'Required skills', Icons.handyman_rounded),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: task.requiredSkills.map((s) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                    decoration: AppDecorations.tagAccent(color: AppColors.tertiary),
                    child: Text(
                      s,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (task.sdgTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _section(theme, 'SDG goals', Icons.public_rounded),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: task.sdgTags.map((sdg) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                    decoration: AppDecorations.tagAccent(color: AppColors.secondary),
                    child: Text(
                      'SDG $sdg',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heroChip(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: AppRadius.pillR,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleMedium),
      ],
    );
  }

  Widget _kvTile(ThemeData theme, String key, String value) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.cardSubtle,
      child: Row(
        children: [
          Expanded(
            child: Text(key, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }

  Color _urgencyCol(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'critical':
        return AppColors.urgencyCritical;
      case 'high':
        return AppColors.urgencyHigh;
      case 'medium':
        return AppColors.urgencyMedium;
      case 'low':
        return AppColors.urgencyLow;
      default:
        return AppColors.primary;
    }
  }
}
