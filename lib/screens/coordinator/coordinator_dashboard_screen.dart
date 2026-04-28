import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadRecentNeeds,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(theme).animate().fadeIn(duration: AppMotion.standard),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null) _buildErrorBanner(theme),
                const SizedBox(height: AppSpacing.lg),
                _buildStatsRow(theme, state).animate(delay: 80.ms).fadeIn(duration: AppMotion.standard),
                const SizedBox(height: AppSpacing.xxl),
                if (state.derivedCrisisAlerts.isNotEmpty) ...[
                  _buildSectionHeader(
                    theme,
                    title: 'Critical alerts',
                    badge: '${state.derivedCrisisAlerts.length} active',
                    badgeColor: AppColors.error,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    height: 232,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      scrollDirection: Axis.horizontal,
                      itemCount: state.derivedCrisisAlerts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                      itemBuilder: (context, index) =>
                          CrisisAlertCard(alert: state.derivedCrisisAlerts[index])
                              .animate(delay: (index * 60).ms)
                              .fadeIn(duration: AppMotion.standard)
                              .slideX(begin: 0.06, end: 0),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
                if (_recentNeeds != null && _recentNeeds!['events'] != null) ...[
                  _buildSectionHeader(
                    theme,
                    title: 'Real-time events',
                    badge: '${_recentNeeds!['total_events'] ?? 0} events',
                    badgeColor: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...(_recentNeeds!['events'] as List).take(5).toList().asMap().entries.map((entry) {
                    final i = entry.key;
                    final event = entry.value as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xs),
                      child: InkWell(
                        borderRadius: AppRadius.lgR,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PipelineEventDetailScreen(
                                event: Map<String, dynamic>.from(event),
                              ),
                            ),
                          );
                        },
                        child: _buildEventCard(theme, event),
                      ).animate(delay: (i * 50).ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
                    );
                  }),
                  const SizedBox(height: AppSpacing.xxl),
                ],
                if (_overviewData != null && _overviewData!.profiles.isNotEmpty) ...[
                  _buildSectionHeader(theme, title: 'Recent needs'),
                  const SizedBox(height: AppSpacing.md),
                  ..._overviewData!.profiles.take(5).toList().asMap().entries.map((entry) {
                    final i = entry.key;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.md),
                      child: _buildCommunityRequirementCard(theme, entry.value)
                          .animate(delay: (i * 50).ms)
                          .fadeIn(duration: AppMotion.standard)
                          .slideY(begin: 0.04, end: 0),
                    );
                  }),
                  const SizedBox(height: AppSpacing.xxl),
                ] else ...[
                  _buildSectionHeader(theme, title: 'Recent needs'),
                  const SizedBox(height: AppSpacing.md),
                  ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.tasks.take(5).length,
                    itemBuilder: (context, index) {
                      final t = state.tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: InkWell(
                          borderRadius: AppRadius.lgR,
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
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────── pieces
  Widget _buildHero(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coordinator overview',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text('Community snapshot', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(
            'Live signals from your communities, ranked by urgency.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: AppRadius.lgR,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Could not refresh community snapshots: $_error',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme, AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: StatCard(
              title: 'Open needs',
              value: '${state.tasks.where((t) => t.status == TaskStatus.open).length}',
              icon: Icons.assignment_late_rounded,
              color: AppColors.warning,
              subtitle: 'Pending',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: StatCard(
              title: 'Active tasks',
              value: '${state.activeTasks.length}',
              icon: Icons.groups_2_rounded,
              color: AppColors.primary,
              subtitle: '${state.completedTasks.length} done',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme, {
    required String title,
    String? badge,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
              decoration: BoxDecoration(
                color: (badgeColor ?? AppColors.primary).withValues(alpha: 0.10),
                borderRadius: AppRadius.pillR,
              ),
              child: Text(
                badge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: badgeColor ?? AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommunityRequirementCard(ThemeData theme, CommunityProfile profile) {
    return InkWell(
      borderRadius: AppRadius.xlR,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => CommunityDetailScreen(profile: profile)),
        );
      },
      child: Container(
        decoration: AppDecorations.baseCard,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius: AppRadius.mdR,
                  ),
                  child: const Icon(Icons.groups_rounded, color: AppColors.secondary, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Last reported: ${profile.lastVerifiedLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.outlineVariant),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Sources: ${profile.activeOrganizationsLabel}',
              style: theme.textTheme.bodySmall,
            ),
            if (profile.needs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: profile.needs.take(3).map((need) {
                  final needName = need.needType.replaceAll('_', ' ');
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                    decoration: AppDecorations.tagAccent(color: AppColors.primary),
                    child: Text(
                      needName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(ThemeData theme, Map<String, dynamic> event) {
    final needType = (event['need_type'] ?? 'unknown').toString();
    final severity = (event['severity'] ?? 'moderate').toString();
    final urgency = (event['composite_urgency'] as num?)?.toDouble() ?? 0.5;
    final communityName = (event['community_name'] ?? 'Unknown community').toString();
    final timestamp = (event['timestamp'] ?? '').toString();
    final eventCount = event['event_count'] ?? 1;
    final source = (event['source'] ?? 'Unknown').toString();

    final severityColor = _getSeverityColor(severity);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: severityColor.withValues(alpha: 0.25), width: 1.2),
        boxShadow: AppElevation.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.14),
                  borderRadius: AppRadius.mdR,
                ),
                child: Icon(Icons.bolt_rounded, color: severityColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      communityName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      needType.replaceAll('_', ' ').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.16),
                  borderRadius: AppRadius.pillR,
                ),
                child: Text(
                  severity.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: severityColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.pillR,
                  child: LinearProgressIndicator(
                    value: urgency.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(severityColor),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(urgency * 100).toInt()}%',
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$eventCount events · $source',
                style: theme.textTheme.labelSmall,
              ),
              Text(
                timestamp.isNotEmpty ? _formatTime(timestamp) : 'Just now',
                style: theme.textTheme.labelSmall,
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
        return AppColors.urgencyCritical;
      case 'high':
      case 'orange':
        return AppColors.urgencyHigh;
      case 'moderate':
      case 'yellow':
        return AppColors.urgencyMedium;
      default:
        return AppColors.urgencyLow;
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
