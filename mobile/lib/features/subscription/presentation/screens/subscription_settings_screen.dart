import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';

/// Status badge colors for subscription state.
Color _statusColor(String? status) {
  switch (status?.toUpperCase()) {
    case 'ACTIVE':
    case 'TRIAL':
      return DesignColors.success;
    case 'PAST_DUE':
    case 'OVERDUE':
      return DesignColors.warning;
    case 'CANCELED':
    case 'EXPIRED':
      return DesignColors.error;
    default:
      return DesignColors.darkTextTertiary;
  }
}

String _statusLabel(String? status) {
  switch (status?.toUpperCase()) {
    case 'ACTIVE':
      return 'Active';
    case 'TRIAL':
      return 'Free Trial';
    case 'PAST_DUE':
      return 'Past Due';
    case 'OVERDUE':
      return 'Overdue';
    case 'CANCELED':
      return 'Canceled';
    case 'EXPIRED':
      return 'Expired';
    default:
      return status ?? 'Unknown';
  }
}

class SubscriptionSettingsScreen extends ConsumerStatefulWidget {
  const SubscriptionSettingsScreen({super.key});

  @override
  ConsumerState<SubscriptionSettingsScreen> createState() =>
      _SubscriptionSettingsScreenState();
}

class _SubscriptionSettingsScreenState
    extends ConsumerState<SubscriptionSettingsScreen> {
  Map<String, dynamic>? _plan;
  List<dynamic> _invoices = [];
  bool _isLoadingPlan = true;
  bool _isLoadingInvoices = true;
  final bool _isChangingPlan = false;
  String? _error;

  ApiClient get _apiClient => getIt<ApiClient>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadPlan(), _loadInvoices()]);
  }

  Future<void> _loadPlan() async {
    setState(() {
      _isLoadingPlan = true;
      _error = null;
    });
    try {
      final plan = await _apiClient.getSubscriptionPlan();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _isLoadingPlan = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingPlan = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoadingInvoices = true);
    try {
      final invoices = await _apiClient.getSubscriptionInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _isLoadingInvoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingInvoices = false);
    }
  }

  // Future<void> _changePlan(String planId) async {
  //   ...
  // }

  void _showChangePlanDialog() {
    final currentPlanId = _plan?['planId'] as String? ?? 'core';

    String? selectedPlanId;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: DesignColors.darkSurfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: DesignColors.darkBorder),
            ),
            title: const Text(
              'Change Plan',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select a new plan. Changes take effect immediately.',
                  style: TextStyle(
                    color: DesignColors.darkTextSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                // CORE plan option
                _PlanOptionTile(
                  name: 'CORE',
                  price: 'KES 3,200/mo',
                  isSelected: selectedPlanId == 'core',
                  isCurrent: currentPlanId == 'core',
                  onTap: () => setDialogState(() => selectedPlanId = 'core'),
                ),
                const SizedBox(height: 8),
                // ENTERPRISE plan option
                _PlanOptionTile(
                  name: 'ENTERPRISE',
                  price: 'KES 5,000/mo',
                  isSelected: selectedPlanId == 'enterprise',
                  isCurrent: currentPlanId == 'enterprise',
                  onTap: () =>
                      setDialogState(() => selectedPlanId = 'enterprise'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              GradientButton(
                label: 'Change to ${selectedPlanId == 'enterprise' ? 'ENTERPRISE' : 'CORE'}',
                expanded: false,
                height: 42,
                borderRadius: 12,
                onPressed: () async {
                  final target = selectedPlanId ?? currentPlanId;
                  if (target == currentPlanId) {
                    Navigator.pop(dialogContext);
                    return;
                  }
                  try {
                    await _apiClient.changeSubscriptionPlan(planId: target);
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (!mounted) return;
                    await _loadPlan();
                    if (!mounted) return;
                    if (!context.mounted) return;
                    showGlassSnackBar(
                      context,
                      'Plan changed to ${target == 'enterprise' ? 'ENTERPRISE' : 'CORE'}',
                      icon: Icons.check_circle_rounded,
                      color: DesignColors.success,
                    );
                  } catch (e) {
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    return text.replaceFirst('Exception: ', '').trim().isEmpty
        ? 'Something went wrong. Please try again.'
        : text.replaceFirst('Exception: ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      appBar: AppBar(
        backgroundColor: DesignColors.darkBg,
        title: const Text(
          'Subscription',
          style: TextStyle(
            color: DesignColors.darkTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: DesignColors.darkTextPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Current Plan Card ──
          _buildCurrentPlanCard(),
          const SizedBox(height: 20),

          // ── Change Plan Button ──
          if (!_isLoadingPlan && _plan != null) ...[
            GradientButton(
              label: _isChangingPlan
                  ? 'Changing plan…'
                  : 'Change Plan',
              icon: Icons.swap_horiz_rounded,
              onPressed: _isChangingPlan ? null : _showChangePlanDialog,
              height: 52,
              borderRadius: 16,
            ),
            const SizedBox(height: 24),
          ],

          // ── Error ──
          if (_error != null) ...[
            _buildErrorCard(_error!),
            const SizedBox(height: 16),
          ],

          // ── Invoice History ──
          const SettingsGroupLabel('Invoice History'),
          const SizedBox(height: 8),
          if (_isLoadingInvoices)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_invoices.isEmpty)
            _buildEmptyInvoices()
          else
            ..._invoices.map((inv) => _buildInvoiceRow(inv)),
        ],
      ),
    );
  }

  Widget _buildCurrentPlanCard() {
    if (_isLoadingPlan) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_plan == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DesignColors.darkSurface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DesignColors.darkBorder),
        ),
        child: const Column(
          children: [
            Icon(Icons.error_outline_rounded,
                color: DesignColors.darkTextTertiary, size: 40),
            SizedBox(height: 12),
            Text(
              'Could not load subscription details',
              style: TextStyle(color: DesignColors.darkTextSecondary),
            ),
          ],
        ),
      );
    }

    final planName = _plan?['plan'] as String? ?? 'CORE';
    final status = _plan?['subscriptionStatus'] as String? ?? 'TRIAL';
    final nextBilling = _plan?['currentPeriodEnd'] as String?;
    final trialEnds = _plan?['currentPeriodEnd'] as String?;
    final isTrial = status.toUpperCase() == 'TRIAL';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DesignColors.brand.withValues(alpha: 0.20),
            DesignColors.darkSurfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: DesignColors.brand.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan name + status badge
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.subscriptions_rounded,
                  color: DesignColors.brand,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      planName,
                      style: const TextStyle(
                        color: DesignColors.darkTextPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _statusColor(status).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Price
          Row(
            children: [
              Text(
                planName == 'ENTERPRISE' ? 'KES 5,000' : 'KES 3,200',
                style: DesignType.numeric(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: DesignColors.darkTextPrimary,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
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
          const SizedBox(height: 12),
          // Trial / billing info
          if (isTrial && trialEnds != null) ...[
            _buildInfoRow(
              Icons.timer_outlined,
              'Trial ends ${_formatDate(trialEnds)}',
            ),
          ] else if (nextBilling != null) ...[
            _buildInfoRow(
              Icons.calendar_today_rounded,
              'Next billing: ${_formatDate(nextBilling)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: DesignColors.darkTextSecondary, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: DesignColors.darkTextSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceRow(Map<String, dynamic> invoice) {
    final amount = invoice['amount'] as num? ?? 0;
    final currency = invoice['currency'] as String? ?? 'KES';
    final status = invoice['status'] as String? ?? '';
    final date = invoice['date'] as String? ?? invoice['createdAt'] as String? ?? '';
    final description = invoice['description'] as String? ?? 'Subscription';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignColors.darkSurfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: DesignColors.darkTextSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  date.isNotEmpty ? _formatDate(date) : '',
                  style: const TextStyle(
                    color: DesignColors.darkTextTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currency ${_formatAmount(amount)}',
                style: DesignType.numeric(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DesignColors.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyInvoices() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              color: DesignColors.darkTextTertiary, size: 36),
          SizedBox(height: 10),
          Text(
            'No invoices yet',
            style: TextStyle(
              color: DesignColors.darkTextSecondary,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Invoices will appear after your first billing cycle.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DesignColors.darkTextTertiary,
              fontSize: 12,
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

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _formatAmount(num amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }
}

/// A selectable plan option tile used in the change-plan dialog.
class _PlanOptionTile extends StatelessWidget {
  final String name;
  final String price;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PlanOptionTile({
    required this.name,
    required this.price,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? DesignColors.brand.withValues(alpha: 0.12)
              : DesignColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? DesignColors.brand.withValues(alpha: 0.5)
                : DesignColors.darkBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: DesignColors.darkTextPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: DesignColors.darkTextTertiary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'CURRENT',
                            style: TextStyle(
                              color: DesignColors.darkTextTertiary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    price,
                    style: const TextStyle(
                      color: DesignColors.darkTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: DesignColors.brand,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
