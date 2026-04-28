import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../models/community_graph_models.dart';

/// Full view for a single community from the graph / recent needs APIs.
class CommunityDetailScreen extends StatelessWidget {
  const CommunityDetailScreen({super.key, required this.profile});

  final CommunityProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reportUrl =
        (profile.report['source_url'] ?? profile.report['pdf_url'] ?? profile.provenance['source_url'] ?? '')
            .toString();

    return Scaffold(
      appBar: AppBar(title: Text(profile.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${profile.region} · ${profile.district} · ${profile.block}',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _chip(Icons.history, 'Last verified', profile.lastVerifiedLabel),
                _chip(Icons.warning_amber_outlined, 'Status', profile.isStale ? 'Stale signal' : 'Active'),
              ],
            ),
            const SizedBox(height: 24),
            Text('Organizations', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(profile.activeOrganizationsLabel, style: theme.textTheme.bodyLarge),
            if (profile.keywords.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Keywords', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: profile.keywords
                    .take(12)
                    .map(
                      (k) => Padding(
                        padding: const EdgeInsets.only(right: 6, bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(k, style: theme.textTheme.bodySmall),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            Text('Needs signals', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...profile.needs.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: AppDecorations.contentBlock,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.needType.replaceAll('_', ' '), style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Acute ${(n.acuteScore * 100).round()}% · Chronic ${(n.chronicScore * 100).round()}% · Confidence ${(n.confidence * 100).round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      if (n.evidenceQuotes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...n.evidenceQuotes.take(3).map((q) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('“$q”', style: theme.textTheme.bodySmall),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (profile.coverageGaps.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Knowledge gaps', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...profile.coverageGaps.map(
                (g) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline, size: 20),
                  title: Text((g['reason'] ?? g['community_name'] ?? 'Gap').toString()),
                  subtitle: g['detail'] != null ? Text(g['detail'].toString()) : null,
                ),
              ),
            ],
            if (profile.similarity.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Similar communities', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...profile.similarity.map(
                (s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text((s['community_name'] ?? s['id']).toString()),
                  trailing: s['score'] != null
                      ? Text('${((s['score'] as num).toDouble() * 100).round()}% match')
                      : null,
                ),
              ),
            ],
            if (reportUrl.isNotEmpty) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(reportUrl);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Open source evidence'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: AppDecorations.contentBlock,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
