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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(profile.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHero(theme),
            const SizedBox(height: AppSpacing.lg),
            _section(theme, 'Organizations', Icons.business_rounded),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppDecorations.cardSubtle,
              child: Text(profile.activeOrganizationsLabel, style: theme.textTheme.bodyMedium),
            ),
            if (profile.keywords.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _section(theme, 'Keywords', Icons.label_outline_rounded),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: profile.keywords.take(12).map((k) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                    decoration: AppDecorations.tagAccent(color: AppColors.primary),
                    child: Text(
                      k,
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _section(theme, 'Need signals', Icons.warning_amber_rounded),
            const SizedBox(height: AppSpacing.sm),
            ...profile.needs.map((n) => _buildNeedCard(theme, n)),
            if (profile.coverageGaps.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _section(theme, 'Knowledge gaps', Icons.help_outline_rounded),
              const SizedBox(height: AppSpacing.sm),
              ...profile.coverageGaps.map((g) => _buildBulletRow(
                    theme,
                    title: (g['reason'] ?? g['community_name'] ?? 'Gap').toString(),
                    subtitle: g['detail']?.toString(),
                    icon: Icons.info_outline_rounded,
                  )),
            ],
            if (profile.similarity.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _section(theme, 'Similar communities', Icons.group_work_outlined),
              const SizedBox(height: AppSpacing.sm),
              ...profile.similarity.map((s) => _buildBulletRow(
                    theme,
                    title: (s['community_name'] ?? s['id']).toString(),
                    trailing: s['score'] != null
                        ? '${((s['score'] as num).toDouble() * 100).round()}% match'
                        : null,
                    icon: Icons.diversity_3_rounded,
                  )),
            ],
            if (reportUrl.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(reportUrl);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Open source evidence'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF3B62F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xlR,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Community profile',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 6),
          Text(
            profile.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${profile.region} · ${profile.district} · ${profile.block}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _heroChip(theme, Icons.history_rounded, 'Verified', profile.lastVerifiedLabel),
              _heroChip(
                theme,
                Icons.bolt_rounded,
                'Status',
                profile.isStale ? 'Stale signal' : 'Active',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(ThemeData theme, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
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

  Widget _buildNeedCard(ThemeData theme, dynamic n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: AppDecorations.baseCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.needType.replaceAll('_', ' ').toString(), style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _statTag(theme, 'Acute', '${(n.acuteScore * 100).round()}%', AppColors.urgencyHigh),
                _statTag(theme, 'Chronic', '${(n.chronicScore * 100).round()}%', AppColors.warning),
                _statTag(theme, 'Confidence', '${(n.confidence * 100).round()}%', AppColors.primary),
              ],
            ),
            if (n.evidenceQuotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ...n.evidenceQuotes.take(3).map<Widget>((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '“$q”',
                      style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statTag(ThemeData theme, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletRow(
    ThemeData theme, {
    required String title,
    String? subtitle,
    String? trailing,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: AppDecorations.cardSubtle,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
