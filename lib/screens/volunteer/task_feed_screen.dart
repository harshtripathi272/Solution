import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../config/theme.dart';
import '../../models/task_model.dart';
import '../../widgets/task_card.dart';

class VolunteerTaskFeed extends StatefulWidget {
  const VolunteerTaskFeed({super.key});

  @override
  State<VolunteerTaskFeed> createState() => _VolunteerTaskFeedState();
}

class _VolunteerTaskFeedState extends State<VolunteerTaskFeed> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().refreshHistoricalTasks();
    });
  }

  void _acceptTask(String taskId) {
    final state = context.read<AppState>();
    final userId = state.currentUser?.id ?? '';
    state.acceptTask(taskId, userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task accepted — moved to Active.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        ),
      );
    }
  }

  void _declineTask(String taskId) {
    context.read<AppState>().updateTaskStatus(taskId, TaskStatus.cancelled);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task declined.')),
      );
    }
  }

  void _markComplete(String taskId) {
    context.read<AppState>().updateTaskStatus(taskId, TaskStatus.completed);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task completed — great work.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final user = state.currentUser;
    final userSkills = user?.skills ?? [];

    final openCandidates = state.tasks.where((t) => t.status == TaskStatus.open).toList();
    final matchedTasks = openCandidates.where((t) {
      if (userSkills.isEmpty) return true;
      if (t.requiredSkills.isEmpty) return true;
      return t.requiredSkills.any((s) => userSkills.contains(s));
    }).toList()
      ..sort((a, b) {
        final aMatch = a.requiredSkills.where((s) => userSkills.contains(s)).length;
        final bMatch = b.requiredSkills.where((s) => userSkills.contains(s)).length;
        if (aMatch != bMatch) return bMatch.compareTo(aMatch);
        return (b.matchScore ?? 0).compareTo(a.matchScore ?? 0);
      });

    final activeTasks = state.tasks
        .where((t) => t.status == TaskStatus.inProgress || t.status == TaskStatus.assigned)
        .toList();
    final doneTasks = state.tasks.where((t) => t.status == TaskStatus.completed).toList();

    final currentList = _tabIndex == 0 ? matchedTasks : (_tabIndex == 1 ? activeTasks : doneTasks);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await context.read<AppState>().refreshHistoricalTasks();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHero(theme, user?.name)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
              child: _buildSegmentedTabs(
                theme,
                matched: matchedTasks.length,
                active: activeTasks.length,
                done: doneTasks.length,
              ),
            ),
          ),
          if (state.tasks.isEmpty && state.backendError != null)
            SliverToBoxAdapter(child: _buildBackendErrorBanner(theme, state.backendError!)),
          if (state.tasks.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyExplainer(theme)),
          if (currentList.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(theme),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
              sliver: SliverList.builder(
                itemCount: currentList.length,
                itemBuilder: (context, index) {
                  final task = currentList[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Column(
                      children: [
                        TaskCard(task: task),
                        const SizedBox(height: AppSpacing.md),
                        if (_tabIndex == 0) _buildAcceptDeclineRow(task.id),
                        if (_tabIndex == 1) _buildCompleteButton(task.id),
                      ],
                    ),
                  ).animate(delay: (index * 40).ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────── pieces
  Widget _buildHero(ThemeData theme, String? name) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name == null ? 'Impact Feed' : 'Hi, ${name.split(' ').first}',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text('Find your next task', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(
            'Tasks ranked by your skills, area, and urgency.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    ).animate().fadeIn(duration: AppMotion.standard);
  }

  Widget _buildSegmentedTabs(ThemeData theme,
      {required int matched, required int active, required int done}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.pillR,
      ),
      child: Row(
        children: [
          _buildTab(0, 'Matched', matched),
          _buildTab(1, 'Active', active),
          _buildTab(2, 'Done', done),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, int count) {
    final isSelected = _tabIndex == index;
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.easeStandard,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceContainerLowest : Colors.transparent,
            borderRadius: AppRadius.pillR,
            boxShadow: isSelected ? AppElevation.soft : null,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
                      borderRadius: AppRadius.pillR,
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcceptDeclineRow(String taskId) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _acceptTask(taskId),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Accept'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _declineTask(taskId),
            child: const Text('Decline'),
          ),
        ),
      ],
    );
  }

  Widget _buildCompleteButton(String taskId) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _markComplete(taskId),
        style: FilledButton.styleFrom(backgroundColor: AppColors.success),
        icon: const Icon(Icons.task_alt_rounded, size: 18),
        label: const Text('Mark complete'),
      ),
    );
  }

  Widget _buildBackendErrorBanner(ThemeData theme, String error) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: AppRadius.lgR,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyExplainer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ClipRRect(
          borderRadius: AppRadius.lgR,
          child: Container(
            decoration: AppDecorations.cardSubtle,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: AppRadius.mdR,
                ),
                child: const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 20),
              ),
              title: Text('Why are there no tasks?', style: theme.textTheme.titleSmall),
              subtitle: Text(
                'Tasks come from the volunteer-area pipeline. Tap for details.',
                style: theme.textTheme.bodySmall,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                  child: Text(
                    'Tasks appear when the backend returns volunteer_area_tasks within your radius and your '
                    'session has a location anchor (one-time GPS at sign-in or ongoing sharing). The "Matched" '
                    'tab also filters by skills when tasks specify required skills. Empty often means pipeline '
                    'or geography — not necessarily a defect.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final messages = [
      ['No matching tasks', 'Tasks that match your skills will appear here. Try enabling location sharing.', Icons.search_off_rounded],
      ['No active tasks', 'Accept tasks from the Matched tab to see them here.', Icons.assignment_outlined],
      ['No completed tasks yet', 'Tasks you complete will show up here. Keep going.', Icons.emoji_events_outlined],
    ];
    final msg = messages[_tabIndex];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: [Color(0xFFE2E8FF), Color(0x00E2E8FF)],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(msg[2] as IconData, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(msg[0] as String, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              msg[1] as String,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ).animate().fadeIn(duration: AppMotion.standard),
    );
  }
}
