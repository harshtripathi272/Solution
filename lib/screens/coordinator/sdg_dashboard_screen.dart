import 'package:flutter/material.dart';
import '../../config/theme.dart';

class SDGDashboardScreen extends StatelessWidget {
  const SDGDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Social Impact', style: theme.textTheme.displayMedium),
          const SizedBox(height: 12),
          Text('Tracking contributions towards UN Sustainable Development Goals',
              style: theme.textTheme.bodyLarge),
          
          const SizedBox(height: 32),
          
          // Overall Metric Card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: AppDecorations.baseCard.copyWith(color: AppColors.primaryContainer),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('12,450', style: theme.textTheme.displayLarge?.copyWith(color: AppColors.onPrimary)),
                    const SizedBox(height: 8),
                    Text('Total Lives Improved', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onPrimaryContainer)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerLowest.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.public, color: AppColors.onPrimary, size: 32),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 48),
          
          Text('Key Goals Affected', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 24),
          
          // Softly styled list of SDGs
          _sdgRow(context, '01', 'No Poverty', 1240, AppColors.tertiary),
          const SizedBox(height: 16),
          _sdgRow(context, '02', 'Zero Hunger', 3420, AppColors.warning),
          const SizedBox(height: 16),
          _sdgRow(context, '03', 'Good Health & Well-being', 850, AppColors.success),
          const SizedBox(height: 16),
          _sdgRow(context, '04', 'Quality Education', 210, AppColors.info),
          
          const SizedBox(height: 48),
          
          Container(
            padding: const EdgeInsets.all(32),
            decoration: AppDecorations.contentBlock,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Volunteer Efficacy', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricCircle(context, '85%', 'Task Completion'),
                    _metricCircle(context, '14m', 'Avg. Response'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _sdgRow(BuildContext context, String num, String name, int count, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppDecorations.baseCard,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Text(num, style: theme.textTheme.headlineSmall?.copyWith(color: color)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('$count interventions', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.outlineVariant),
        ],
      ),
    );
  }
  
  Widget _metricCircle(BuildContext context, String stat, String label) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            shape: BoxShape.circle,
            boxShadow: AppDecorations.ambientShadow,
          ),
          child: Center(
            child: Text(stat, style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.primary)),
          ),
        ),
        const SizedBox(height: 16),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
