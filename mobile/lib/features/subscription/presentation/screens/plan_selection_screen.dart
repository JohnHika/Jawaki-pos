import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../domain/subscription_plans.dart';

/// One-time setup fee (KES) charged during onboarding, before the 7-day
/// trial starts. Mirrors the backend onboarding fee — change both together.
const double _setupFeeKes = 35000;

/// "KSh 35,000" — [formatKes] digits with the KSh prefix used in prose copy.
String _setupFeeKsh() => formatKes(_setupFeeKes).replaceFirst('KES ', 'KSh ');

class PlanSelectionScreen extends ConsumerStatefulWidget {
  const PlanSelectionScreen({super.key, this.companyName});

  final String? companyName;

  @override
  ConsumerState<PlanSelectionScreen> createState() =>
      _PlanSelectionScreenState();
}

class _PlanSelectionScreenState extends ConsumerState<PlanSelectionScreen> {
  String? _selectedPlanId;
  bool _isSubmitting = false;
  String? _error;

  ApiClient get _apiClient => getIt<ApiClient>();

  Future<void> _startFreeTrial() async {
    if (_selectedPlanId == null) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Backend `VALID_PLANS` are uppercase (TRIAL/CORE/BUSINESS/ENTERPRISE)
      // and changePlan() does not normalize case — send the uppercase id or
      // the backend rejects it with NotFoundException.
      await _apiClient.changeSubscriptionPlan(
        planId: _selectedPlanId!.toUpperCase(),
      );

      if (!mounted) return;

      context.go('/owner-welcome', extra: widget.companyName);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 401) {
        return 'Session expired. Please log in again.';
      }
      if (error.response?.statusCode == 403) {
        return 'You don\u2019t have permission to change the plan.';
      }
      if (error.response?.statusCode != null &&
          error.response!.statusCode! >= 500) {
        return 'Server error. Please try again in a moment.';
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Couldn\u2019t reach the server. Check your internet and try again.';
      }
    }
    final text = error.toString();
    if (text.contains('503') || text.contains('not configured')) {
      return 'Subscription service is not available yet. Please contact Axon support.';
    }
    return text.replaceFirst('Exception: ', '').trim().isEmpty
        ? 'Something went wrong. Please try again.'
        : text.replaceFirst('Exception: ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Scaffold(
        backgroundColor: DesignColors.darkBg,
        body: SafeArea(
          child: Stack(
            children: [
              _buildAmbientField(),
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 28),
                  Text(
                    'Choose your plan',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.companyName == null || widget.companyName!.isEmpty
                        ? 'Start with a 7-day free trial. No subscription charges until your trial ends.'
                        : '${widget.companyName} is ready. Pick a plan to start your 7-day free trial.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DesignColors.darkTextSecondary,
                        height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Plan cards — first-mount stagger (see StaggeredItem)
                  for (final (i, plan) in kAvailablePlans.indexed) ...[
                    StaggeredItem(
                      itemKey: 'plan-${plan.id}',
                      index: i,
                      child: _buildPlanCard(plan, i),
                    ),
                    const SizedBox(height: DesignSpacing.lg - 2),
                  ],
                  const SizedBox(height: 8),
                  _buildSetupFeeNotice(),
                  const SizedBox(height: 22),
                  if (_error != null) ...[
                    _buildErrorCard(_error!),
                    const SizedBox(height: 16),
                  ],
                  GradientButton(
                    label: _isSubmitting
                        ? 'Starting your free trial…'
                        : 'Start 7-Day Free Trial',
                    icon: Icons.rocket_launch_rounded,
                    onPressed: _selectedPlanId != null && !_isSubmitting
                        ? _startFreeTrial
                        : null,
                    height: 58,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A one-time ${_setupFeeKsh()} setup fee applies before your free trial begins. Cancel anytime during the trial.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DesignColors.darkTextTertiary,
                        height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _buildComparisonSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: DesignColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DesignColors.brand.withValues(alpha: 0.35),
            ),
          ),
          child: const Icon(
            Icons.subscriptions_rounded,
            color: DesignColors.brand,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AXON / SUBSCRIPTION',
                style: TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'STEP 4 · CHOOSE PLAN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: DesignColors.accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, int index) {
    final isSelected = _selectedPlanId == plan.id;

    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedPlanId = plan.id),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXxl + 4),
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    DesignColors.brand.withValues(alpha: 0.24),
                    DesignColors.darkSurfaceElevated,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected
              ? null
              : DesignColors.darkSurface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? DesignColors.brand.withValues(alpha: 0.55)
                : DesignColors.darkBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: DesignColors.darkTextPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                            ),
                          ),
                          if (plan.isPopular) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    DesignColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: DesignColors.accent
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                'POPULAR',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: DesignColors.accent,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.tagline,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DesignColors.darkTextSecondary,
                            height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: DesignColors.brand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Shrink the price (never overflow) when the card is narrow —
                // 'KES 10,000' at 30px needs the full row width on small phones.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatKes(plan.priceKes),
                      maxLines: 1,
                      style: DesignType.numeric(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: DesignColors.darkTextPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/month',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DesignColors.darkTextTertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: DesignColors.darkBorder,
            ),
            const SizedBox(height: 14),
            ...plan.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: DesignColors.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feature.text,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                          color: DesignColors.darkTextSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildSetupFeeNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignColors.accentSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DesignColors.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: DesignColors.accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'One-time setup fee',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DesignColors.darkTextPrimary,
                      fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_setupFeeKsh()} gets your business fully onboarded before your trial starts.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DesignColors.darkTextSecondary,
                      height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatKes(_setupFeeKes),
            style: DesignType.numeric(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: DesignColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compare features',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: DesignColors.darkTextPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'See exactly what you get with each plan.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DesignColors.darkTextTertiary,
              height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: DesignColors.darkSurface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DesignColors.darkBorder),
          ),
          child: Column(
            children: [
              // Header row — feature-name column + one column per plan.
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(
                  color: DesignColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: DesignColors.darkBorder),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'Feature',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DesignColors.darkTextTertiary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _buildPlanColumnHeader('CORE', DesignColors.darkTextPrimary),
                    _buildPlanColumnHeader('BUSINESS', DesignColors.accent),
                    _buildPlanColumnHeader('ENTERPRISE', DesignColors.brand),
                  ],
                ),
              ),
              ...kPlanFeatures.map((feature) => _buildComparisonRow(feature)),
            ],
          ),
        ),
      ],
    );
  }

  /// Centered plan-name cell for the comparison-table header. [FittedBox]
  /// keeps 'ENTERPRISE' inside its narrow column on phone widths instead of
  /// overflowing the row.
  Widget _buildPlanColumnHeader(String name, Color color) {
    return Expanded(
      flex: 2,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            name,
            maxLines: 1,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  /// One centered check/remove cell in a plan column.
  Widget _buildComparisonCell(bool included) {
    return Expanded(
      flex: 2,
      child: Center(
        child: included
            ? const Icon(Icons.check_circle_rounded,
                color: DesignColors.success, size: 20)
            : const Icon(Icons.remove_rounded,
                color: DesignColors.darkTextTertiary, size: 18),
      ),
    );
  }

  Widget _buildComparisonRow(PlanFeature feature) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: DesignColors.darkBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              feature.text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DesignColors.darkTextSecondary,
                  height: 1.35,
              ),
            ),
          ),
          _buildComparisonCell(feature.includedInCore),
          _buildComparisonCell(feature.includedInBusiness),
          _buildComparisonCell(feature.includedInEnterprise),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DesignColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: DesignColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: DesignColors.error, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientField() {
    return Positioned(
      left: -MediaQuery.sizeOf(context).width * 0.3,
      right: -MediaQuery.sizeOf(context).width * 0.3,
      bottom: -MediaQuery.sizeOf(context).height * 0.12,
      height: MediaQuery.sizeOf(context).width * 1.1,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          // Ambient hero drift: automatic (not user-triggered), so a timing
          // curve token; 1200ms is intentionally beyond normal350 because
          // this is environmental motion, not interaction feedback.
          duration: DesignAnimation.slower,
          tween: Tween(begin: 0.86, end: 1.0),
          curve: DesignAnimation.smooth,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  DesignColors.brand.withValues(alpha: 0.12),
                  DesignColors.accent.withValues(alpha: 0.035),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.38, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
