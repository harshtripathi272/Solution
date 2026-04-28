import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

    final sortedSdgs = sdgCounts.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Impact', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('SDG dashboard', style: theme.textTheme.headlineLarge),
              const SizedBox(height: AppSpacing.lg),
              _buildHeroStat(theme, livesImproved, completedCount, totalCount).animate().fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(child: _metricTile(theme, '$completionRate%', 'Completion', AppColors.primary, Icons.donut_small_rounded)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _metricTile(theme, '${state.criticalTaskCount}', 'Critical', AppColors.error, Icons.priority_high_rounded)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _metricTile(theme, '${state.reportCount}', 'Reports', AppColors.secondary, Icons.summarize_rounded)),
                ],
              ).animate(delay: 80.ms).fadeIn(duration: AppMotion.standard),
              const SizedBox(height: AppSpacing.xl),
              Text('SDG breakdown', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              if (sortedSdgs.isEmpty)
                _buildEmptyState(theme)
              else
                ...sortedSdgs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final tag = entry.value;
                  final name = AppConstants.sdgGoals[tag] ?? 'SDG $tag';
                  final count = sdgCounts[tag] ?? 0;
                  final people = sdgPeople[tag] ?? 0;
                  return _sdgRow(
                    context,
                    theme,
                    tag.toString().padLeft(2, '0'),
                    name,
                    count,
                    people,
                    () => _showTasksForSDGGoal(context, state, tag, name),
                  ).animate(delay: (i * 40).ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0);
                }),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────── pieces
  Widget _buildHeroStat(ThemeData theme, int lives, int completed, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF3B62F0), AppColors.secondary],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xlR,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'People reached',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_formatNumber(lives), style: AppTypography.metric(size: 56, color: Colors.white)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: AppRadius.pillR,
            ),
            child: Text(
              '$completed of $total tasks completed',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(ThemeData theme, String value, String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.baseCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.mdR,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(value, style: AppTypography.metric(size: 24, color: color)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppDecorations.cardSubtle,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.analytics_outlined, size: 28, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('No SDG data yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Impact metrics will populate as tasks are created and completed.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  void _showTasksForSDGGoal(BuildContext context, AppState state, int tag, String name) {
    final related = state.tasks.where((t) => t.sdgTags.contains(tag)).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final h = MediaQuery.of(ctx).size.height * 0.5;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: AppRadius.pillR,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: AppRadius.mdR,
                        ),
                        child: Center(
                          child: Text(
                            tag.toString().padLeft(2, '0'),
                            style: AppTypography.metric(size: 18, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: theme.textTheme.titleMedium),
                            Text(
                              '${related.length} task${related.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: related.isEmpty
                        ? Center(
                            child: Text(
                              'No tasks mapped to this goal yet.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            itemCount: related.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (c, i) {
                              final t = related[i];
                              return Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: AppDecorations.cardSubtle,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.title, style: theme.textTheme.titleSmall),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${t.status.name} · ${t.needType}',
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: AppDecorations.baseCard,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF3B62F0)],
                  ),
                  borderRadius: AppRadius.mdR,
                ),
                child: Center(
                  child: Text(
                    number,
                    style: AppTypography.metric(size: 17, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '$tasks task${tasks == 1 ? '' : 's'} · ${_formatNumber(people)} reached',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}
