import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/widgets/add_edit_product_sheet.dart';

typedef OnboardingLoader = Future<Map<String, dynamic>> Function();
typedef OnboardingUpdater = Future<Map<String, dynamic>> Function(
    String key, String status);

class OwnerWelcomeScreen extends StatefulWidget {
  const OwnerWelcomeScreen({
    super.key,
    this.companyName,
    this.onboardingLoader,
    this.onboardingUpdater,
  });

  final String? companyName;
  final OnboardingLoader? onboardingLoader;
  final OnboardingUpdater? onboardingUpdater;

  @override
  State<OwnerWelcomeScreen> createState() => _OwnerWelcomeScreenState();
}

class _OwnerWelcomeScreenState extends State<OwnerWelcomeScreen> {
  Map<String, dynamic>? _onboarding;
  Object? _loadError;
  bool _isLoading = true;
  final Set<String> _updatingKeys = {};

  ApiClient get _api => getIt<ApiClient>();

  @override
  void initState() {
    super.initState();
    _loadOnboarding();
  }

  Future<void> _loadOnboarding() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result =
          await (widget.onboardingLoader?.call() ?? _api.getTenantOnboarding());
      if (mounted) setState(() => _onboarding = result);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _steps {
    final source = _onboarding?['steps'];
    if (source is! List) return const [];
    return source
        .whereType<Map>()
        .map((step) => Map<String, dynamic>.from(step))
        .toList();
  }

  Future<void> _updateStep(String key, String status) async {
    if (_updatingKeys.contains(key)) return;
    setState(() => _updatingKeys.add(key));
    try {
      final updated = await (widget.onboardingUpdater?.call(key, status) ??
          _api.updateTenantOnboardingStep(key: key, status: status));
      if (mounted) setState(() => _onboarding = updated);
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'We could not update this checklist item. Try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingKeys.remove(key));
    }
  }

  Future<void> _addFirstProduct() async {
    await GlassBottomSheet.show(
      context,
      title: 'Add Product',
      initialSize: 0.85,
      maxSize: 0.95,
      scrollable: true,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const AddEditProductSheet(),
      ),
    );
  }

  Future<void> _showStaffInvite() async {
    final formKey = GlobalKey<FormState>();
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final email = TextEditingController();
    try {
      final data = await Future.wait([_api.getRoles(), _api.getBranches()]);
      if (!mounted) return;
      final roles =
          data[0].whereType<Map>().map(Map<String, dynamic>.from).toList();
      final branches =
          data[1].whereType<Map>().map(Map<String, dynamic>.from).toList();
      if (roles.isEmpty || branches.isEmpty) {
        showGlassSnackBar(
          context,
          'Add at least one role and active branch before inviting staff.',
          icon: Icons.info_outline_rounded,
          color: DesignColors.warning,
        );
        return;
      }
      String roleId = roles.first['id'].toString();
      String branchId = branches.first['id'].toString();
      var isSubmitting = false;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: DesignColors.darkSurface,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Invite a team member',
                      style: TextStyle(
                          color: DesignColors.darkTextPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                      'Their email will receive a time-limited verification code to accept the invitation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DesignColors.darkTextSecondary)),
                  const SizedBox(height: 20),
                  _inviteField(firstName, 'First name',
                      Icons.person_outline_rounded, _required),
                  const SizedBox(height: 12),
                  _inviteField(lastName, 'Last name',
                      Icons.person_outline_rounded, _required),
                  const SizedBox(height: 12),
                  _inviteField(email, 'Email address', Icons.email_outlined,
                      _emailValidator,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _inviteDropdown(
                    label: 'Role',
                    value: roleId,
                    items: roles,
                    onChanged: (value) => setSheetState(() => roleId = value!),
                  ),
                  const SizedBox(height: 12),
                  _inviteDropdown(
                    label: 'Branch',
                    value: branchId,
                    items: branches,
                    onChanged: (value) =>
                        setSheetState(() => branchId = value!),
                  ),
                  const SizedBox(height: 20),
                  GradientButton(
                    label: 'Send verified invitation',
                    icon: Icons.send_rounded,
                    isLoading: isSubmitting,
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            setSheetState(() => isSubmitting = true);
                            try {
                              await _api.createStaffInvitation(
                                email: email.text.trim(),
                                firstName: firstName.text.trim(),
                                lastName: lastName.text.trim(),
                                roleId: roleId,
                                branchId: branchId,
                              );
                              if (!sheetContext.mounted) return;
                              Navigator.of(sheetContext).pop();
                              await _updateStep('invite_staff', 'COMPLETED');
                              if (mounted) {
                                showGlassSnackBar(this.context,
                                    'Invitation ready. Ask your team member to use their email code.',
                                    icon: Icons.check_circle_outline_rounded,
                                    color: DesignColors.success);
                              }
                            } catch (_) {
                              if (sheetContext.mounted) {
                                showGlassSnackBar(sheetContext,
                                    'We could not send the invitation. Check the details and try again.',
                                    icon: Icons.error_outline_rounded,
                                    color: DesignColors.error);
                              }
                              setSheetState(() => isSubmitting = false);
                            }
                          },
                    height: 54,
                    borderRadius: 14,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    } finally {
      firstName.dispose();
      lastName.dispose();
      email.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.companyName?.trim();
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOnboarding,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            children: [
              const Icon(Icons.storefront_rounded,
                  color: DesignColors.brand, size: 52),
              const SizedBox(height: 16),
              Text(
                name?.isNotEmpty == true
                    ? 'Welcome, $name'
                    : 'Welcome to Axon POS',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your workspace is ready. Complete the essentials now or safely return later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: DesignColors.darkTextSecondary, height: 1.4),
              ),
              const SizedBox(height: 18),
              _featureStrip(),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator()))
              else if (_loadError != null)
                _loadFailure()
              else
                _checklist(),
              const SizedBox(height: 18),
              GradientButton(
                label: 'Add Your First Product',
                icon: Icons.add_box_outlined,
                onPressed: _addFirstProduct,
                height: 56,
                borderRadius: 14,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Finish later'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureStrip() => const Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _FeatureChip(
              icon: Icons.point_of_sale_rounded, label: 'Sell products'),
          _FeatureChip(icon: Icons.inventory_2_outlined, label: 'Track stock'),
          _FeatureChip(icon: Icons.insights_outlined, label: 'See insights'),
        ],
      );

  Widget _loadFailure() => Center(
        child: Column(children: [
          const Icon(Icons.cloud_off_outlined,
              color: DesignColors.warning, size: 36),
          const SizedBox(height: 12),
          const Text('Could not load your onboarding checklist',
              style: TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
              'You can still add products now and retry the checklist when online.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DesignColors.darkTextSecondary)),
          TextButton.icon(
              onPressed: _loadOnboarding,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry')),
        ]),
      );

  Widget _checklist() {
    final steps = _steps;
    final completed =
        steps.where((step) => step['status'] == 'COMPLETED').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$completed of ${steps.length} completed',
          style: const TextStyle(
              color: DesignColors.darkTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      LinearProgressIndicator(
          value: steps.isEmpty ? 0 : completed / steps.length,
          minHeight: 7,
          borderRadius: BorderRadius.circular(9)),
      const SizedBox(height: 14),
      ...steps.map(_stepCard),
    ]);
  }

  Widget _stepCard(Map<String, dynamic> step) {
    final key = step['key']?.toString() ?? '';
    final status = step['status']?.toString() ?? 'PENDING';
    final detail = _details[key] ??
        _StepDetail(key, 'Complete setup', 'Review this workspace setting.',
            Icons.checklist_rounded);
    final isDone = status == 'COMPLETED';
    final isBusy = _updatingKeys.contains(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDone
                ? DesignColors.success.withValues(alpha: 0.45)
                : DesignColors.darkBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isDone ? Icons.check_circle_rounded : detail.icon,
              color: isDone ? DesignColors.success : DesignColors.accent),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(detail.title,
                    style: const TextStyle(
                        color: DesignColors.darkTextPrimary,
                        fontWeight: FontWeight.w700)),
                Text(detail.subtitle,
                    style: const TextStyle(
                        color: DesignColors.darkTextSecondary, fontSize: 12)),
              ])),
          _statusBadge(status),
        ]),
        if (!isDone) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: isBusy ? null : () => _performStepAction(key),
              child: Text(detail.actionLabel),
            )),
            const SizedBox(width: 8),
            TextButton(
              onPressed: isBusy ? null : () => _updateStep(key, 'DEFERRED'),
              child: const Text('Defer'),
            ),
          ]),
        ],
      ]),
    );
  }

  Future<void> _performStepAction(String key) async {
    switch (key) {
      case 'invite_staff':
        await _showStaffInvite();
      case 'add_catalog':
        await _addFirstProduct();
      case 'activate_payment':
        if (mounted) context.go('/payments');
      default:
        await _updateStep(key, 'COMPLETED');
    }
  }

  Widget _statusBadge(String status) {
    final color = status == 'COMPLETED'
        ? DesignColors.success
        : status == 'DEFERRED'
            ? DesignColors.warning
            : DesignColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99)),
      child: Text(status.toLowerCase(),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _inviteField(TextEditingController controller, String label,
          IconData icon, String? Function(String?) validator,
          {TextInputType? keyboardType}) =>
      TextFormField(
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
              borderSide: const BorderSide(color: DesignColors.darkBorder)),
        ),
      );

  Widget _inviteDropdown(
          {required String label,
          required String value,
          required List<Map<String, dynamic>> items,
          required ValueChanged<String?> onChanged}) =>
      DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        onChanged: onChanged,
        dropdownColor: DesignColors.darkSurfaceElevated,
        style: const TextStyle(color: DesignColors.darkTextPrimary),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: DesignColors.darkTextSecondary),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        items: items
            .map((item) => DropdownMenuItem(
                value: item['id'].toString(),
                child: Text(item['name']?.toString() ?? 'Unnamed')))
            .toList(),
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  String? _emailValidator(String? value) =>
      RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value?.trim() ?? '')
          ? null
          : 'Enter a valid email address';
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: DesignColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: DesignColors.brand),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: DesignColors.darkTextSecondary, fontSize: 12))
        ]),
      );
}

class _StepDetail {
  const _StepDetail(this.key, this.title, this.subtitle, this.icon,
      {this.actionLabel = 'Mark complete'});
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
}

const _details = <String, _StepDetail>{
  'confirm_business': _StepDetail('confirm_business', 'Confirm your business',
      'Review the owner and business details.', Icons.business_center_outlined),
  'configure_branch': _StepDetail('configure_branch', 'Configure your branch',
      'Confirm the location where sales begin.', Icons.store_outlined),
  'invite_staff': _StepDetail(
      'invite_staff',
      'Invite your team',
      'Send a verified invitation with a role and branch.',
      Icons.group_add_outlined,
      actionLabel: 'Invite staff'),
  'add_catalog': _StepDetail('add_catalog', 'Add your catalog',
      'Create products before your first sale.', Icons.inventory_2_outlined,
      actionLabel: 'Add product'),
  'activate_payment': _StepDetail('activate_payment', 'Set up payments',
      'Choose and configure how customers can pay.', Icons.payments_outlined,
      actionLabel: 'Open payments'),
};
