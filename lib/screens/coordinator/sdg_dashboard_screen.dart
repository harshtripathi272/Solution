import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:animate_do/animate_do.dart';
import '../../config/theme.dart';
import '../../providers/app_state.dart';

class SDGDashboardScreen extends StatelessWidget {
  const SDGDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final metrics = state.impactMetrics;
        final sdgBreakdown =
            metrics['sdgBreakdown'] as Map<String, dynamic>? ?? {};
        final wardImpact =
            metrics['wardImpact'] as Map<String, dynamic>? ?? {};
        final weeklyTrend =
            (metrics['weeklyTrend'] as List<dynamic>?)?.cast<int>() ?? [];

        return CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: FadeInDown(
                duration: const Duration(milliseconds: 600),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Impact Dashboard',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Measuring real community outcomes aligned with UN SDGs',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Impact summary cards
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FadeInUp(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'TOTAL IMPACT',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildImpactStat(
                              '${metrics['totalVolunteerHours'] ?? 0}',
                              'Volunteer\nHours',
                              Icons.schedule,
                            ),
                            _buildDivider(),
                            _buildImpactStat(
                              '${metrics['totalTasksCompleted'] ?? 0}',
                              'Tasks\nCompleted',
                              Icons.task_alt,
                            ),
                            _buildDivider(),
                            _buildImpactStat(
                              _formatNumber(
                                  metrics['totalPeopleServed'] ?? 0),
                              'People\nServed',
                              Icons.groups,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Weekly trend chart
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FadeInUp(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 300),
                  child: Container(
                    decoration: AppDecorations.glassCard,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tasks Completed This Week',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 180,
                          child: weeklyTrend.isNotEmpty
                              ? BarChart(
                                  BarChartData(
                                    alignment:
                                        BarChartAlignment.spaceAround,
                                    barGroups: weeklyTrend
                                        .asMap()
                                        .entries
                                        .map((e) => BarChartGroupData(
                                              x: e.key,
                                              barRods: [
                                                BarChartRodData(
                                                  toY: e.value.toDouble(),
                                                  gradient:
                                                      AppDecorations.primaryGradient,
                                                  width: 20,
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                    top: Radius.circular(6),
                                                  ),
                                                ),
                                              ],
                                            ))
                                        .toList(),
                                    titlesData: FlTitlesData(
                                      leftTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: false)),
                                      rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: false)),
                                      topTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: false)),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, meta) {
                                            const days = [
                                              'Mon',
                                              'Tue',
                                              'Wed',
                                              'Thu',
                                              'Fri',
                                              'Sat',
                                              'Sun'
                                            ];
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                      top: 8),
                                              child: Text(
                                                days[value.toInt() %
                                                    days.length],
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textMuted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    gridData: const FlGridData(show: false),
                                    borderData:
                                        FlBorderData(show: false),
                                    barTouchData: BarTouchData(
                                      touchTooltipData:
                                          BarTouchTooltipData(
                                        getTooltipColor: (_) =>
                                            AppColors.bgCard,
                                        getTooltipItem: (group, groupIndex,
                                            rod, rodIndex) {
                                          return BarTooltipItem(
                                            '${rod.toY.toInt()} tasks',
                                            const TextStyle(
                                              color:
                                                  AppColors.textPrimary,
                                              fontSize: 12,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Text('No data yet')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // SDG Breakdown
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: FadeInLeft(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 400),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.flag,
                                size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              'UN SDG ALIGNMENT',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = sdgBreakdown.entries.toList()[index];
                    final data = entry.value as Map<String, dynamic>;
                    final colors = [
                      AppColors.sdg2,
                      AppColors.sdg3,
                      AppColors.sdg4,
                      AppColors.sdg6,
                      const Color(0xFFF99D26),
                      AppColors.sdg1,
                    ];
                    return FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: Duration(milliseconds: 100 * index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: AppDecorations.glassCard,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors[index % colors.length],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${data['tasks']} tasks · ${data['hours']} hrs · ${_formatNumber(data['people'])} people',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${data['hours']}h',
                              style: TextStyle(
                                color: colors[index % colors.length],
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: sdgBreakdown.length,
                ),
              ),
            ),

            // Ward impact (before/after)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: FadeInLeft(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 500),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.trending_down,
                                size: 14, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              'BEFORE / AFTER BY WARD',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = wardImpact.entries.toList()[index];
                    final data = entry.value as Map<String, dynamic>;
                    return FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: Duration(milliseconds: 100 * index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: AppDecorations.glassCard,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _buildBeforeAfterChip(
                                        'Before',
                                        '${data['reportsBefore']} reports',
                                        AppColors.error,
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward,
                                          size: 14,
                                          color: AppColors.textMuted),
                                      const SizedBox(width: 8),
                                      _buildBeforeAfterChip(
                                        'After',
                                        '${data['reportsAfter']} reports',
                                        AppColors.success,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.success
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '↓ ${data['reduction']}%',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: wardImpact.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImpactStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 50,
      color: Colors.white24,
    );
  }

  Widget _buildBeforeAfterChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style:
                TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _formatNumber(dynamic n) {
    final num value = n is num ? n : 0;
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }
}
