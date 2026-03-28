import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    return Stack(
      children: [
        // Simulated clean map base
        Container(color: AppColors.surfaceContainerHigh),
        
        // Custom softer heatmap painter
        CustomPaint(
          size: Size.infinite,
          painter: SimpleHeatmapPainter(state.tasks, _selectedFilter),
        ),
        
        // Floating top header with filters (Glassmorphism / Frosted Organicism)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              boxShadow: AppDecorations.ambientShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Focus Areas', style: theme.textTheme.displayMedium),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Critical', 'High', 'Medium', 'Low'].map((level) {
                      final active = _selectedFilter == level;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedFilter = level),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: active ? AppDecorations.activeChip : AppDecorations.inactiveChip,
                            child: Text(
                              level, 
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: active ? AppColors.onTertiary : AppColors.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Location breakdown slide up panel
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: AppDecorations.baseCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.location_city, color: AppColors.onPrimary, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Text('Location Breakdown', style: theme.textTheme.headlineLarge),
                    const Spacer(),
                    const Icon(Icons.expand_more, color: AppColors.outlineVariant),
                  ],
                ),
                const SizedBox(height: 24),
                _bWard('Ward 15', 'Critical Flooding', 650, AppColors.urgencyCritical),
                const SizedBox(height: 16),
                _bWard('Ward 22', 'Food Shortage', 320, AppColors.urgencyHigh),
                const SizedBox(height: 16),
                _bWard('Ward 08', 'Medical Support', 150, AppColors.urgencyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bWard(String name, String desc, int people, Color color) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge),
              Text(desc, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        Text('$people', style: theme.textTheme.headlineSmall),
        const SizedBox(width: 4),
        const Icon(Icons.groups, size: 16, color: AppColors.outlineVariant),
      ],
    );
  }
}

class SimpleHeatmapPainter extends CustomPainter {
  final List tasks;
  final String filter;
  SimpleHeatmapPainter(this.tasks, this.filter);

  @override
  void paint(Canvas canvas, Size size) {
    // Simple mock points rendering based on screen size
    final paints = <String, Paint>{
      'Critical': Paint()..color = AppColors.urgencyCritical.withValues(alpha: 0.6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
      'High': Paint()..color = AppColors.urgencyHigh.withValues(alpha: 0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      'Medium': Paint()..color = AppColors.urgencyMedium.withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      'Low': Paint()..color = AppColors.urgencyLow.withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    };

    // Draw some mock clusters
    if (filter == 'All' || filter == 'Critical') {
      canvas.drawCircle(Offset(size.width * 0.4, size.height * 0.5), 60, paints['Critical']!);
      canvas.drawCircle(Offset(size.width * 0.45, size.height * 0.45), 40, paints['Critical']!);
    }
    if (filter == 'All' || filter == 'High') {
      canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.3), 50, paints['High']!);
    }
    if (filter == 'All' || filter == 'Medium') {
      canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.8), 45, paints['Medium']!);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
