import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Detail for a unified pipeline “real-time event” row (structured map from API).
class PipelineEventDetailScreen extends StatelessWidget {
  const PipelineEventDetailScreen({super.key, required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = event.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(event['community_name']?.toString() ?? 'Pipeline event'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            (event['need_type'] ?? event['needType'] ?? 'need').toString().replaceAll('_', ' '),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: AppDecorations.contentBlock,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(e.key, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.primary)),
                    const SizedBox(height: 4),
                    SelectableText(
                      _formatValue(e.value),
                      style: theme.textTheme.bodyMedium,
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
    if (v == null) return '';
    if (v is Map) return v.toString();
    if (v is List) return v.join(', ');
    return v.toString();
  }
}
