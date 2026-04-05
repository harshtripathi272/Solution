import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/task_model.dart';

class TaskCard extends StatelessWidget {
  final VolunteerTask task;
  final bool compact;

  const TaskCard({super.key, required this.task, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sc = _statusCol(task.status);
    final theme = Theme.of(context);

    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: AppDecorations.contentBlock,
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title, style: theme.textTheme.titleLarge?.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${task.estimatedPeopleAffected} people · ${task.ward}', style: theme.textTheme.bodyMedium),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(task.status.name.toUpperCase(), style: theme.textTheme.labelLarge?.copyWith(color: sc, fontSize: 11)),
          ),
        ]),
      );
    }

    return Container(
      decoration: AppDecorations.baseCard,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
                child: Text(task.urgency.toUpperCase(), style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 12)),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Text(task.status.name.toUpperCase(), style: theme.textTheme.labelLarge?.copyWith(color: sc, fontSize: 12)),
              ),
              const Spacer(),
              Icon(Icons.location_on, size: 16, color: AppColors.outlineVariant),
              const SizedBox(width: 4),
              Text(task.ward, style: theme.textTheme.bodyMedium),
            ]),
            const SizedBox(height: 20),
            Text(task.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
            const SizedBox(height: 24),
            Row(children: [
              Icon(Icons.groups, size: 18, color: AppColors.outlineVariant),
              const SizedBox(width: 8),
              Text('${task.estimatedPeopleAffected} people', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 16),
              ...task.sdgTags.take(2).map((sdg) => Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                child: Text('SDG $sdg', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }

  Color _statusCol(TaskStatus s) => switch (s) {
    TaskStatus.open => AppColors.warning, TaskStatus.assigned => AppColors.info,
    TaskStatus.inProgress => AppColors.primary, TaskStatus.completed => AppColors.success,
    TaskStatus.cancelled => AppColors.onSurfaceVariant,
  };
}
