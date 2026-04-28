import 'package:flutter/material.dart';

import '../../models/task_model.dart';

/// Read-only task detail for coordinators (data from volunteer-area pipeline).
class VolunteerAreaTaskDetailScreen extends StatelessWidget {
  const VolunteerAreaTaskDetailScreen({super.key, required this.task});

  final VolunteerTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(task.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(task.urgency)),
                Chip(label: Text(task.status.name)),
                if (task.matchScore != null)
                  Chip(label: Text('Score ${(task.matchScore! * 100).round()}%')),
                if (task.distanceKm != null)
                  Chip(label: Text('${task.distanceKm!.toStringAsFixed(1)} km')),
              ],
            ),
            const SizedBox(height: 16),
            Text(task.description, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            Text('Need type: ${task.needType}', style: theme.textTheme.titleSmall),
            Text('Ward / area: ${task.ward}', style: theme.textTheme.bodyMedium),
            Text('Approx. people: ${task.estimatedPeopleAffected}', style: theme.textTheme.bodyMedium),
            if (task.requiredSkills.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Skills', style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 6,
                children: task.requiredSkills.map((s) => Chip(label: Text(s))).toList(),
              ),
            ],
            if (task.sdgTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('SDG tags: ${task.sdgTags.join(", ")}', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
