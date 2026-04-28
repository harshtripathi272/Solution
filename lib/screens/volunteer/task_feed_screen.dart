import 'package:flutter/material.dart';
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
      if (!mounted) {
        return;
      }
      context.read<AppState>().refreshHistoricalTasks();
    });
  }

  void _acceptTask(String taskId) {
    final state = context.read<AppState>();
    final userId = state.currentUser?.id ?? '';
    state.acceptTask(taskId, userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task accepted! Moved to Active tab.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _declineTask(String taskId) {
    // For now, just remove from local view by marking cancelled
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
        const SnackBar(
          content: Text('Task completed! Great work! 🎉'),
          backgroundColor: AppColors.success,
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

    // Matched tab: prefer tasks whose requiredSkills overlap volunteer skills (or no skills required).
    final openCandidates = state.tasks.where((t) => t.status == TaskStatus.open).toList();
    final matchedTasks = openCandidates.where((t) {
      if (userSkills.isEmpty) return true;
      if (t.requiredSkills.isEmpty) return true;
      return t.requiredSkills.any((s) => userSkills.contains(s));
    }).toList()
      ..sort((a, b) {
        // Prioritize tasks whose requiredSkills overlap with user skills
        final aMatch = a.requiredSkills.where((s) => userSkills.contains(s)).length;
        final bMatch = b.requiredSkills.where((s) => userSkills.contains(s)).length;
        if (aMatch != bMatch) return bMatch.compareTo(aMatch);
        // Fall back to matchScore
        return (b.matchScore ?? 0).compareTo(a.matchScore ?? 0);
      });
    final activeTasks = state.tasks
        .where(
          (t) =>
              t.status == TaskStatus.inProgress ||
              t.status == TaskStatus.assigned,
        )
        .toList();
    final doneTasks = state.tasks
        .where((t) => t.status == TaskStatus.completed)
        .toList();

    List<VolunteerTask> currentList = _tabIndex == 0
        ? matchedTasks
        : (_tabIndex == 1 ? activeTasks : doneTasks);

    return Column(
      children: [
        // App bar area
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Impact Feed', style: theme.textTheme.displayMedium),
              const SizedBox(height: 24),
              // Beautiful organic tabs
              Container(
                padding: const EdgeInsets.all(6),
                decoration: AppDecorations.contentBlock,
                child: Row(
                  children: [
                    _buildTab(0, 'Matched', matchedTasks.length),
                    _buildTab(1, 'Active', activeTasks.length),
                    _buildTab(2, 'Done', doneTasks.length),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.tasks.isEmpty && state.backendError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state.backendError!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (state.tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text('Why are there no tasks?', style: theme.textTheme.titleSmall),
                    subtitle: Text(
                      'Tasks come from the volunteer-area pipeline (API + location). Tap for details.',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          'Tasks appear when the backend returns volunteer_area_tasks within your radius, '
                          'and your session has a location anchor (one-time GPS at sign-in or ongoing sharing). '
                          'Matched also filters by skills when tasks specify required skills. '
                          'Empty often means pipeline or geography — not necessarily a defect.',
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: currentList.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: currentList.length,
                  itemBuilder: (context, index) {
                    final task = currentList[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        children: [
                          TaskCard(task: task),
                          const SizedBox(height: 16),
                          // Only show action buttons for Matched / Active
                          if (_tabIndex == 0)
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _acceptTask(task.id),
                                    child: const Text('Accept Need'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                TextButton(
                                  onPressed: () => _declineTask(task.id),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.onSurfaceVariant,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text('Decline'),
                                ),
                              ],
                            )
                          else if (_tabIndex == 1)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _markComplete(task.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                ),
                                child: const Text('Mark Complete'),
                              ),
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
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final messages = [
      ['No matching tasks found', 'Tasks that match your skills will appear here. Try enabling location sharing.', Icons.search_off],
      ['No active tasks', 'Accept tasks from the Matched tab to see them here.', Icons.assignment_outlined],
      ['No completed tasks yet', 'Tasks you complete will appear here. Keep up the great work!', Icons.emoji_events_outlined],
    ];
    final msg = messages[_tabIndex];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(msg[2] as IconData, size: 48, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(msg[0] as String, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(msg[1] as String, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index, String label, int count) {
    final isSelected = _tabIndex == index;
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: isSelected
              ? AppDecorations.baseCard.copyWith(boxShadow: [])
              : const BoxDecoration(),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isSelected
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryContainer
                          : AppColors.surfaceDim,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? AppColors.onPrimary
                            : AppColors.onSurfaceVariant,
                        fontSize: 11,
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
}
