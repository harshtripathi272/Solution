import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/app_state.dart';
import '../models/user_model.dart';
import '../config/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const List<UserRole> _signUpRoleOrder = [
    UserRole.volunteer,
    UserRole.ngoAdmin,
    UserRole.ngoWorker,
  ];

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  UserRole _selectedRole = UserRole.volunteer;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _orgNameController = TextEditingController();
  final _orgMissionController = TextEditingController();
  final _orgRegionController = TextEditingController();
  final _orgIdController = TextEditingController();
  bool _isIndependent = false;
  final _authService = AuthService();

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    if (!_isLogin) {
      final orgId = _orgIdController.text.trim();
      if ((_selectedRole == UserRole.volunteer && !_isIndependent) ||
          _selectedRole == UserRole.ngoWorker) {
        if (orgId.isEmpty) {
          setState(() => _errorMessage = 'Enter the 8-digit Organization ID from your NGO.');
          return;
        }
        if (!RegExp(r'^\d{8}$').hasMatch(orgId.replaceAll(RegExp(r'\s'), ''))) {
          setState(() => _errorMessage = 'Organization ID must be exactly 8 digits.');
          return;
        }
      }
      if (_selectedRole == UserRole.ngoAdmin) {
        if (_nameController.text.trim().isEmpty || _orgNameController.text.trim().isEmpty) {
          setState(() => _errorMessage = 'Please enter your name and NGO name.');
          return;
        }
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        await _authService.signInWithEmailPassword(email, password);
      } else {
        if (mounted) {
          final regData = <String, dynamic>{
            'requested_role': _selectedRole.name,
            'name': _nameController.text.trim(),
            'is_independent': _isIndependent,
          };
          if (_selectedRole == UserRole.ngoAdmin) {
            regData.addAll({
              'organization_name': _orgNameController.text.trim(),
              'organization_mission': _orgMissionController.text.trim(),
              'organization_region': _orgRegionController.text.trim(),
            });
          } else if (_selectedRole == UserRole.ngoWorker ||
              (_selectedRole == UserRole.volunteer && !_isIndependent)) {
            regData['organization_id'] = _orgIdController.text.trim().replaceAll(RegExp(r'\s'), '');
          }
          context.read<AppState>().setRegistrationData(regData);
        }
        await _authService.signUpWithEmailPassword(email, password);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Authentication failed');
    } catch (e) {
      setState(() => _errorMessage = 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitGoogle() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (!_isLogin && mounted) {
        context.read<AppState>().setRequestedRole(_selectedRole);
      }
      await _authService.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Google Sign-In failed');
    } catch (_) {
      // user cancelled
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _orgNameController.dispose();
    _orgMissionController.dispose();
    _orgRegionController.dispose();
    _orgIdController.dispose();
    super.dispose();
  }

  String _roleLabel(UserRole r) => switch (r) {
        UserRole.volunteer => 'Volunteer',
        UserRole.ngoWorker => 'NGO field worker',
        UserRole.ngoAdmin || UserRole.coordinator => 'NGO Administrator',
        UserRole.platformAdmin => 'Platform Admin',
      };

  IconData _roleIcon(UserRole r) => switch (r) {
        UserRole.volunteer => Icons.volunteer_activism_rounded,
        UserRole.ngoWorker => Icons.people_alt_rounded,
        UserRole.ngoAdmin || UserRole.coordinator => Icons.business_center_rounded,
        UserRole.platformAdmin => Icons.shield_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _AuroraBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl + bottomInset,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - MediaQuery.of(context).padding.vertical,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHero(theme),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            _isLogin ? 'Welcome back' : 'Join SevaSetu',
                            style: theme.textTheme.headlineLarge,
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(duration: AppMotion.standard).slideY(begin: 0.08, end: 0),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _isLogin
                                ? 'Log in to coordinate care and impact lives.'
                                : 'Create one account — pick how you participate.',
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ).animate(delay: 80.ms).fadeIn(duration: AppMotion.standard),
                          const SizedBox(height: AppSpacing.xxl),
                          if (_errorMessage != null) _buildError(theme),
                          _buildTextField(
                            controller: _emailController,
                            label: 'Work email',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ).animate(delay: 120.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.06, end: 0),
                          const SizedBox(height: AppSpacing.md),
                          _buildTextField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                          ).animate(delay: 160.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.06, end: 0),
                          if (!_isLogin) ...[
                            const SizedBox(height: AppSpacing.md),
                            _buildTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              icon: Icons.person_outline_rounded,
                            ).animate(delay: 180.ms).fadeIn(duration: AppMotion.standard),
                            const SizedBox(height: AppSpacing.lg),
                            _buildRoleDropdown(theme),
                            if (_selectedRole == UserRole.ngoAdmin) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _buildTextField(
                                controller: _orgNameController,
                                label: 'NGO Name',
                                icon: Icons.business_rounded,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _buildTextField(
                                controller: _orgMissionController,
                                label: 'NGO Mission',
                                icon: Icons.flag_rounded,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _buildTextField(
                                controller: _orgRegionController,
                                label: 'NGO Primary Region',
                                icon: Icons.map_rounded,
                              ),
                            ] else if (_selectedRole == UserRole.ngoWorker ||
                                _selectedRole == UserRole.volunteer) ...[
                              const SizedBox(height: AppSpacing.md),
                              if (_selectedRole == UserRole.volunteer)
                                SwitchListTile(
                                  title: const Text('I am an independent helper'),
                                  subtitle: const Text('Not affiliated with any specific NGO'),
                                  value: _isIndependent,
                                  activeThumbColor: AppColors.primary,
                                  onChanged: (v) => setState(() {
                                    _isIndependent = v;
                                    if (v) _orgIdController.clear();
                                  }),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              if (_selectedRole == UserRole.ngoWorker ||
                                  !_isIndependent) ...[
                                const SizedBox(height: AppSpacing.md),
                                _buildTextField(
                                  controller: _orgIdController,
                                  label: 'Organization ID',
                                  icon: Icons.pin_rounded,
                                  keyboardType: TextInputType.number,
                                  hintText: '8-digit code from your NGO',
                                  maxLength: 8,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                                  child: Text(
                                    'Ask your NGO administrator for this SevaSetu organization ID.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          _buildPrimaryButton(theme),
                          const SizedBox(height: AppSpacing.md),
                          _buildDivider(theme),
                          const SizedBox(height: AppSpacing.md),
                          _buildGoogleButton(theme),
                          const Spacer(),
                          const SizedBox(height: AppSpacing.lg),
                          _buildToggleRow(theme),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sections
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHero(ThemeData theme) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFE2E8FF), Color(0x00E2E8FF)],
              stops: [0.0, 0.85],
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Lottie.asset(
            'assets/lottie/hummingbird.lottie',
            fit: BoxFit.contain,
            repeat: true,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                ),
                child: const Icon(
                  Icons.flutter_dash_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
              );
            },
          ),
        ).animate().fadeIn(duration: AppMotion.emphasized).scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              curve: AppMotion.easeEmphasized,
              duration: AppMotion.emphasized,
            ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onErrorContainer),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: AppMotion.fast);
  }

  Widget _buildRoleDropdown(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign up as',
          style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<UserRole>(
          initialValue: _selectedRole,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: AppColors.primary),
          decoration: InputDecoration(
            prefixIcon: Icon(_roleIcon(_selectedRole), color: AppColors.primary),
          ),
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.onSurface),
          items: _signUpRoleOrder.map((r) {
            return DropdownMenuItem<UserRole>(
              value: r,
              child: Row(
                children: [
                  Icon(_roleIcon(r), size: 18, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.md),
                  Text(_roleLabel(r)),
                ],
              ),
            );
          }).toList(),
          onChanged: _isLoading ? null : (v) => v == null ? null : setState(() => _selectedRole = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'You can change this later with your organisation.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ).animate(delay: 200.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0);
  }

  Widget _buildPrimaryButton(ThemeData theme) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: _isLoading ? null : _submit,
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2.4),
              )
            : Text(
                _isLogin ? 'Log in' : 'Create account',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.onPrimary,
                  fontSize: 15,
                ),
              ),
      ),
    ).animate(delay: 220.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.06, end: 0);
  }

  Widget _buildGoogleButton(ThemeData theme) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _submitGoogle,
        icon: const Icon(Icons.g_mobiledata_rounded, size: 28, color: AppColors.primary),
        label: Text(
          'Continue with Google',
          style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurface),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surfaceContainerLowest,
        ),
      ),
    ).animate(delay: 260.ms).fadeIn(duration: AppMotion.standard);
  }

  Widget _buildDivider(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.outlineVariant.withValues(alpha: 0.6))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'or',
            style: theme.textTheme.labelMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
        Expanded(child: Divider(color: AppColors.outlineVariant.withValues(alpha: 0.6))),
      ],
    );
  }

  Widget _buildToggleRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? 'New here?' : 'Already registered?',
          style: theme.textTheme.bodyMedium,
        ),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null;
                  }),
          child: Text(
            _isLogin ? 'Create an account' : 'Log in',
            style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? hintText,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        counterText: maxLength != null ? '' : null,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: AppColors.onSurfaceVariant,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
    );
  }
}

/// Soft, ambient gradient backdrop on the auth screen.
class _AuroraBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryContainer.withValues(alpha: 0.8),
                      AppColors.primaryContainer.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -160,
              left: -60,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondaryContainer.withValues(alpha: 0.6),
                      AppColors.secondaryContainer.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
