import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

      if (user == null) throw Exception('User not loaded');

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
          ),
        );
      }
    } catch (e) {
      setState(() => _saveError = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(theme),
              const SizedBox(height: AppSpacing.lg),
              _buildIdentityCard(theme, user, appState).animate().fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
              const SizedBox(height: AppSpacing.lg),
              _buildStatsCard(theme, user, appState).animate(delay: 80.ms).fadeIn(duration: AppMotion.standard),
              if (_isEditing) ...[
                const SizedBox(height: AppSpacing.xl),
                _sectionTitle(theme, 'Edit profile'),
                const SizedBox(height: AppSpacing.md),
                _buildTextField(controller: _nameController, label: 'Full name', icon: Icons.person_rounded),
                const SizedBox(height: AppSpacing.md),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildTextField(
                  controller: _locationController,
                  label: 'Location / area',
                  icon: Icons.location_on_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildAvailabilityToggle(theme),
              ],
              const SizedBox(height: AppSpacing.xl),
              _sectionTitle(theme, 'Skills'),
              const SizedBox(height: AppSpacing.md),
              if (_isEditing) _buildAddSkillRow(theme),
              const SizedBox(height: AppSpacing.md),
              _buildSkillsBlock(theme),
              const SizedBox(height: AppSpacing.xl),
              _sectionTitle(theme, 'Location privacy'),
              const SizedBox(height: AppSpacing.md),
              _buildLocationPrivacyCard(theme, appState),
              if (_saveError != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: AppRadius.lgR,
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text('Error: $_saveError', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onErrorContainer)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────── pieces
  Widget _buildTopBar(ThemeData theme) {
    return Row(
      children: [
        Text('My profile', style: theme.textTheme.headlineLarge),
        const Spacer(),
        if (!_isEditing)
          FilledButton.tonalIcon(
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            ),
          )
        else
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveChanges,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_isSaving ? 'Saving' : 'Save'),
          ),
      ],
    );
  }

  Widget _buildIdentityCard(ThemeData theme, AppUser user, AppState appState) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF3B62F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xlR,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: AppRadius.lgR,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
            ),
            child: Center(
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: AppTypography.metric(size: 30, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isEmpty ? 'Volunteer' : user.name,
                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: AppRadius.pillR,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isAvailable ? AppColors.success : AppColors.urgencyHigh,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isAvailable ? 'Available' : 'Unavailable',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme, AppUser user, AppState appState) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.baseCard,
      child: Row(
        children: [
          Expanded(child: _statTile(theme, 'Tasks done', '${appState.completedTasks.length}', AppColors.primary)),
          Container(width: 1, height: 36, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          Expanded(child: _statTile(theme, 'Est. hours', '${appState.completedTasks.length * 2}', AppColors.secondary)),
          Container(width: 1, height: 36, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          Expanded(child: _statTile(theme, 'Trust score', '${user.trustScore.toStringAsFixed(1)}/5', AppColors.tertiary)),
        ],
      ),
    );
  }

  Widget _statTile(ThemeData theme, String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: AppTypography.metric(size: 22, color: color)),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String label) {
    return Text(label, style: theme.textTheme.titleLarge);
  }

  Widget _buildAvailabilityToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: AppDecorations.cardSubtle,
      child: Row(
        children: [
          const Icon(Icons.event_available_rounded, color: AppColors.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text('Available for tasks', style: theme.textTheme.titleSmall)),
          Switch(
            value: _isAvailable,
            activeThumbColor: AppColors.success,
            onChanged: (v) => setState(() => _isAvailable = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSkillRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _newSkillController,
            decoration: const InputDecoration(
              hintText: 'Add a skill (e.g., medical, rescue)',
              prefixIcon: Icon(Icons.add_circle_outline_rounded),
            ),
            onSubmitted: (_) => _addSkill(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: _addSkill,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          ),
          child: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Widget _buildSkillsBlock(ThemeData theme) {
    if (_editingSkills.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: AppDecorations.cardSubtle,
        child: Center(
          child: Text(
            _isEditing ? 'Add skills to get matched with tasks' : 'No skills added yet',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: _editingSkills.map((skill) {
        return Container(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, _isEditing ? 4 : AppSpacing.md, AppSpacing.sm),
          decoration: AppDecorations.tagAccent(color: AppColors.primary),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                skill,
                style: theme.textTheme.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
              if (_isEditing) ...[
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: AppRadius.pillR,
                  onTap: () => setState(() => _editingSkills.remove(skill)),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLocationPrivacyCard(ThemeData theme, AppState appState) {
    final tracking = appState.locationService?.isTracking == true;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.baseCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (tracking ? AppColors.success : AppColors.surfaceContainerHigh).withValues(alpha: tracking ? 0.18 : 1),
                  borderRadius: AppRadius.mdR,
                ),
                child: Icon(
                  tracking ? Icons.my_location_rounded : Icons.location_off_rounded,
                  color: tracking ? AppColors.success : AppColors.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  tracking ? 'Location is being shared' : 'Location sharing is off',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your location is ephemeral and auto-expires after 2 hours. You can permanently delete it any time.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => appState.toggleLocationTracking(),
                  icon: Icon(tracking ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(tracking ? 'Pause' : 'Start'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete location data'),
                      content: const Text('This permanently removes your location from our servers. Continue?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  if (!mounted) return;
                  await context.read<AppState>().revokeLocation();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Location data deleted permanently.')),
                  );
                },
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
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
      ),
    );
  }
}
