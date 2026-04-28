import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../services/profile_service.dart';

class VolunteerProfileScreen extends StatefulWidget {
  const VolunteerProfileScreen({super.key});

  @override
  State<VolunteerProfileScreen> createState() => _VolunteerProfileScreenState();
}

class _VolunteerProfileScreenState extends State<VolunteerProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _locationController;
  late TextEditingController _newSkillController;
  List<String> _editingSkills = [];
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isAvailable = true;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final user = appState.currentUser;

    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _locationController = TextEditingController(text: user?.location ?? '');
    _newSkillController = TextEditingController();
    _editingSkills = List.from(user?.skills ?? []);
    _isAvailable = user?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _newSkillController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final appState = context.read<AppState>();
      final user = appState.currentUser;
      final messenger = ScaffoldMessenger.of(context);

      if (user == null) throw Exception("User not loaded");

      final updatedUser = AppUser(
        id: user.id,
        name: _nameController.text,
        email: user.email,
        role: UserRole.volunteer,
        phone: _phoneController.text,
        skills: _editingSkills,
        location: _locationController.text,
        latitude: user.latitude,
        longitude: user.longitude,
        trustScore: user.trustScore,
        tasksCompleted: user.tasksCompleted,
        totalHoursVolunteered: user.totalHoursVolunteered,
        isAvailable: _isAvailable,
        createdAt: user.createdAt,
      );

      await ProfileService.updateVolunteerProfile(user.id, updatedUser);
      await appState.refreshProfileFromServer();

      if (mounted) {
        final u = appState.currentUser;
        if (u != null) {
          _nameController.text = u.name;
          _phoneController.text = u.phone ?? '';
          _locationController.text = u.location ?? '';
          _editingSkills = List.from(u.skills);
          _isAvailable = u.isAvailable;
        }
        setState(() => _isEditing = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } catch (e) {
      setState(() => _saveError = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addSkill() {
    final skill = _newSkillController.text.trim();
    if (skill.isNotEmpty && !_editingSkills.contains(skill)) {
      setState(() {
        _editingSkills.add(skill);
        _newSkillController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    final theme = Theme.of(context);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (!_isEditing)
            TextButton(
              onPressed: () => setState(() => _isEditing = true),
              child: const Text('Edit'),
            )
          else
            TextButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Avatar & Summary
            Container(
              padding: const EdgeInsets.all(24),
              decoration: AppDecorations.baseCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.primaryContainer,
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(user.email, style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _isAvailable ? 'Available' : 'Unavailable',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _isAvailable
                                          ? AppColors.success
                                          : AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatTile(
                        'Tasks Done',
                        '${appState.completedTasks.length}',
                      ),
                      _buildStatTile(
                        'Est. hours',
                        '${appState.completedTasks.length * 2}',
                      ),
                      _buildStatTile(
                        'Trust Score',
                        '${user.trustScore.toStringAsFixed(1)}/5',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Editable Fields
            if (_isEditing) ...[
              Text('Edit Profile', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),

              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _phoneController,
                label: 'Phone Number',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _locationController,
                label: 'Location/Area',
                icon: Icons.location_on,
              ),
              const SizedBox(height: 24),

              // Availability Toggle
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: AppDecorations.contentBlock,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available for Tasks',
                      style: theme.textTheme.labelLarge,
                    ),
                    Switch(
                      value: _isAvailable,
                      activeThumbColor: AppColors.success,
                      onChanged: (value) =>
                          setState(() => _isAvailable = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],

            // Skills Section
            Text('Skills', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),

            if (_isEditing)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newSkillController,
                          decoration: InputDecoration(
                            hintText: 'Add a skill (e.g., Medical, Rescue)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addSkill,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            if (_editingSkills.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(
                    _isEditing
                        ? 'Add skills to get matched with tasks'
                        : 'No skills added yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _editingSkills.map((skill) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          skill,
                          style: const TextStyle(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_isEditing)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _editingSkills.remove(skill)),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            // Location Privacy section
            const SizedBox(height: 32),
            Text('Location Privacy', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppDecorations.contentBlock,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        appState.locationService?.isTracking == true
                            ? Icons.location_on
                            : Icons.location_off,
                        color: appState.locationService?.isTracking == true
                            ? AppColors.success
                            : AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        appState.locationService?.isTracking == true
                            ? 'Location is being shared'
                            : 'Location sharing is off',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your location is ephemeral and auto-expires after 2 hours. You can permanently delete it at any time.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => appState.toggleLocationTracking(),
                          icon: Icon(
                            appState.locationService?.isTracking == true
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            appState.locationService?.isTracking == true
                                ? 'Pause Sharing'
                                : 'Start Sharing',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final appState = context.read<AppState>();
                          final messenger = ScaffoldMessenger.of(context);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Location Data'),
                              content: const Text(
                                'This will permanently remove your location from our servers. Continue?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && mounted) {
                            await appState.revokeLocation();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Location data deleted permanently.',
                                ),
                              ),
                            );
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Delete Data'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_saveError != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'Error: $_saveError',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
