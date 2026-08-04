import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';

class CompanyActivationScreen extends ConsumerStatefulWidget {
  const CompanyActivationScreen({super.key, this.companyName});

  final String? companyName;

  @override
  ConsumerState<CompanyActivationScreen> createState() =>
      _CompanyActivationScreenState();
}

class _CompanyActivationScreenState
    extends ConsumerState<CompanyActivationScreen> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  bool _isStartingCheckout = false;
  bool _isVerifying = false;
  String? _error;

  ApiClient get _apiClient => getIt<ApiClient>();
  AuthService get _authService => getIt<AuthService>();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final status = await _apiClient.getTenantActivationStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _startCheckout() async {
    setState(() {
      _isStartingCheckout = true;
      _error = null;
    });
    try {
      final status = await _apiClient.initializeTenantActivationPayment();
      final url = status['authorizationUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('The secure checkout link was not returned.');
      }
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not open the secure payment page.');
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _isStartingCheckout = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStartingCheckout = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _verifyPayment() async {
    final reference = _status?['reference'] as String?;
    if (reference == null || reference.isEmpty) {
      await _startCheckout();
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      final status = await _apiClient.verifyTenantActivationPayment(reference);
      final isActive = status['status'] == 'ACTIVE';
      if (!isActive) {
        throw Exception(
          'Payment is still being confirmed. Please wait a moment and try again.',
        );
      }
      await _authService.updateTenantSession({
        'activationStatus': 'ACTIVE',
        'activationAmount': status['amountKes'],
        'activationReference': status['reference'],
        'activationProvider': status['provider'],
        'activationPaidAt': status['paidAt'],
      });
      if (!mounted) return;
      context.go('/plan-selection', extra: widget.companyName);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('503') || text.contains('not configured')) {
      return 'Secure checkout is not available on the server yet. Please contact Axon support before attempting payment.';
    }
    if (text.contains('402')) {
      return 'Complete the KSh 50,000 activation payment to continue.';
    }
    return text.replaceFirst('Exception: ', '').trim().isEmpty
        ? 'We could not load the activation payment. Please try again.'
        : text.replaceFirst('Exception: ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final companyName = widget.companyName?.trim();
    final reference = _status?['reference'] as String?;
    final hasCheckout = reference != null && reference.isNotEmpty;

    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            _buildAmbientField(),
            RefreshIndicator(
              color: DesignColors.brand,
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  Text(
                    'Activate your workspace',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    companyName == null || companyName.isEmpty
                        ? 'Your company is created. One payment unlocks the Axon POS workspace.'
                        : '$companyName is created. Complete activation before using Axon POS.',
                    style: const TextStyle(
                      color: DesignColors.darkTextSecondary,
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildPriceCard(),
                  const SizedBox(height: 16),
                  _buildIncludesCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(_error!),
                  ],
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    GradientButton(
                      label: _isStartingCheckout
                          ? 'Opening secure checkout…'
                          : hasCheckout
                              ? 'Open payment checkout again'
                              : 'Pay KSh 50,000 to activate',
                      icon: Icons.lock_rounded,
                      onPressed: _isStartingCheckout ? null : _startCheckout,
                      height: 58,
                      borderRadius: 16,
                    ),
                    if (hasCheckout) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isVerifying ? null : _verifyPayment,
                        icon: _isVerifying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.verified_rounded),
                        label: Text(
                          _isVerifying
                              ? 'Checking payment…'
                              : 'I completed payment — check status',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DesignColors.darkTextPrimary,
                          side: BorderSide(
                            color: DesignColors.darkTextTertiary
                                .withValues(alpha: 0.45),
                          ),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Secure checkout powered by Paystack. Axon will only unlock the workspace after the payment is verified by the server.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DesignColors.darkTextTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
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
            Icons.lock_outline_rounded,
            color: DesignColors.brand,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AXON / ACTIVATION',
                style: TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'STEP 4 · PAYMENT REQUIRED',
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

  Widget _buildPriceCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DesignColors.brand.withValues(alpha: 0.24),
            DesignColors.darkSurfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignColors.brand.withValues(alpha: 0.55)),
      ),
      child: const Row(
        children: [
          Icon(Icons.workspace_premium_rounded,
              color: DesignColors.brand, size: 38),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Axon workspace activation',
                  style: TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'One-time setup payment',
                  style: TextStyle(color: DesignColors.darkTextSecondary),
                ),
              ],
            ),
          ),
          Text(
            'KSh 50,000',
            style: TextStyle(
              color: DesignColors.darkTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncludesCard() {
    const items = [
      ('Dashboard', 'Business overview and daily decisions'),
      ('POS workspace', 'Sales, customers, products, and payments'),
      ('Owner controls', 'Staff, permissions, branches, and settings'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Column(
        children: items
            .map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_rounded,
                    color: DesignColors.accent, size: 22),
                title: Text(item.$1,
                    style: const TextStyle(
                        color: DesignColors.darkTextPrimary,
                        fontWeight: FontWeight.w700)),
                subtitle: Text(item.$2,
                    style: const TextStyle(color: DesignColors.darkTextSecondary)),
              ),
            )
            .toList(),
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
