import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/app_state.dart';

class ReportSubmissionScreen extends StatefulWidget {
  const ReportSubmissionScreen({super.key});

  @override
  State<ReportSubmissionScreen> createState() => _ReportSubmissionScreenState();
}

class _ReportSubmissionScreenState extends State<ReportSubmissionScreen> {
  String _needType = AppConstants.needTypes.first;
  String _urgency = 'Medium';
  final _descCtrl = TextEditingController();
  final FocusNode _descFocus = FocusNode();
  
  bool _isSubmitting = false;
  bool _submitted = false;
  final List<String> _mediaUrls = [];

  Future<void> _handleSubmission() async {
    if (_descCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the situation')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    
    final appState = context.read<AppState>();
    final success = await appState.submitReport(
      needType: _needType,
      urgency: _urgency,
      description: _descCtrl.text,
      mediaUrls: _mediaUrls,
    );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        if (success) {
          _submitted = true;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submission failed. Please check your connection.')),
          );
        }
      });
    }
  }

  static const int _maxImageBytes = 900000;

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _showImagePickOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _capturePhoto();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhotoFromGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 82,
      );
      await _consumeImage(xfile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e')),
      );
    }
  }

  Future<void> _pickPhotoFromGallery() async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 82,
      );
      await _consumeImage(xfile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open gallery: $e')),
      );
    }
  }

  Future<void> _consumeImage(XFile? xfile) async {
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    if (bytes.length > _maxImageBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image too large — use a smaller photo (under ~900 KB).')),
      );
      return;
    }
    final ext = xfile.name.toLowerCase();
    final mime = ext.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    setState(() {
      _mediaUrls.removeWhere((u) => u.startsWith('data:image'));
      _mediaUrls.add(dataUrl);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo attached')),
    );
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (kIsWeb && file.bytes != null) {
        final b64 = base64Encode(file.bytes!);
        setState(() {
          _mediaUrls.removeWhere((u) => u.startsWith('data:audio'));
          _mediaUrls.add('data:audio/wav;base64,$b64');
        });
      } else if (file.path != null) {
        setState(() {
          _mediaUrls.removeWhere((u) => u.startsWith('file:') && _isAudioPath(u));
          _mediaUrls.add(Uri.file(file.path!).toString());
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio file attached')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach audio: $e')),
      );
    }
  }

  bool _isAudioPath(String u) {
    final lower = u.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac');
  }

  bool get _hasPhoto => _mediaUrls.any((u) => u.startsWith('data:image'));
  bool get _hasAudio =>
      _mediaUrls.any((u) => u.startsWith('data:audio') || _isAudioPath(u));

  @override
  void dispose() {
    _descCtrl.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_submitted) return _buildSuccessView(theme);

    int currentStep = 1;
    if (_mediaUrls.isNotEmpty) currentStep = 2;
    if (_descCtrl.text.isNotEmpty) currentStep = 3;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (index) {
              final step = index + 1;
              final isActive = step <= currentStep;
              return Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.standard,
                  curve: AppMotion.easeStandard,
                  margin: EdgeInsets.only(right: index < 2 ? AppSpacing.sm : 0),
                  height: 5,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : AppColors.surfaceContainerHigh,
                    borderRadius: AppRadius.pillR,
                  ),
                ),
              );
            }),
          ).animate().fadeIn(duration: AppMotion.standard),
          const SizedBox(height: AppSpacing.xl),
          Text('Report a need', style: theme.textTheme.headlineLarge)
              .animate().fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
          const SizedBox(height: 6),
          Text('Provide context so we can mobilize the right network.', style: theme.textTheme.bodyMedium)
              .animate(delay: 50.ms).fadeIn(duration: AppMotion.standard),
          const SizedBox(height: AppSpacing.xl),
          Text('Capture source', style: theme.textTheme.titleLarge)
              .animate(delay: 100.ms).fadeIn(duration: AppMotion.standard),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sourceCard(
                Icons.camera_alt,
                'Photo',
                _hasPhoto,
                _showImagePickOptions,
              ).animate().fadeIn(delay: 150.ms).scaleXY(begin: 0.9),
              _sourceCard(
                Icons.audiotrack,
                'Audio',
                _hasAudio,
                _pickAudio,
              ).animate().fadeIn(delay: 200.ms).scaleXY(begin: 0.9),
              _sourceCard(
                Icons.edit_note,
                'Details',
                false,
                () {
                  FocusScope.of(context).requestFocus(_descFocus);
                },
              ).animate().fadeIn(delay: 250.ms).scaleXY(begin: 0.9),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Details', style: theme.textTheme.titleLarge)
              .animate(delay: 300.ms).fadeIn(duration: AppMotion.standard),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _needType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Need type',
              prefixIcon: Icon(Icons.category_rounded),
            ),
            icon: const Icon(Icons.expand_more_rounded, color: AppColors.primary),
            items: AppConstants.needTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => v == null ? null : setState(() => _needType = v),
          ).animate(delay: 350.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
          const SizedBox(height: AppSpacing.lg),
          Text('Urgency', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurface))
              .animate(delay: 400.ms).fadeIn(duration: AppMotion.standard),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppConstants.urgencyLevels.map((u) {
                final active = _urgency == u;
                final idx = AppConstants.urgencyLevels.indexOf(u);
                
                // Switch color based on urgency mapping
                Color activeColor;
                switch (u) {
                  case 'Critical': activeColor = AppColors.urgencyCritical; break;
                  case 'High': activeColor = AppColors.urgencyHigh; break;
                  case 'Medium': activeColor = AppColors.urgencyMedium; break;
                  default: activeColor = AppColors.urgencyLow; break;
                }

                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: GestureDetector(
                    onTap: () => setState(() => _urgency = u),
                    child: AnimatedContainer(
                      duration: AppMotion.standard,
                      curve: AppMotion.easeStandard,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: active ? activeColor : AppColors.surfaceContainerLow,
                        borderRadius: AppRadius.pillR,
                        border: Border.all(
                          color: active ? activeColor : AppColors.outlineVariant.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        u,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: active ? Colors.white : AppColors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ).animate(delay: (450 + idx * 50).ms).fadeIn(duration: AppMotion.standard);
              }).toList(),
            ),
          ),
          
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _descCtrl,
            focusNode: _descFocus,
            maxLines: 5,
            enabled: !_isSubmitting,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Describe the situation in detail...',
              alignLabelWithHint: true,
            ),
          ).animate(delay: 550.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _handleSubmission,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_isSubmitting ? 'Submitting' : 'Submit report'),
            ),
          ).animate(delay: 600.ms).fadeIn(duration: AppMotion.standard).slideY(begin: 0.04, end: 0),
          const SizedBox(height: AppSpacing.xl),

          // Past reports
          Builder(builder: (ctx) {
            final reports = context.watch<AppState>().reports;
            if (reports.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 24),
                Text('Recent submissions', style: theme.textTheme.titleLarge)
                    .animate(delay: 400.ms).fadeIn(duration: AppMotion.standard),
                const SizedBox(height: AppSpacing.md),
                ...reports.take(5).map((report) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: AppDecorations.cardSubtle,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _urgencyColor(report.urgency).withValues(alpha: 0.12),
                          borderRadius: AppRadius.mdR,
                        ),
                        child: Icon(Icons.description_rounded, color: _urgencyColor(report.urgency), size: 20),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(report.needType, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(report.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                        decoration: BoxDecoration(
                          color: _urgencyColor(report.urgency).withValues(alpha: 0.12),
                          borderRadius: AppRadius.pillR,
                        ),
                        child: Text(
                          report.urgency,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _urgencyColor(report.urgency),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: AppMotion.standard)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Color _urgencyColor(String urgency) => switch (urgency.toLowerCase()) {
    'critical' => AppColors.error,
    'high' => AppColors.warning,
    'medium' => AppColors.info,
    _ => AppColors.onSurfaceVariant,
  };

  Widget _sourceCard(IconData icon, String label, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    final bgColor = selected ? AppColors.primary : AppColors.surfaceContainerLowest;
    final contentColor = selected ? Colors.white : AppColors.onSurface;
    final iconColor = selected ? Colors.white : AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.standard,
        curve: AppMotion.easeStandard,
        width: (MediaQuery.of(context).size.width - AppSpacing.xl * 2 - AppSpacing.sm * 2) / 3,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadius.lgR,
          boxShadow: selected ? AppElevation.floating : AppElevation.soft,
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.18) : AppColors.primaryContainer,
                borderRadius: AppRadius.mdR,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: contentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: [Color(0xFFCCFBF1), Color(0x00CCFBF1)],
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.32),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 42),
              ),
            ).animate().scaleXY(curve: AppMotion.easeBack, duration: AppMotion.emphasized),
            const SizedBox(height: AppSpacing.xl),
            Text('Report logged', style: theme.textTheme.headlineLarge)
                .animate(delay: 200.ms).fadeIn(duration: AppMotion.standard),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We have analyzed the context and dispatched alerts to the relevant networks.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ).animate(delay: 280.ms).fadeIn(duration: AppMotion.standard),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.tonalIcon(
              onPressed: () => setState(() {
                _submitted = false;
                _descCtrl.clear();
                _mediaUrls.clear();
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New submission'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
              ),
            ).animate(delay: 360.ms).fadeIn(duration: AppMotion.standard),
          ],
        ),
      ),
    );
  }
}
