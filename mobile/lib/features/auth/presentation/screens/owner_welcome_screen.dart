import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
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
    final result = await context.push<bool>('/invite-staff');
    if (result == true && mounted) {
      await _updateStep('invite_staff', 'COMPLETED');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.companyName?.trim();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOnboarding,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(DesignSpacing.xl,
                DesignSpacing.xxl + 4, DesignSpacing.xl, DesignSpacing.xxl + 4),
            children: [
              // First-mount entrance choreography: each onboarding section
              // fades/rises in once, staggered (see StaggeredItem). Keys are
              // stable so pull-to-refresh never replays them.
              const StaggeredItem(
                itemKey: 'welcome-mark',
                child: Icon(Icons.storefront_rounded,
                    color: DesignColors.brand, size: 52),
              ),
              const SizedBox(height: DesignSpacing.lg),
              StaggeredItem(
                itemKey: 'welcome-title',
                index: 1,
                child: Text(
                  name?.isNotEmpty == true
                      ? 'Welcome, $name'
                      : 'Welcome to Axon POS',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      color: DesignColors.darkTextPrimary,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: DesignSpacing.sm),
              StaggeredItem(
                itemKey: 'welcome-subtitle',
                index: 2,
                child: Text(
                  'Your workspace is ready. Complete the essentials now or safely return later.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: DesignColors.darkTextSecondary, height: 1.4),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg + 2),
              StaggeredItem(
                itemKey: 'welcome-features',
                index: 3,
                child: _featureStrip(),
              ),
              const SizedBox(height: DesignSpacing.xl + 4),
              if (_isLoading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(DesignSpacing.xxxl),
                        child: CircularProgressIndicator()))
              else if (_loadError != null)
                _loadFailure()
              else
                _checklist(),
              const SizedBox(height: DesignSpacing.lg + 2),
              // No stagger delay here: this CTA sits below the fold, and a
              // delayed first-mount entrance that plays offscreen keeps a
              // timer pending (also breaks flutter_test timer invariants).
              // The step cards above carry the staggered reveal.
              GradientButton(
                label: 'Add Your First Product',
                icon: Icons.add_box_outlined,
                onPressed: _addFirstProduct,
                height: 56,
                borderRadius: 14,
              ),
              const SizedBox(height: DesignSpacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 48),
                ),
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: DesignColors.darkTextPrimary,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: DesignSpacing.sm),
      LinearProgressIndicator(
          value: steps.isEmpty ? 0 : completed / steps.length,
          minHeight: DesignSpacing.sm - 1,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusFull - 1)),
      const SizedBox(height: DesignSpacing.lg - 2),
      ...steps.asMap().entries.map(
            (entry) => StaggeredItem(
              itemKey: 'welcome-step-${entry.value['key'] ?? entry.key}',
              index: entry.key,
              child: _stepCard(entry.value),
            ),
          ),
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
      margin: const EdgeInsets.only(bottom: DesignSpacing.md - 2),
      padding: const EdgeInsets.all(DesignSpacing.lg - 2),
      decoration: BoxDecoration(
        color: DesignColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: DesignColors.darkTextPrimary)),
                Text(detail.subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: DesignColors.darkTextSecondary)),
              ])),
          _statusBadge(status),
        ]),
        if (!isDone) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: key == 'invite_staff'
                  ? GradientButton(
                      label: detail.actionLabel,
                      icon: Icons.send_rounded,
                      onPressed: isBusy ? null : () => _performStepAction(key),
                      height: 44,
                      borderRadius: 10,
                    )
                  : OutlinedButton(
                      onPressed: isBusy ? null : () => _performStepAction(key),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(detail.actionLabel),
                    ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
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
          borderRadius: BorderRadius.circular(DesignSpacing.radiusFull)),
      child: Text(status.toLowerCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
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
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: DesignColors.darkTextSecondary))
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
