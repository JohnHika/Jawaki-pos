import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';

/// A full-screen staff invitation form that loads available roles and branches
/// on init, then lets the owner fill in email, name, and pick a role + branch
/// before sending the invitation via the API.
class InviteStaffScreen extends StatefulWidget {
  const InviteStaffScreen({super.key});

  @override
  State<InviteStaffScreen> createState() => _InviteStaffScreenState();
}

class _InviteStaffScreenState extends State<InviteStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  ApiClient get _api => getIt<ApiClient>();

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _branches = [];
  String? _selectedRoleId;
  String? _selectedBranchId;
  bool _isLoading = true;
  Object? _loadError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await Future.wait([_api.getRoles(), _api.getBranches()]);
      if (!mounted) return;
      final roles =
          data[0].whereType<Map>().map(Map<String, dynamic>.from).toList();
      final branches =
          data[1].whereType<Map>().map(Map<String, dynamic>.from).toList();
      setState(() {
        _roles = roles;
        _branches = branches;
        _selectedRoleId =
            roles.isNotEmpty ? roles.first['id'].toString() : null;
        _selectedBranchId =
            branches.isNotEmpty ? branches.first['id'].toString() : null;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedRoleId == null || _selectedBranchId == null) {
      showGlassSnackBar(
        context,
        'Please select both a role and a branch.',
        icon: Icons.info_outline_rounded,
        color: DesignColors.warning,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _api.createStaffInvitation(
        email: _emailController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        roleId: _selectedRoleId!,
        branchId: _selectedBranchId!,
      );
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Invitation sent. Ask your team member to use their email code.',
        icon: Icons.check_circle_outline_rounded,
        color: DesignColors.success,
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'We could not send the invitation. Check the details and try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Scaffold(
        backgroundColor: DesignColors.darkBg,
        appBar: AppBar(
          backgroundColor: DesignColors.darkSurface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: DesignColors.darkTextPrimary),
            onPressed: () => context.pop(),
          ),
          title: const Text(
            'Invite Staff',
            style: TextStyle(
              color: DesignColors.darkTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: DesignColors.accent),
      );
    }
    if (_loadError != null) {
      return _loadFailure();
    }
    if (_roles.isEmpty || _branches.isEmpty) {
      return _emptyState();
    }
    return _buildForm();
  }

  Widget _loadFailure() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: DesignColors.warning, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load roles and branches',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DesignColors.darkTextSecondary),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: _loadData,
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: DesignColors.warning, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Setup required',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add at least one role and one active branch before inviting staff.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DesignColors.darkTextSecondary),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Go Back',
              icon: Icons.arrow_back_rounded,
              onPressed: () => context.pop(),
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Icon(Icons.person_add_alt_1_rounded,
                color: DesignColors.brand, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Invite a team member',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Their email will receive a time-limited verification code to accept the invitation.',
              style: TextStyle(
                color: DesignColors.darkTextSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // First name
            _buildField(
              controller: _firstNameController,
              label: 'First name',
              icon: Icons.person_outline_rounded,
              validator: _required,
            ),
            const SizedBox(height: 14),

            // Last name
            _buildField(
              controller: _lastNameController,
              label: 'Last name',
              icon: Icons.person_outline_rounded,
              validator: _required,
            ),
            const SizedBox(height: 14),

            // Email
            _buildField(
              controller: _emailController,
              label: 'Email address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
            const SizedBox(height: 14),

            // Role dropdown
            _buildDropdown(
              label: 'Role',
              value: _selectedRoleId,
              items: _roles,
              onChanged: (v) => setState(() => _selectedRoleId = v),
            ),
            const SizedBox(height: 14),

            // Branch dropdown
            _buildDropdown(
              label: 'Branch',
              value: _selectedBranchId,
              items: _branches,
              onChanged: (v) => setState(() => _selectedBranchId = v),
            ),
            const SizedBox(height: 28),

            // Submit button
            GradientButton(
              label: 'Send verified invitation',
              icon: Icons.send_rounded,
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
              height: 54,
              borderRadius: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(color: DesignColors.darkTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: DesignColors.darkTextSecondary),
        prefixIcon: Icon(icon, color: DesignColors.darkTextSecondary),
        filled: true,
        fillColor: DesignColors.darkSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.error),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      onChanged: onChanged,
      dropdownColor: DesignColors.darkSurfaceElevated,
      style: const TextStyle(color: DesignColors.darkTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: DesignColors.darkTextSecondary),
        prefixIcon: Icon(
          label == 'Role' ? Icons.badge_outlined : Icons.store_outlined,
          color: DesignColors.darkTextSecondary,
        ),
        filled: true,
        fillColor: DesignColors.darkSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.accent, width: 2),
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem(
                value: item['id'].toString(),
                child: Text(item['name']?.toString() ?? 'Unnamed'),
              ))
          .toList(),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value.trim())
        ? null
        : 'Enter a valid email address';
  }
}
