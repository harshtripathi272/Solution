import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Detail for a unified pipeline "real-time event" row (structured map from API).
class PipelineEventDetailScreen extends StatelessWidget {
  const PipelineEventDetailScreen({super.key, required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = event.entries.toList();
    final needTypeRaw = (event['need_type'] ?? event['needType'] ?? 'need').toString();
    final severity = (event['severity'] ?? 'moderate').toString();
    final severityColor = _severityColor(severity);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(event['community_name']?.toString() ?? 'Pipeline event'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [severityColor.withValues(alpha: 0.92), severityColor.withValues(alpha: 0.65)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: AppRadius.xlR,
              boxShadow: [
                BoxShadow(
                  color: severityColor.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: AppRadius.mdR,
                      ),
                      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: AppRadius.pillR,
                      ),
                      child: Text(
                        severity.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  needTypeRaw.replaceAll('_', ' ').toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  event['community_name']?.toString() ?? 'Pipeline event',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Raw fields', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: AppDecorations.cardSubtle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      e.key,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _formatValue(e.value),
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(Object? v) {
    if (v == null) return '—';
    if (v is Map) return v.toString();
    if (v is List) return v.join(', ');
    return v.toString();
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'red':
        return AppColors.urgencyCritical;
      case 'high':
      case 'orange':
        return AppColors.urgencyHigh;
      case 'moderate':
      case 'yellow':
        return AppColors.urgencyMedium;
      default:
        return AppColors.primary;
    }
  }
}
