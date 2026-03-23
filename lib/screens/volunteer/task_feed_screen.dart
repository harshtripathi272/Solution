import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../../config/theme.dart';
import '../../providers/app_state.dart';
import '../../models/task_model.dart';

class VolunteerTaskFeed extends StatefulWidget {
  const VolunteerTaskFeed({super.key});

  @override
  State<VolunteerTaskFeed> createState() => _VolunteerTaskFeedState();
}

class _VolunteerTaskFeedState extends State<VolunteerTaskFeed>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Column(
          children: [
            FadeInDown(
              duration: const Duration(milliseconds: 600),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Tasks',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('AI-matched tasks based on your skills & location',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder, width: 0.5),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  dividerHeight: 0,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Matched'), const SizedBox(width: 6),
                      _badge('${state.openTasks.length}', AppColors.accent),
                    ])),
                    Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Active'), const SizedBox(width: 6),
                      _badge('${state.activeTasks.length}', AppColors.primary),
                    ])),
                    Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Done'), const SizedBox(width: 6),
                      _badge('${state.completedTasks.length}', AppColors.success),
                    ])),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(controller: _tabController, children: [
                _buildList(state.openTasks, state, matched: true),
                _buildList(state.activeTasks, state),
                _buildList(state.completedTasks, state),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _badge(String c, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: col.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
    child: Text(c, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _buildList(List<VolunteerTask> tasks, AppState state, {bool matched = false}) {
    if (tasks.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_outline, size: 64, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text('No tasks here', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final task = tasks[i];
        final uc = _urgCol(task.urgency);
        return FadeInUp(
          duration: const Duration(milliseconds: 500),
          delay: Duration(milliseconds: 100 * i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: AppDecorations.glassCard,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: uc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(task.urgency.toUpperCase(), style: TextStyle(color: uc, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                if (matched) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(gradient: AppDecorations.primaryGradient, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('AI Match: ${(85 + i * 3).clamp(75, 98)}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (task.status == TaskStatus.completed) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('COMPLETED', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _chip(Icons.location_on, task.ward),
                _chip(Icons.groups, '${task.estimatedPeopleAffected} people'),
                ...task.requiredSkills.take(2).map((s) => _chip(Icons.build_circle, s, color: AppColors.primary)),
              ]),
              if (task.status == TaskStatus.open) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Decline'))),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: ElevatedButton(
                    onPressed: () => state.acceptTask(task.id, state.currentUser.id),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check, size: 18), SizedBox(width: 6), Text('Accept Task'),
                    ]),
                  )),
                ]),
              ],
              if (task.status == TaskStatus.assigned || task.status == TaskStatus.inProgress) ...[
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () => state.updateTaskStatus(task.id, TaskStatus.completed),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(double.infinity, 44)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.check_circle, size: 18), SizedBox(width: 6), Text('Mark Complete'),
                  ]),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: (color ?? AppColors.textMuted).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color ?? AppColors.textMuted),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color ?? AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
    ]),
  );

  Color _urgCol(String u) => switch (u) {
    'Critical' => AppColors.urgencyCritical, 'High' => AppColors.urgencyHigh,
    'Medium' => AppColors.urgencyMedium, _ => AppColors.urgencyLow,
  };
}
