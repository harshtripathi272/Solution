import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/crisis_alert_model.dart';
import 'package:intl/intl.dart';

class CrisisAlertCard extends StatelessWidget {
  final CrisisAlert alert;

  const CrisisAlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final sc = _sevCol(alert.severity);
    final theme = Theme.of(context);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.xlR,
        boxShadow: AppElevation.soft,
        border: Border.all(color: sc.withValues(alpha: 0.18), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [sc.withValues(alpha: 0.18), sc.withValues(alpha: 0.08)],
                  ),
                  borderRadius: AppRadius.lgR,
                ),
                child: Icon(Icons.warning_rounded, color: sc, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.severity.name.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: sc,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.affectedArea,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            alert.prediction,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const Spacer(),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM dd').format(alert.predictedDate),
                style: theme.textTheme.labelMedium,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: AppRadius.pillR,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'AI Forecast',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _sevCol(AlertSeverity s) => switch (s) {
        AlertSeverity.critical => AppColors.urgencyCritical,
        AlertSeverity.high => AppColors.urgencyHigh,
        AlertSeverity.moderate => AppColors.urgencyMedium,
        AlertSeverity.low => AppColors.urgencyLow,
      };
}
