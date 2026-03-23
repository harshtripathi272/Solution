import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';

class ReportSubmissionScreen extends StatefulWidget {
  const ReportSubmissionScreen({super.key});

  @override
  State<ReportSubmissionScreen> createState() => _ReportSubmissionScreenState();
}

class _ReportSubmissionScreenState extends State<ReportSubmissionScreen> {
  String _needType = AppConstants.needTypes.first;
  String _urgency = 'Medium';
  final _descCtrl = TextEditingController();
  
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_submitted) return _buildSuccessView(theme);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report a Need', style: theme.textTheme.displayMedium),
          const SizedBox(height: 12),
          Text('Provide context so we can mobilize the right network.', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 32),
          
          Text('Capture Source', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sourceCard(Icons.camera_alt, 'Camera', AppColors.primaryContainer),
              _sourceCard(Icons.mic, 'Voice', AppColors.tertiary),
              _sourceCard(Icons.edit_note, 'Text', AppColors.surfaceContainerHigh),
            ],
          ),
          const SizedBox(height: 48),
          
          Text('Details', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          
          // Organic form fields
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _needType,
                isExpanded: true,
                dropdownColor: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
                style: theme.textTheme.bodyLarge,
                items: AppConstants.needTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _needType = v!),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          Text('Urgency', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.onSurface)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppConstants.urgencyLevels.map((u) {
                final active = _urgency == u;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _urgency = u),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: active ? AppDecorations.activeChip : AppDecorations.inactiveChip,
                      child: Text(
                        u, 
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: active ? AppColors.onTertiary : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: TextField(
              controller: _descCtrl,
              maxLines: 5,
              decoration: InputDecoration.collapsed(
                hintText: 'Describe the situation...',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
          ),
          
          const SizedBox(height: 48),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _submitted = true),
              child: const Text('Submit Report'),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _sourceCard(IconData icon, String label, Color bgColor) {
    final theme = Theme.of(context);
    final active = bgColor != AppColors.surfaceContainerHigh;
    final contentColor = active ? AppColors.onPrimary : AppColors.onSurface;
    
    return Container(
      width: (MediaQuery.of(context).size.width - 48 - 32) / 3, // 48 margins, 32 inner spacing
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: active ? AppDecorations.ambientShadow : [],
      ),
      child: Column(
        children: [
          Icon(icon, color: contentColor, size: 32),
          const SizedBox(height: 12),
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: contentColor, fontWeight: FontWeight.w600)),
        ],
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
              child: const Icon(Icons.check, color: AppColors.success, size: 64),
            ),
            const SizedBox(height: 32),
            Text('Report Logged', style: theme.textTheme.displayMedium),
            const SizedBox(height: 16),
            Text('We have analyzed the context and dispatched alerts to the relevant networks.', 
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceContainerLow, foregroundColor: AppColors.onSurface),
              onPressed: () => setState(() { _submitted = false; _descCtrl.clear(); }),
              child: const Text('New Submission'),
            ),
          ],
        ),
      ),
    );
  }
}
