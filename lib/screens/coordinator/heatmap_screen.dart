import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../../config/theme.dart';
import '../../providers/app_state.dart';
import '../../models/task_model.dart';
import '../../widgets/task_card.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        // Group tasks by ward
        final wardGroups = <String, List<VolunteerTask>>{};
        for (final task in state.tasks) {
          wardGroups.putIfAbsent(task.ward, () => []).add(task);
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: FadeInDown(
                duration: const Duration(milliseconds: 600),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need Heatmap',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Real-time urgency visualization by ward',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Map placeholder with heatmap visualization
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FadeInUp(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 200),
                  child: Container(
                    height: 260,
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.glassBorder, width: 0.5),
                    ),
                    child: Stack(
                      children: [
                        // Map background with grid lines
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: CustomPaint(
                            size: const Size(double.infinity, 260),
                            painter: _MapGridPainter(),
                          ),
                        ),
                        // Heatmap dots
                        ...state.tasks.asMap().entries.map((entry) {
                          final task = entry.value;
                          final color = _getUrgencyColor(task.urgency);
                          // Position based on lat/lng offsets
                          final xPercent =
                              ((task.longitude - 72.82) / 0.12).clamp(0.1, 0.9);
                          final yPercent =
                              ((19.14 - task.latitude) / 0.12).clamp(0.1, 0.9);

                          return Positioned(
                            left: xPercent * 320,
                            top: yPercent * 220 + 10,
                            child: FadeIn(
                              duration: const Duration(milliseconds: 800),
                              delay: Duration(milliseconds: 300 + entry.key * 150),
                              child: _buildMapDot(task, color),
                            ),
                          );
                        }),

                        // Legend
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.bgPrimary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildLegendItem('Critical', AppColors.urgencyCritical),
                                _buildLegendItem('High', AppColors.urgencyHigh),
                                _buildLegendItem('Medium', AppColors.urgencyMedium),
                                _buildLegendItem('Low', AppColors.urgencyLow),
                              ],
                            ),
                          ),
                        ),

                        // Label overlay
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.bgPrimary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: AppColors.glassBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map, size: 14, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Mumbai Metropolitan',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Filter chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FadeInLeft(
                  duration: const Duration(milliseconds: 600),
                  delay: const Duration(milliseconds: 300),
                  child: Wrap(
                    spacing: 8,
                    children: ['All', 'Critical', 'High', 'Medium', 'Low']
                        .map((filter) => ChoiceChip(
                              label: Text(filter),
                              selected: _selectedFilter == filter,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedFilter = filter;
                                });
                              },
                              selectedColor:
                                  AppColors.primary.withValues(alpha: 0.3),
                              labelStyle: TextStyle(
                                color: _selectedFilter == filter
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),

            // Ward breakdown
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Coverage by Ward',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final wardEntry = wardGroups.entries.toList()[index];
                    final tasks = wardEntry.value;
                    final filteredTasks = _selectedFilter == 'All'
                        ? tasks
                        : tasks
                            .where((t) => t.urgency == _selectedFilter)
                            .toList();

                    if (filteredTasks.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final openCount = filteredTasks
                        .where((t) => t.status == TaskStatus.open)
                        .length;
                    final totalPeople = filteredTasks.fold<int>(
                        0, (sum, t) => sum + t.estimatedPeopleAffected);
                    final maxUrgency = _getMaxUrgency(filteredTasks);

                    return FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: Duration(milliseconds: 100 * index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: AppDecorations.glassCard,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            childrenPadding: const EdgeInsets.fromLTRB(
                                16, 0, 16, 12),
                            leading: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getUrgencyColor(maxUrgency),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _getUrgencyColor(maxUrgency)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            title: Text(
                              wardEntry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '$openCount open · ${filteredTasks.length} total · $totalPeople people',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            children: filteredTasks
                                .map(
                                    (task) => TaskCard(task: task, compact: true))
                                .toList(),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: wardGroups.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMapDot(VolunteerTask task, Color color) {
    return Tooltip(
      message: '${task.ward}: ${task.title}',
      child: Container(
        width: 28 + (task.estimatedPeopleAffected / 100).clamp(0, 20),
        height: 28 + (task.estimatedPeopleAffected / 100).clamp(0, 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Color _getUrgencyColor(String urgency) {
    switch (urgency) {
      case 'Critical':
        return AppColors.urgencyCritical;
      case 'High':
        return AppColors.urgencyHigh;
      case 'Medium':
        return AppColors.urgencyMedium;
      default:
        return AppColors.urgencyLow;
    }
  }

  String _getMaxUrgency(List<VolunteerTask> tasks) {
    const priority = ['Critical', 'High', 'Medium', 'Low'];
    for (final level in priority) {
      if (tasks.any((t) => t.urgency == level)) return level;
    }
    return 'Low';
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.glassBorder.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Draw grid
    for (var i = 0; i < 12; i++) {
      final x = i * size.width / 11;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var i = 0; i < 8; i++) {
      final y = i * size.height / 7;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw some "road" lines
    final roadPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.1)
      ..strokeWidth = 2;

    canvas.drawLine(
        Offset(size.width * 0.3, 0),
        Offset(size.width * 0.4, size.height),
        roadPaint);
    canvas.drawLine(
        Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.4),
        roadPaint);
    canvas.drawLine(
        Offset(size.width * 0.6, 0),
        Offset(size.width * 0.7, size.height),
        roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
