import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../config/theme.dart';
import '../../models/task_model.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/task_card.dart';
import '../../widgets/crisis_alert_card.dart';
import '../../services/community_graph_api_service.dart';
import '../../models/community_graph_models.dart';
import 'pipeline_event_detail_screen.dart';
import 'community_detail_screen.dart';
import 'volunteer_area_task_detail_screen.dart';

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard> {
  late CommunityGraphApiService _apiService;
  Map<String, dynamic>? _recentNeeds;
  CommunityGraphOverview? _overviewData;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _apiService = CommunityGraphApiService();
    _loadRecentNeeds();
  }

  Future<void> _loadRecentNeeds() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _apiService.fetchRecentNeeds(limit: 10, hours: 48),
        _apiService.fetchOverview(limit: 6),
      ]);
      
      if (!mounted) return;
      setState(() {
        _recentNeeds = results[0] as Map<String, dynamic>;
        _overviewData = results[1] as CommunityGraphOverview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.isLoading) return const Center(child: CircularProgressIndicator());

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loading) const Padding(
                padding: EdgeInsets.fromLTRB(32, 0, 32, 0),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      'Could not refresh community snapshots: $_error',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
                    ),
                  ),
                ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Here is the latest snapshot of your community.',
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    Text('Overview', style: theme.textTheme.displayMedium),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: StatCard(
                        title: 'Open Needs',
                        value: '${state.tasks.where((t) => t.status == TaskStatus.open).length}',
                        icon: Icons.assignment_late,
                        color: AppColors.warning,
                        subtitle: 'Requires attention',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StatCard(
                        title: 'Active Tasks',
                        value: '${state.activeTasks.length}',
                        icon: Icons.people,
                        color: AppColors.primary,
                        subtitle: '${state.completedTasks.length} completed',
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Crisis Alerts (derived from critical tasks)
              if (state.derivedCrisisAlerts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      Text('Critical Alerts', style: theme.textTheme.headlineLarge),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: Text('${state.derivedCrisisAlerts.length} Active', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 240,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    scrollDirection: Axis.horizontal,
                    itemCount: state.derivedCrisisAlerts.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 24),
                    itemBuilder: (context, index) => CrisisAlertCard(alert: state.derivedCrisisAlerts[index]),
                  ),
                ),
                const SizedBox(height: 64),
              ],
              
              // Real-time Events Section
              if (_recentNeeds != null && _recentNeeds!['events'] != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      Text('Real-Time Events', style: theme.textTheme.headlineLarge),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: Text(
                          '${_recentNeeds!['total_events'] ?? 0} Events',
                          style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ...(_recentNeeds!['events'] as List).take(5).map((event) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PipelineEventDetailScreen(event: Map<String, dynamic>.from(event as Map)),
                          ),
                        );
                      },
                      child: _buildEventCard(context, theme, event as Map<String, dynamic>),
                    ),
                  );
                }),
                const SizedBox(height: 32),
              ],
              
              // Recent Needs (Community Profiles)
              if (_overviewData != null && _overviewData!.profiles.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text('Recent Needs', style: theme.textTheme.headlineLarge),
                ),
                const SizedBox(height: 24),
                
                ..._overviewData!.profiles.take(5).map((profile) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 32, right: 32),
                    child: _buildCommunityRequirementCard(context, theme, profile),
                  );
                }),
                const SizedBox(height: 48),
              ] else ...[
                // Fallback to task components if no profiles
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text('Recent Needs', style: theme.textTheme.headlineLarge),
                ),
                const SizedBox(height: 24),
                ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.tasks.take(5).length,
                  itemBuilder: (context, index) {
                    final t = state.tasks[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => VolunteerAreaTaskDetailScreen(task: t),
                            ),
                          );
                        },
                        child: TaskCard(task: t),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 48),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommunityRequirementCard(BuildContext context, ThemeData theme, CommunityProfile profile) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CommunityDetailScreen(profile: profile),
          ),
        );
      },
      child: Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ]
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Last Reported: ${profile.lastVerifiedLabel}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.outlineVariant),
              ],
            ),
            const SizedBox(height: 12),
            Text('Sources: ${profile.activeOrganizationsLabel}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (profile.needs.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profile.needs.take(3).map((need) {
                   final needName = need.needType.replaceAll('_', ' ');
                   return Container(
                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                     decoration: BoxDecoration(
                       color: AppColors.primary.withValues(alpha: 0.1),
                       borderRadius: BorderRadius.circular(12),
                     ),
                     child: Text(needName, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.primary)),
                   );
                }).toList(),
              ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildEventCard(BuildContext context, ThemeData theme, Map<String, dynamic> event) {
    final needType = event['need_type'] ?? 'unknown';
    final severity = event['severity'] ?? 'moderate';
    final urgency = (event['composite_urgency'] as num?)?.toDouble() ?? 0.5;
    final communityName = event['community_name'] ?? 'Unknown Community';
    final timestamp = event['timestamp'] ?? '';
    final eventCount = event['event_count'] ?? 1;
    final source = event['source'] ?? 'Unknown';

    final severityColor = _getSeverityColor(severity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: severityColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        color: severityColor.withValues(alpha: 0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      communityName,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      needType.replaceAll('_', ' ').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  severity.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: severityColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: urgency,
                  minHeight: 6,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(severityColor),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(urgency * 100).toInt()}%',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$eventCount events · $source',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
              ),
              Text(
                timestamp.isNotEmpty ? _formatTime(timestamp) : 'Just now',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'red':
        return Colors.red;
      case 'high':
      case 'orange':
        return Colors.orange;
      case 'moderate':
      case 'yellow':
        return Colors.amber;
      default:
        return Colors.green;
    }
  }

  String _formatTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      
      return dt.toString().split(' ')[0];
    } catch (_) {
      return 'Recently';
    }
  }
}
