import 'package:flutter/material.dart';
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
      
      if (user == null) throw Exception("User not loaded");

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
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } catch (e) {
      setState(() => _saveError = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: AppColors.error),
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
              child: _isSaving ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ) : const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
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
                        backgroundColor: AppColors.tertiary,
                        child: Text(
                          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name, style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(user.email, style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.tertiary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'NGO Worker',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.tertiary,
                                ),
                              ),
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
                      _buildStatTile('Reports', '${appState.reportCount}'),
                      _buildStatTile('Trust', user.trustScore.toStringAsFixed(1)),
                      _buildStatTile('Member Since', user.createdAt.year.toString()),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

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
                controller: _organizationController,
                label: 'Organization Name',
                icon: Icons.business,
              ),
              const SizedBox(height: 16),
              
              _buildTextField(
                controller: _locationController,
                label: 'Office Location',
                icon: Icons.location_on,
              ),
              const SizedBox(height: 32),
            ] else ...[
              // View Mode
              Text('Organization Details', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              
              _buildInfoTile('Organization', user.ngoId ?? 'Not set'),
              const SizedBox(height: 12),
              
              _buildInfoTile('Location', user.location ?? 'Not set'),
              const SizedBox(height: 12),
              
              _buildInfoTile('Phone', user.phone ?? 'Not set'),
            ],

            if (_saveError != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppDecorations.contentBlock,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
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
