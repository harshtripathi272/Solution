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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    // Mock filtering logic for the tabs
    final matchedTasks = state.tasks.where((t) => t.status == TaskStatus.open).toList();
    final activeTasks = state.tasks.where((t) => t.status == TaskStatus.inProgress || t.status == TaskStatus.assigned).toList();
    final doneTasks = state.tasks.where((t) => t.status == TaskStatus.completed).toList();

    List<VolunteerTask> currentList = _tabIndex == 0 ? matchedTasks : (_tabIndex == 1 ? activeTasks : doneTasks);

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
        
        // List area
        Expanded(
          child: ListView.builder(
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
                              onPressed: () {},
                              child: const Text('Accept Need'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.onSurfaceVariant,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                            child: const Text('Decline'),
                          )
                        ],
                      )
                    else if (_tabIndex == 1)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
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
          decoration: isSelected ? AppDecorations.baseCard.copyWith(boxShadow: []) : const BoxDecoration(),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelLarge?.copyWith(
                  color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
                )),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryContainer : AppColors.surfaceDim,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('$count', style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    )),
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
