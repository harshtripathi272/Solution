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
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sc.withValues(alpha: 0.3), width: 1),
        boxShadow: [BoxShadow(color: sc.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.warning_amber_rounded, color: sc, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert.severity.name.toUpperCase(),
                style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            Text(alert.affectedArea, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ])),
        ]),
        const SizedBox(height: 10),
        Text(alert.prediction, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
        const Spacer(),
        Row(children: [
          Icon(Icons.schedule, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('Predicted: ${DateFormat('MMM dd').format(alert.predictedDate)}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text('AI Forecast', style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.w600)),
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
