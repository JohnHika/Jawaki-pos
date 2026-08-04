import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';

/// Represents a subscription plan option.
class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double priceKes;
  final List<String> features;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.priceKes,
    required this.features,
    this.isPopular = false,
  });
}

/// Available plans shown on the selection screen.
const kAvailablePlans = [
  SubscriptionPlan(
    id: 'core',
    name: 'CORE',
    description: 'Essential tools for a single-location shop',
    priceKes: 3200,
    features: [
      'Up to 1 branch',
      'Up to 3 staff accounts',
      'Basic sales & inventory',
      'Daily sales reports',
      'Email support',
    ],
  ),
  SubscriptionPlan(
    id: 'enterprise',
    name: 'ENTERPRISE',
    description: 'Full power for growing multi-location businesses',
    priceKes: 5000,
    isPopular: true,
    features: [
      'Unlimited branches',
      'Unlimited staff accounts',
      'Advanced inventory management',
      'Analytics dashboard & forecasting',
      'AI-powered insights',
      'Priority phone & email support',
      'Custom reports & data export',
    ],
  ),
];

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
      // Call the backend to select the plan and start the 14-day trial.
      // The backend handles the setup fee payment flow internally.
      await _apiClient.changeSubscriptionPlan(planId: _selectedPlanId!);

      if (!mounted) return;

      // After plan selection, navigate to the setup fee payment or
      // directly to the owner welcome screen.
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
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            _buildAmbientField(),
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                Text(
                  'Choose your plan',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: DesignColors.darkTextPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.companyName == null || widget.companyName!.isEmpty
                      ? 'Select a subscription plan to start your 14-day free trial.'
                      : '${widget.companyName} is ready. Pick a plan to begin your free trial.',
                  style: const TextStyle(
                    color: DesignColors.darkTextSecondary,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                // Plan cards
                for (final plan in kAvailablePlans) ...[
                  _buildPlanCard(plan),
                  const SizedBox(height: 16),
                ],
                // Setup fee notice
                _buildSetupFeeNotice(),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _buildErrorCard(_error!),
                  const SizedBox(height: 16),
                ],
                // Action button
                GradientButton(
                  label: _isSubmitting
                      ? 'Starting your free trial…'
                      : 'Start 14-Day Free Trial',
                  icon: Icons.rocket_launch_rounded,
                  onPressed:
                      _selectedPlanId != null && !_isSubmitting
                          ? _startFreeTrial
                          : null,
                  height: 58,
                  borderRadius: 16,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No charges today. Your 14-day free trial starts after a one-time setup fee of KSh 35,000.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DesignColors.darkTextTertiary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ],
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AXON / SUBSCRIPTION',
                style: TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'STEP 4 · CHOOSE PLAN',
                style: TextStyle(
                  color: DesignColors.accent,
                  fontSize: 11,
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

  Widget _buildPlanCard(SubscriptionPlan plan) {
    final isSelected = _selectedPlanId == plan.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedPlanId = plan.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(22),
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
          color: isSelected ? null : DesignColors.darkSurface.withValues(alpha: 0.82),
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
            // Plan header row
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
                            style: const TextStyle(
                              color: DesignColors.darkTextPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              letterSpacing: 1.2,
                            ),
                          ),
                          if (plan.isPopular) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: DesignColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: DesignColors.accent.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'POPULAR',
                                style: TextStyle(
                                  color: DesignColors.accent,
                                  fontSize: 9,
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
                        plan.description,
                        style: const TextStyle(
                          color: DesignColors.darkTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
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
            // Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'KES ${plan.priceKes.toStringAsFixed(0)}',
                  style: DesignType.numeric(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: DesignColors.darkTextPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/month',
                    style: TextStyle(
                      color: DesignColors.darkTextTertiary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Divider
            Container(
              height: 1,
              color: DesignColors.darkBorder,
            ),
            const SizedBox(height: 16),
            // Features
            ...plan.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: DesignColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(
                          color: DesignColors.darkTextSecondary,
                          fontSize: 14,
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'One-time setup fee',
                  style: TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'A one-time KSh 35,000 setup fee applies before your free trial begins.',
                  style: TextStyle(
                    color: DesignColors.darkTextSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'KES 35,000',
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
          duration: const Duration(milliseconds: 1200),
          tween: Tween(begin: 0.86, end: 1.0),
          curve: Curves.easeOutCubic,
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
