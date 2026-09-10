import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _severity = 'medium';
  File? _screenshot;
  bool _isSubmitting = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920);
    if (!mounted) return;
    if (image != null) {
      setState(() => _screenshot = File(image.path));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);

    try {
      final api = getIt<ApiClient>();

      final result = await api.submitBugReport(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        severity: _severity,
        component: 'Axon POS',
        attachment: _screenshot,
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showGlassSnackBar(
        context,
        'Could not submit bug report. Check your connection and try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;

    return Scaffold(
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surface,
      appBar: AppBar(
        backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Report a Bug',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: _result != null ? _buildResult(isDark) : _buildForm(isDark),
      ),
    );
  }

  Widget _buildResult(bool isDark) {
    final success = _result?['success'] == true;
    final hulyUrl = _result?['hulyUrl'] as String?;
    final hulyIssueId = _result?['hulyIssueId'] as String?;
    final error = _result?['error'] as String?;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: success ? DesignColors.success : DesignColors.error,
              size: 64,
            ),
            const SizedBox(height: DesignSpacing.xl),
            Text(
              success ? 'Bug Report Submitted' : 'Submission Failed',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            Text(
              success
                  ? 'Your report has been logged as $hulyIssueId. We\'ll review it shortly.'
                  : error ?? 'Something went wrong. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (success && hulyUrl != null) ...[
              const SizedBox(height: DesignSpacing.sm),
              TextButton(
                onPressed: () {/* TODO: open URL */},
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, DesignSpacing.xl + 24),
                ),
                child: const Text('View in Huly', style: TextStyle(color: DesignColors.accent)),
              ),
            ],
            const SizedBox(height: DesignSpacing.xxl),
            StaggeredItem(
              itemKey: 'bug-result-action',
              index: 0,
              child: GradientButton(
                label: success ? 'Done' : 'Try Again',
                onPressed: () => success ? context.pop() : setState(() => _result = null),
                height: DesignSpacing.xl + 28,
                borderRadius: DesignSpacing.radiusMd,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    return SingleChildScrollView(
      // Keyboard-safe: lift the form above the keyboard as fields focus.
      padding: EdgeInsets.fromLTRB(
        DesignSpacing.lg,
        DesignSpacing.lg,
        DesignSpacing.lg,
        DesignSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: _inputDecoration('Title', 'Brief summary of the issue'),
              style: TextStyle(color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            const SizedBox(height: DesignSpacing.lg),

            // Severity
            Text(
              'Severity',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
              ),
            ),
            const SizedBox(height: DesignSpacing.sm),
            _buildSeveritySelector(),
            const SizedBox(height: DesignSpacing.lg),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: _inputDecoration('Description', 'Describe what happened, steps to reproduce, and expected behavior'),
              maxLines: 6,
              style: TextStyle(color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the issue' : null,
            ),
            const SizedBox(height: DesignSpacing.lg),

            // Screenshot
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickScreenshot,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(_screenshot != null ? 'Change Screenshot' : 'Add Screenshot'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignColors.accent,
                    side: const BorderSide(color: DesignColors.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignSpacing.radiusMd)),
                    minimumSize: const Size(64, DesignSpacing.xl + 24),
                  ),
                ),
                if (_screenshot != null) ...[
                  const SizedBox(width: DesignSpacing.md),
                  Expanded(
                    child: Text(
                      _screenshot!.path.split('/').last,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary,
                      ),
                    ),
                  ),
                  // >=44px tap target for removing the attached screenshot.
                  IconButton(
                    tooltip: 'Remove screenshot',
                    constraints: const BoxConstraints(
                        minWidth: DesignSpacing.xl + 24,
                        minHeight: DesignSpacing.xl + 24),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded, size: 18, color: DesignColors.error),
                    onPressed: () => setState(() => _screenshot = null),
                  ),
                ],
              ],
            ),
            const SizedBox(height: DesignSpacing.xxl),

            // Submit
            StaggeredItem(
              itemKey: 'bug-submit',
              index: 0,
              child: GradientButton(
                label: _isSubmitting ? 'Submitting…' : 'Submit Bug Report',
                icon: _isSubmitting ? null : Icons.bug_report_rounded,
                onPressed: _isSubmitting ? null : _submit,
                height: DesignSpacing.xxl + 28,
                borderRadius: DesignSpacing.radiusLg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeveritySelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final severities = [
      {'key': 'low', 'label': 'Low', 'color': DesignColors.info},
      {'key': 'medium', 'label': 'Medium', 'color': DesignColors.warning},
      {'key': 'high', 'label': 'High', 'color': DesignColors.error},
      {'key': 'critical', 'label': 'Critical', 'color': Colors.red.shade900},
    ];

    return Row(
      children: severities.map((s) {
        final selected = _severity == s['key'];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _severity = s['key'] as String),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                child: Container(
                  // >=44px tap target.
                  constraints: const BoxConstraints(
                    minHeight: DesignSpacing.xl + 24,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: DesignSpacing.sm),
                  decoration: BoxDecoration(
                    color: selected
                        ? (s['color'] as Color).withValues(alpha: 0.15)
                        : (isDark ? DesignColors.darkSurfaceElevated : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    border: Border.all(
                      color: selected ? s['color'] as Color : (isDark ? DesignColors.darkBorder : Colors.grey.shade300),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    s['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? s['color'] as Color : (isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
      hintStyle: TextStyle(color: isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary),
      filled: true,
      fillColor: isDark ? DesignColors.darkSurfaceElevated : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        borderSide: BorderSide(color: isDark ? DesignColors.darkBorder : Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        borderSide: BorderSide(color: isDark ? DesignColors.darkBorder : Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        borderSide: const BorderSide(color: DesignColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(DesignSpacing.lg - DesignSpacing.xs),
    );
  }
}
