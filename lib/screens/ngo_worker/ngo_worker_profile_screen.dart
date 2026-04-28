import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../services/profile_service.dart';

class NGOWorkerProfileScreen extends StatefulWidget {
  const NGOWorkerProfileScreen({super.key});

  @override
  State<NGOWorkerProfileScreen> createState() => _NGOWorkerProfileScreenState();
}

class _NGOWorkerProfileScreenState extends State<NGOWorkerProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _organizationController;
  late TextEditingController _locationController;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final user = appState.currentUser;

    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _organizationController = TextEditingController(text: user?.ngoId ?? '');
    _locationController = TextEditingController(text: user?.location ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _organizationController.dispose();
    _locationController.dispose();
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
        role: UserRole.ngoWorker,
        ngoId: _organizationController.text,
        phone: _phoneController.text,
        skills: user.skills,
        location: _locationController.text,
        latitude: user.latitude,
        longitude: user.longitude,
        trustScore: user.trustScore,
        tasksCompleted: user.tasksCompleted,
        totalHoursVolunteered: user.totalHoursVolunteered,
        isAvailable: user.isAvailable,
        createdAt: user.createdAt,
      );

      await ProfileService.updateNGOWorkerProfile(user.id, updatedUser);
      await appState.refreshProfileFromServer();

      if (mounted) {
        final u = appState.currentUser;
        if (u != null) {
          _nameController.text = u.name;
          _phoneController.text = u.phone ?? '';
          _organizationController.text = u.ngoId ?? '';
          _locationController.text = u.location ?? '';
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
              _buildIdentityCard(theme, user).animate().fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
              const SizedBox(height: AppSpacing.lg),
              _buildStatsCard(theme, user, appState).animate(delay: 80.ms).fadeIn(duration: AppMotion.standard),
              const SizedBox(height: AppSpacing.xl),
              if (_isEditing) ...[
                Text('Edit profile', style: theme.textTheme.titleLarge),
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
                  controller: _organizationController,
                  label: 'Organization',
                  icon: Icons.business_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildTextField(
                  controller: _locationController,
                  label: 'Office location',
                  icon: Icons.location_on_rounded,
                ),
              ] else ...[
                Text('Organization details', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                _buildInfoTile(theme, 'Organization', user.ngoId ?? '—', Icons.business_rounded),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoTile(theme, 'Office location', user.location ?? '—', Icons.location_on_rounded),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoTile(theme, 'Phone', user.phone ?? '—', Icons.phone_rounded),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: AppRadius.lgR,
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Error: $_saveError',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onErrorContainer),
                  ),
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

  Widget _buildIdentityCard(ThemeData theme, AppUser user) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.tertiary, Color(0xFFEA8A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xlR,
        boxShadow: [
          BoxShadow(
            color: AppColors.tertiary.withValues(alpha: 0.22),
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
                  user.name.isEmpty ? 'NGO worker' : user.name,
                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
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
                  child: Text(
                    'NGO worker',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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
          Expanded(child: _statTile(theme, 'Reports', '${appState.reportCount}', AppColors.primary)),
          Container(width: 1, height: 36, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          Expanded(child: _statTile(theme, 'Trust', user.trustScore.toStringAsFixed(1), AppColors.tertiary)),
          Container(width: 1, height: 36, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          Expanded(child: _statTile(theme, 'Member since', user.createdAt.year.toString(), AppColors.secondary)),
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

  Widget _buildInfoTile(ThemeData theme, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.cardSubtle,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadius.mdR,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.titleSmall),
              ],
            ),
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
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}
