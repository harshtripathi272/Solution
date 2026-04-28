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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stepped Progress Indicator
          Row(
            children: List.generate(3, (index) {
              final step = index + 1;
              final isActive = step <= currentStep;
              return Expanded(
                child: AnimatedContainer(
                  duration: 300.ms,
                  curve: Curves.easeOutCirc,
                  margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ).animate().fadeIn().slideY(begin: -0.5),
          const SizedBox(height: 32),

          Text('Report a Need', style: theme.textTheme.displayMedium)
              .animate().fadeIn().slideX(begin: -0.1),
          const SizedBox(height: 12),
          Text('Provide context so we can mobilize the right network.', style: theme.textTheme.bodyLarge)
              .animate().fadeIn(delay: 50.ms).slideX(begin: -0.1),
          const SizedBox(height: 32),
          
          Text('Capture Source', style: theme.textTheme.headlineSmall)
              .animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 16),
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
          const SizedBox(height: 48),
          
          Text('Details', style: theme.textTheme.headlineSmall)
              .animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 16),
          
          // Organic form fields
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppDecorations.ambientShadow,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _needType,
                isExpanded: true,
                dropdownColor: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
                style: theme.textTheme.labelLarge,
                items: AppConstants.needTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _needType = v!),
              ),
            ),
          ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1),
          const SizedBox(height: 24),
          
          Text('Urgency', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurface))
              .animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 12),
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
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _urgency = u),
                    child: AnimatedContainer(
                      duration: 300.ms,
                      curve: Curves.easeOutCirc,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: active 
                          ? AppDecorations.activeChip.copyWith(color: activeColor)
                          : AppDecorations.inactiveChip,
                      child: Text(
                        u, 
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: active ? Colors.white : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: (450 + idx * 50).ms).scaleXY(begin: 0.8, curve: Curves.easeOutBack);
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppDecorations.ambientShadow,
            ),
            child: TextField(
              controller: _descCtrl,
              focusNode: _descFocus,
              maxLines: 5,
              enabled: !_isSubmitting,
              onChanged: (_) => setState(() {}), // To trigger step updates
              decoration: InputDecoration.collapsed(
                hintText: 'Describe the situation in detail...',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
          ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.1),
          
          const SizedBox(height: 48),
          
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTapDown: (_) {
                if (_isSubmitting) return;
                // Add tiny satisfying scale on touch down if we wanted, but ElevatedButton natively splashes
              },
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmission,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: AppColors.primary.withValues(alpha: 0.5),
                ),
                child: _isSubmitting 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Report', style: TextStyle(fontSize: 16)),
              ),
            ).animate(target: _descCtrl.text.isNotEmpty ? 1 : 0).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 200.ms),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2),
          const SizedBox(height: 48),

          // Past reports
          Builder(builder: (ctx) {
            final reports = context.watch<AppState>().reports;
            if (reports.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 24),
                Text('Recent Submissions', style: theme.textTheme.headlineSmall)
                    .animate().fadeIn(delay: 400.ms),
                const SizedBox(height: 16),
                ...reports.take(5).map((report) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: AppDecorations.contentBlock,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _urgencyColor(report.urgency).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.description, color: _urgencyColor(report.urgency), size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(report.needType, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(report.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _urgencyColor(report.urgency).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(report.urgency, style: theme.textTheme.labelSmall?.copyWith(color: _urgencyColor(report.urgency))),
                      ),
                    ],
                  ),
                ).animate().fadeIn()),
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
    final bgColor = selected ? AppColors.primary : AppColors.surfaceContainerHigh;
    final contentColor = selected ? Colors.white : AppColors.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 48 - 32) / 3,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
          border: Border.all(
            color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: contentColor, size: 32),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: contentColor,
                fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check, color: AppColors.success, size: 64)
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 2.seconds),
            ).animate().scaleXY(curve: Curves.elasticOut, duration: 800.ms),
            const SizedBox(height: 32),
            Text('Report Logged', style: theme.textTheme.displayMedium)
                .animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
            const SizedBox(height: 16),
            Text('We have analyzed the context and dispatched alerts to the relevant networks.', 
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge)
                .animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceContainerLow, 
                foregroundColor: AppColors.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => setState(() { _submitted = false; _descCtrl.clear(); _mediaUrls.clear(); }),
              child: const Text('New Submission'),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }
}
