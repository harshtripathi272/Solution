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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppDecorations.ambientShadow,
        border: Border.all(color: sc.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.warning_rounded, color: sc, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert.severity.name.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(color: sc, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(alert.affectedArea, style: theme.textTheme.titleLarge),
          ])),
        ]),
        const SizedBox(height: 20),
        Text(alert.prediction, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
        const Spacer(),
        Row(children: [
          Icon(Icons.schedule, size: 16, color: AppColors.outlineVariant),
          const SizedBox(width: 8),
          Text('Predicted: ${DateFormat('MMM dd').format(alert.predictedDate)}',
              style: theme.textTheme.bodyMedium),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Text('AI Forecast', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurfaceVariant)),
          ),
        ]),
      ]),
    );
  }

  Color _sevCol(AlertSeverity s) => switch (s) {
    AlertSeverity.critical => AppColors.urgencyCritical,
    AlertSeverity.high => AppColors.urgencyHigh,
    AlertSeverity.moderate => AppColors.urgencyMedium,
    AlertSeverity.low => AppColors.urgencyLow,
  };
}
