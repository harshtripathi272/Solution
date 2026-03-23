import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/app_state.dart';
import '../../models/field_report_model.dart';

class ReportSubmissionScreen extends StatefulWidget {
  const ReportSubmissionScreen({super.key});

  @override
  State<ReportSubmissionScreen> createState() => _ReportSubmissionScreenState();
}

class _ReportSubmissionScreenState extends State<ReportSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  String _needType = AppConstants.needTypes.first;
  String _urgency = 'Medium';
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _wardCtrl = TextEditingController();
  final _peopleCtrl = TextEditingController();
  bool _submitted = false;
  bool _processing = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _wardCtrl.dispose();
    _peopleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccessView();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FadeInDown(
            duration: const Duration(milliseconds: 600),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Submit Field Report', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Report community needs from the field', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 20),

          // Source selection
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 100),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: AppDecorations.glassCard,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Data Source', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _sourceBtn(Icons.camera_alt, 'Camera', AppColors.primary, () => _simAI()),
                  _sourceBtn(Icons.mic, 'Voice', AppColors.accent, () => _simAI()),
                  _sourceBtn(Icons.chat, 'WhatsApp', AppColors.success, () => _simAI()),
                  _sourceBtn(Icons.edit_note, 'Text', AppColors.info, null),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // AI Processing indicator
          if (_processing)
            FadeIn(child: Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.primary.withValues(alpha: 0.05)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gemini AI Processing...', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('Extracting structured data from input', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ])),
              ]),
            )),

          // Need type
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 200),
            child: _buildDropdown('Need Type', _needType, AppConstants.needTypes, (v) => setState(() => _needType = v!)),
          ),
          const SizedBox(height: 14),

          // Urgency
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 250),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Urgency Level', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(children: AppConstants.urgencyLevels.map((u) {
                final selected = _urgency == u;
                final c = _urgCol(u);
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _urgency = u),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? c.withValues(alpha: 0.2) : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? c : AppColors.glassBorder),
                    ),
                    child: Center(child: Text(u, style: TextStyle(color: selected ? c : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600))),
                  ),
                ));
              }).toList()),
            ]),
          ),
          const SizedBox(height: 14),

          // Description
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 300),
            child: _buildField('Description', 'Describe the community need in detail...', _descCtrl, maxLines: 4),
          ),
          const SizedBox(height: 14),

          // Location & Ward
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 350),
            child: Row(children: [
              Expanded(child: _buildField('Location', 'Area, City', _locationCtrl)),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: _buildField('Ward', 'Ward 14', _wardCtrl)),
            ]),
          ),
          const SizedBox(height: 14),

          // People affected
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 400),
            child: _buildField('Estimated People Affected', '200', _peopleCtrl, keyboardType: TextInputType.number),
          ),
          const SizedBox(height: 24),

          // Submit
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 500),
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.send, size: 18),
                SizedBox(width: 8),
                Text('Submit Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(child: FadeIn(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle, color: AppColors.success, size: 64),
        ),
        const SizedBox(height: 24),
        Text('Report Submitted!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Gemini AI is generating tasks and matching volunteers', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
            SizedBox(width: 6),
            Text('AI auto-assigned to 2 matched volunteers', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => setState(() { _submitted = false; _descCtrl.clear(); _locationCtrl.clear(); _wardCtrl.clear(); _peopleCtrl.clear(); }),
          child: const Text('Submit Another Report'),
        ),
      ]),
    )));
  }

  Widget _sourceBtn(IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: value,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
        dropdownColor: AppColors.bgCard,
        decoration: const InputDecoration(),
      ),
    ]);
  }

  Widget _buildField(String label, String hint, TextEditingController ctrl, {int maxLines = 1, TextInputType? keyboardType}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      TextFormField(controller: ctrl, maxLines: maxLines, keyboardType: keyboardType, decoration: InputDecoration(hintText: hint)),
    ]);
  }

  void _simAI() {
    setState(() => _processing = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() {
        _processing = false;
        _needType = 'Food & Nutrition';
        _urgency = 'Critical';
        _descCtrl.text = 'AI-extracted: 150+ families facing food shortage in low-lying area due to heavy rain. Community kitchen flooded.';
        _locationCtrl.text = 'Sion, Mumbai';
        _wardCtrl.text = 'Ward 15';
        _peopleCtrl.text = '600';
      });
    });
  }

  void _submit() {
    final state = context.read<AppState>();
    state.addFieldReport(FieldReport(
      ngoId: 'ngo-goonj', submittedBy: state.currentUser.name,
      needType: _needType, description: _descCtrl.text,
      location: _locationCtrl.text, latitude: 19.04, longitude: 72.86,
      urgency: _urgency, estimatedPeopleAffected: int.tryParse(_peopleCtrl.text) ?? 0,
      source: ReportSource.text, ward: _wardCtrl.text,
    ));
    setState(() => _submitted = true);
  }

  Color _urgCol(String u) => switch (u) {
    'Critical' => AppColors.urgencyCritical, 'High' => AppColors.urgencyHigh,
    'Medium' => AppColors.urgencyMedium, _ => AppColors.urgencyLow,
  };
}
