import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/task_model.dart';

class TaskCard extends StatelessWidget {
  final VolunteerTask task;
  final bool compact;

  const TaskCard({super.key, required this.task, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusCol(task.status);
    final urgencyColor = _urgencyCol(task.urgency);
    final theme = Theme.of(context);

    if (compact) return _buildCompact(theme, statusColor);
    return _buildFull(theme, statusColor, urgencyColor);
  }

  // ───────────────────────────────────────────── compact
  Widget _buildCompact(ThemeData theme, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.cardSubtle,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: AppRadius.smR,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.estimatedPeopleAffected} people · ${task.ward}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _statusPill(theme, statusColor),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────── full
  Widget _buildFull(ThemeData theme, Color statusColor, Color urgencyColor) {
    return Container(
      decoration: AppDecorations.baseCard,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: urgency + status + match score + distance/ward
          Row(
            children: [
              _badge(theme,
                  label: task.urgency.toUpperCase(),
                  color: urgencyColor,
                  filled: false),
              const SizedBox(width: AppSpacing.sm),
              _statusPill(theme, statusColor),
              if (task.matchScore != null && task.matchScore! > 0) ...[
                const SizedBox(width: AppSpacing.sm),
                _matchPill(theme),
              ],
              const Spacer(),
              if (task.distanceKm != null) ...[
                Icon(Icons.straighten_rounded, size: 14, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${task.distanceKm!.toStringAsFixed(1)} km',
                  style: theme.textTheme.labelMedium?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Title + description
          Text(task.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            task.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Bottom meta strip
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  task.ward,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(Icons.groups_rounded, size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${task.estimatedPeopleAffected}',
                style: theme.textTheme.labelMedium?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const Spacer(),
              if (task.requiredSkills.isNotEmpty)
                ..._skillTags(theme)
              else
                ..._sdgTags(theme),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────── pieces
  Widget _statusPill(ThemeData theme, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillR,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            task.status.name.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme,
      {required String label, required Color color, bool filled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pillR,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: filled ? AppColors.onPrimary : color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _matchPill(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.14), AppColors.secondary.withValues(alpha: 0.10)],
        ),
        borderRadius: AppRadius.pillR,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            '${(task.matchScore! * 100).round()}% match',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _skillTags(ThemeData theme) {
    final visible = task.requiredSkills.take(2).toList();
    return [
      ...visible.map((s) => Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: AppDecorations.tagAccent(color: AppColors.tertiary),
            child: Text(
              s,
              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.tertiary),
            ),
          )),
      if (task.requiredSkills.length > 2)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            '+${task.requiredSkills.length - 2}',
            style: theme.textTheme.labelSmall,
          ),
        ),
    ];
  }

  List<Widget> _sdgTags(ThemeData theme) {
    return task.sdgTags.take(2).map((sdg) {
      return Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: AppDecorations.tagAccent(color: AppColors.secondary),
        child: Text(
          'SDG $sdg',
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary),
        ),
      );
    }).toList();
  }

  Color _statusCol(TaskStatus s) => switch (s) {
        TaskStatus.open => AppColors.warning,
        TaskStatus.assigned => AppColors.info,
        TaskStatus.inProgress => AppColors.primary,
        TaskStatus.completed => AppColors.success,
        TaskStatus.cancelled => AppColors.onSurfaceVariant,
      };

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
        return AppColors.onSurfaceVariant;
    }
  }
}
