import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/task_model.dart';

class TaskCard extends StatelessWidget {
  final VolunteerTask task;
  final bool compact;

  const TaskCard({super.key, required this.task, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final uc = _urgCol(task.urgency);
    final sc = _statusCol(task.status);

    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(width: 4, height: 32, decoration: BoxDecoration(color: uc, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${task.estimatedPeopleAffected} people · ${task.needType}', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
            child: Text(task.status.name.toUpperCase(), style: TextStyle(color: sc, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }

    return Container(
      decoration: AppDecorations.glassCard,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: uc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(task.urgency.toUpperCase(), style: TextStyle(color: uc, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(task.status.name.toUpperCase(), style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 2),
              Text(task.ward, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3)),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.groups, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text('${task.estimatedPeopleAffected} people', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(width: 12),
              ...task.sdgTags.take(2).map((sdg) => Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                child: Text('SDG $sdg', style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }

  Color _urgCol(String u) => switch (u) {
    'Critical' => AppColors.urgencyCritical, 'High' => AppColors.urgencyHigh,
    'Medium' => AppColors.urgencyMedium, _ => AppColors.urgencyLow,
  };

  Color _statusCol(TaskStatus s) => switch (s) {
    TaskStatus.open => AppColors.warning, TaskStatus.assigned => AppColors.info,
    TaskStatus.inProgress => AppColors.primary, TaskStatus.completed => AppColors.success,
    TaskStatus.cancelled => AppColors.textMuted,
  };
}
