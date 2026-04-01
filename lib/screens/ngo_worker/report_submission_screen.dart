import 'package:flutter/material.dart';
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

  void _toggleMedia(String url) {
    setState(() {
      if (_mediaUrls.contains(url)) {
        _mediaUrls.remove(url);
      } else {
        _mediaUrls.add(url);
      }
    });
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
                'Camera', 
                _mediaUrls.any((u) => u.contains('photo')) ? AppColors.primary : AppColors.surfaceContainerHigh,
                () => _toggleMedia('https://example.com/mock_field_photo.jpg'),
                'https://example.com/mock_field_photo.jpg'
              ).animate().fadeIn(delay: 150.ms).scaleXY(begin: 0.9),
              _sourceCard(
                Icons.mic, 
                'Voice', 
                _mediaUrls.any((u) => u.contains('voice')) ? AppColors.primary : AppColors.surfaceContainerHigh,
                () => _toggleMedia('https://example.com/mock_audio_note.mp3'),
                'https://example.com/mock_audio_note.mp3'
              ).animate().fadeIn(delay: 200.ms).scaleXY(begin: 0.9),
              _sourceCard(Icons.edit_note, 'Text', AppColors.surfaceContainerHigh, () {}, '')
                  .animate().fadeIn(delay: 250.ms).scaleXY(begin: 0.9),
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
        ],
      ),
    );
  }

  Widget _sourceCard(IconData icon, String label, Color bgColor, VoidCallback onTap, String url) {
    final theme = Theme.of(context);
    final isSelected = _mediaUrls.contains(url);
    final contentColor = isSelected ? Colors.white : AppColors.onSurface;
    
    Widget cardChild = Container(
      width: (MediaQuery.of(context).size.width - 48 - 32) / 3,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: isSelected ? [BoxShadow(color: bgColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))] : [],
        border: Border.all(color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent),
      ),
      child: Column(
        children: [
          Icon(icon, color: contentColor, size: 32),
          const SizedBox(height: 12),
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: contentColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );

    if (isSelected && url.isNotEmpty) {
      // Wrap with drag to dismiss
      cardChild = Dismissible(
        key: Key(url),
        direction: DismissDirection.vertical,
        onDismissed: (_) {
          setState(() {
            _mediaUrls.remove(url);
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label media removed')));
        },
        child: cardChild,
      ).animate().shake(hz: 3, curve: Curves.easeOut); // subtle shake to indicate it's active
    }

    return GestureDetector(
      onTap: onTap,
      child: cardChild,
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
