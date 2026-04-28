import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/app_state.dart';

class SDGDashboardScreen extends StatelessWidget {
  const SDGDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final metrics = state.impactMetrics;

    final livesImproved = metrics['livesImproved'] as int? ?? 0;
    final completedCount = metrics['completedCount'] as int? ?? 0;
    final totalCount = metrics['totalCount'] as int? ?? 0;
    final completionRate = metrics['completionRate'] as int? ?? 0;
    final sdgCounts = (metrics['sdgCounts'] as Map<int, int>?) ?? {};
    final sdgPeople = (metrics['sdgPeople'] as Map<int, int>?) ?? {};

    // Build SDG rows from real data
    final sdgRows = <Widget>[];
    final sortedSdgs = sdgCounts.keys.toList()..sort();
    for (final tag in sortedSdgs) {
      final name = AppConstants.sdgGoals[tag] ?? 'SDG $tag';
      final count = sdgCounts[tag] ?? 0;
      final people = sdgPeople[tag] ?? 0;
      sdgRows.add(
        _sdgRow(
          context,
          theme,
          tag.toString().padLeft(2, '0'),
          name,
          count,
          people,
          () => _showTasksForSDGGoal(context, state, tag, name),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Impact Dashboard')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero stat
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: AppDecorations.baseCard,
              child: Column(
                children: [
                  Text(
                    _formatNumber(livesImproved),
                    style: theme.textTheme.displayLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total People Reached',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$completedCount of $totalCount tasks completed',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Metric circles
            Row(
              children: [
                _metricCircle(theme, '$completionRate%', 'Task Completion'),
                const SizedBox(width: 16),
                _metricCircle(theme, '${state.criticalTaskCount}', 'Critical Open'),
                const SizedBox(width: 16),
                _metricCircle(theme, '${state.reportCount}', 'Field Reports'),
              ],
            ),
            const SizedBox(height: 40),

            // SDG breakdown
            Text('SDG Impact Breakdown', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (sdgRows.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: AppDecorations.contentBlock,
                child: Column(
                  children: [
                    Icon(Icons.analytics_outlined, size: 48, color: AppColors.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No SDG data yet',
                      style: theme.textTheme.titleMedium?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Impact data will populate as tasks are created and completed.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...sdgRows,
          ],
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  Widget _metricCircle(ThemeData theme, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: AppDecorations.baseCard,
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showTasksForSDGGoal(BuildContext context, AppState state, int tag, String name) {
    final related = state.tasks.where((t) => t.sdgTags.contains(tag)).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final h = MediaQuery.of(ctx).size.height * 0.46;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SDG $tag · $name', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '${related.length} task(s)',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: related.isEmpty
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No tasks mapped to this goal yet.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: related.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (c, i) {
                              final t = related[i];
                              return ListTile(
                                title: Text(t.title),
                                subtitle: Text(
                                  '${t.status.name} · ${t.needType}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sdgRow(
    BuildContext context,
    ThemeData theme,
    String number,
    String name,
    int tasks,
    int people,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: AppDecorations.contentBlock,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  number,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '$tasks tasks · ${_formatNumber(people)} people reached',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.outlineVariant),
          ],
        ),
      ),
    );
  }
}
