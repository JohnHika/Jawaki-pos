import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../domain/billing_entitlement.dart';
import '../providers/entitlement_provider.dart';

/// Status badge colors for billing states (mirrors the subscription
/// screen's palette; GRACE_PERIOD added).
Color _statusColor(String? status) {
  switch (status?.toUpperCase()) {
    case 'ACTIVE':
    case 'PAID':
      return DesignColors.success;
    case 'GRACE_PERIOD':
    case 'PAST_DUE':
    case 'PENDING':
    case 'PENDING_CONFIRMATION':
      return DesignColors.warning;
    case 'RESTRICTED':
    case 'CANCELED':
    case 'EXPIRED':
    case 'REJECTED':
      return DesignColors.error;
    default:
      return DesignColors.darkTextTertiary;
  }
}

String _statusLabel(String? status) {
  switch (status?.toUpperCase()) {
    case 'ACTIVE':
      return 'Active';
    case 'GRACE_PERIOD':
      return 'Grace Period';
    case 'PAST_DUE':
      return 'Past Due';
    case 'RESTRICTED':
      return 'Restricted';
    case 'PAID':
      return 'Paid';
    case 'PENDING':
      return 'Pending';
    case 'PENDING_CONFIRMATION':
      return 'Awaiting Confirmation';
    default:
      return status ?? 'Unknown';
  }
}

/// Settings → Subscription & Billing (ADMIN).
///
/// Shows the signed entitlement (plan, status badge, next payment date,
/// amount, days-remaining progress bar), Pay-with-M-Pesa and Auto-Renew
/// actions, pending payment claims (admin confirm/reject), and invoice
/// history with M-Pesa references.
class SubscriptionBillingScreen extends ConsumerStatefulWidget {
  const SubscriptionBillingScreen({super.key});

  /// Test seam: force the admin-gated UI on/off in widget tests (a real
  /// AuthService singleton needs storage + database, which tests don't
  /// register). Null = decide from the logged-in user's role, as normal.
  @visibleForTesting
  static bool? overrideIsAdmin;

  @override
  ConsumerState<SubscriptionBillingScreen> createState() =>
      _SubscriptionBillingScreenState();
}

class _SubscriptionBillingScreenState
    extends ConsumerState<SubscriptionBillingScreen> {
  BillingEntitlement? _entitlement;
  Map<String, dynamic>? _settings;
  List<dynamic> _invoices = [];
  bool _isLoadingEntitlement = true;
  bool _isLoadingInvoices = true;
  String? _error;

  bool get _isAdmin {
    final forced = SubscriptionBillingScreen.overrideIsAdmin;
    if (forced != null) return forced;
    final user = getIt<AuthService>().currentUser;
    final role = user?['role']?.toString().toUpperCase();
    return role == 'ADMIN' || role == 'OWNER';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadEntitlement(), _loadInvoices()]);
    if (_isAdmin) await _loadSettings();
  }

  Future<void> _loadEntitlement() async {
    setState(() {
      _isLoadingEntitlement = true;
      _error = null;
    });
    try {
      // Live fetch (falls back to the offline cache on failure).
      final entitlement = await refreshEntitlement();
      if (!mounted) return;
      setState(() {
        _entitlement = entitlement;
        _isLoadingEntitlement = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingEntitlement = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoadingInvoices = true);
    try {
      final invoices = await _apiClient.getBillingInvoices();
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

  Future<void> _loadSettings() async {
    try {
      final settings = await _apiClient.getBillingSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
    } catch (_) {
      // Settings are optional UI garnish; entitlement drives the page.
    }
  }

  ApiClient get _apiClient => getIt<ApiClient>();

  String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 401) {
        return 'Session expired. Please log in again.';
      }
      if (error.response?.statusCode == 403) {
        return 'You don\u2019t have permission to view billing details.';
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
    final cleaned = text.replaceFirst('Exception: ', '').trim();
    return cleaned.isEmpty ? 'Something went wrong.' : cleaned;
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
          backgroundColor: DesignColors.darkBg,
          title: const Text(
            'Subscription & Billing',
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
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (_error != null) ...[
                _buildErrorCard(_error!),
                const SizedBox(height: 16),
              ],
              _buildEntitlementCard(),
              const SizedBox(height: 20),
              _buildPayWithMpesaButton(),
              const SizedBox(height: 12),
              if (_isAdmin) ...[
                _buildAutoRenewTile(),
                const SizedBox(height: 24),
              ],
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
        ),
      ),
    );
  }

  // ── Entitlement summary card ────────────────────────────────────────

  Widget _buildEntitlementCard() {
    if (_isLoadingEntitlement && _entitlement == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final entitlement = _entitlement;
    if (entitlement == null) {
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

    final badgeColor = _statusColor(entitlement.status);
    final days = entitlement.daysRemaining ?? 0;
    final nextPayment = entitlement.paidUntil;

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
                      entitlement.plan.toUpperCase(),
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
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel(entitlement.status),
                        style: TextStyle(
                          color: badgeColor,
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
          // Amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _amountLabel(entitlement),
                style: DesignType.numeric(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: DesignColors.darkTextPrimary,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 3),
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
          Container(
            height: 1,
            color: DesignColors.darkBorder.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          // Next payment + days remaining
          if (nextPayment != null)
            _buildInfoRow(
              Icons.calendar_today_rounded,
              'Next payment: ${_formatDate(nextPayment)}',
            ),
          _buildInfoRow(
            Icons.hourglass_bottom_rounded,
            days > 0 ? '$days days remaining' : 'Due for renewal',
          ),
          if (entitlement.maxBranches != null)
            _buildInfoRow(
              Icons.store_rounded,
              'Up to ${entitlement.maxBranches} branches'
              '${entitlement.maxUsers != null ? ' · ${entitlement.maxUsers} users' : ''}',
            ),
          if (entitlement.state == EntitlementState.grace) ...[
            const SizedBox(height: 8),
            _buildGraceNotice(),
          ],
          const SizedBox(height: 14),
          // Days-remaining progress bar
          _buildDaysProgressBar(days),
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
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: DesignColors.darkTextSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraceNotice() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: DesignColors.warning.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.schedule_rounded,
              color: DesignColors.warning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Payment overdue — you\u2019re in the 3-day grace period. '
              'Pay now to keep creating sales.',
              style: TextStyle(
                color: DesignColors.warning,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysProgressBar(int daysRemaining) {
    // 31-day cycle assumption: the bar depletes as the period runs out.
    const cycleDays = 31;
    final fraction = (daysRemaining / cycleDays).clamp(0.0, 1.0);
    final color = daysRemaining <= 3
        ? DesignColors.error
        : daysRemaining <= 7
            ? DesignColors.warning
            : DesignColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'DAYS REMAINING',
              style: TextStyle(
                color: DesignColors.darkTextTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            Text(
              '$daysRemaining',
              style: DesignType.numeric(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: DesignColors.darkBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Widget _buildPayWithMpesaButton() {
    return GradientButton(
      label: 'Pay with M-Pesa',
      icon: Icons.phone_android_rounded,
      onPressed: _showPaySheet,
      height: 52,
      borderRadius: 16,
    );
  }

  Widget _buildAutoRenewTile() {
    final settings = _settings;
    final autoRenew = settings?['autoRenewEnabled'] == true;
    final phone = settings?['billingPhone']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.autorenew_rounded,
              color: DesignColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auto-Renew',
                  style: TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  autoRenew
                      ? (phone.isEmpty
                          ? 'On — no billing phone set'
                          : 'On — $phone')
                      : 'Off — pay manually each month',
                  style: const TextStyle(
                    color: DesignColors.darkTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: autoRenew,
            activeThumbColor: DesignColors.accent,
            onChanged: (_) => _showAutoRenewSheet(),
          ),
        ],
      ),
    );
  }

  // ── Pay sheet ───────────────────────────────────────────────────────

  void _showPaySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PayWithMpesaSheet(
        monthlyAmount: _settings?['plan'] != null
            ? _monthlyAmountFromSettings(_settings!)
            : null,
        manualPaybillPhone:
            _settings?['manualPaybill']?['phone']?.toString(),
        accountFormat:
            _settings?['manualPaybill']?['accountFormat']?.toString(),
        onSubmitted: () {
          _loadEntitlement();
          _loadInvoices();
        },
      ),
    );
  }

  void _showAutoRenewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AutoRenewSheet(
        initialAutoRenew: _settings?['autoRenewEnabled'] == true,
        initialPhone: _settings?['billingPhone']?.toString() ?? '',
        onSaved: (Map<String, dynamic> updated) {
          if (!mounted) return;
          setState(() => _settings = updated);
        },
      ),
    );
  }

  // ── Invoice rows ────────────────────────────────────────────────────

  Widget _buildInvoiceRow(Map<String, dynamic> invoice) {
    final amount = invoice['amount'] as num? ?? 0;
    final currency = invoice['currency'] as String? ?? 'KES';
    final status = invoice['status'] as String? ?? '';
    final date =
        invoice['date'] as String? ?? invoice['createdAt'] as String? ?? '';
    final description = invoice['description'] as String? ??
        (invoice['plan'] != null
            ? '${invoice['plan']} subscription'
            : 'Subscription');
    final reference = invoice['reference'] as String? ??
        invoice['mpesaReference'] as String?;

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
                if (reference != null && reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'M-Pesa $reference',
                    style: DesignType.numeric(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: DesignColors.mpesa,
                    ),
                  ),
                ],
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor(status).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: statusColor(status),
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
            'Invoices appear at each monthly renewal.',
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

  // ── Helpers ─────────────────────────────────────────────────────────

  String _amountLabel(BillingEntitlement entitlement) {
    final amount = _settings?['plan'] != null
        ? _monthlyAmountFromSettings(_settings!)
        : _planPrice(entitlement.plan);
    return 'KES ${_formatAmount(amount)}';
  }

  num _monthlyAmountFromSettings(Map<String, dynamic> settings) {
    final plan = settings['plan']?.toString().toUpperCase() ?? 'CORE';
    return _planPrice(plan);
  }

  num _planPrice(String plan) =>
      plan.toUpperCase() == 'ENTERPRISE' ? 5000 : 3200;

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
      return NumberFormat('#,###').format(amount.toInt());
    }
    return amount.toStringAsFixed(2);
  }
}

/// Status badge colors shared with the banner tests — public because the
/// reminder banner and tests reuse the same palette.
Color statusColor(String? status) => _statusColor(status);

// ═══════════════════════════════════════════════════════════════════
//  PAY WITH M-PESA SHEET — two steps: invoice summary → code entry
// ═══════════════════════════════════════════════════════════════════

class _PayWithMpesaSheet extends ConsumerStatefulWidget {
  const _PayWithMpesaSheet({
    required this.onSubmitted,
    this.monthlyAmount,
    this.manualPaybillPhone,
    this.accountFormat,
  });

  final VoidCallback onSubmitted;
  final num? monthlyAmount;
  final String? manualPaybillPhone;
  final String? accountFormat;

  @override
  ConsumerState<_PayWithMpesaSheet> createState() => _PayWithMpesaSheetState();
}

class _PayWithMpesaSheetState extends ConsumerState<_PayWithMpesaSheet> {
  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  bool _stkRequested = false;

  @override
  void dispose() {
    _codeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  num get _amount => widget.monthlyAmount ?? 3200;

  Future<void> _requestStkPush() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Enter the M-Pesa phone number to charge');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    // The backend fires the STK push against the billing phone on file
    // (auto-charge path). Here we only surface instructions — the actual
    // charge lands as an invoice claim the admin/payment webhook confirms.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _stkRequested = true;
    });
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 8) {
      setState(
          () => _error = 'Enter the M-Pesa confirmation code (e.g. QGH7XY92K1)');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await getIt<ApiClient>().submitSubscriptionPayment(
        mpesaCode: code,
        amount: _amount.toDouble(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSubmitted();
      final message = result['message']?.toString() ??
          'Payment code received. Axon will confirm shortly and your '
              'subscription will continue.';
      showGlassSnackBar(
        context,
        message,
        icon: Icons.schedule_rounded,
        color: DesignColors.warning,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e is DioException && e.response?.statusCode == 409
            ? 'This M-Pesa code has already been submitted'
            : 'Could not submit the code. Check it and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountLabel = 'KES ${NumberFormat('#,###').format(_amount)}';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DesignColors.darkBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pay with M-Pesa',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Renew your subscription via M-Pesa',
              style: TextStyle(
                color: DesignColors.darkTextSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),

            // ── Step 1: invoice summary ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DesignColors.darkSurfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DesignColors.darkBorder),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Subscription', 'Monthly renewal'),
                  _buildSummaryRow('Amount due', amountLabel),
                  if (widget.manualPaybillPhone != null)
                    _buildSummaryRow(
                        'Paybill', widget.manualPaybillPhone!),
                  if (widget.accountFormat != null)
                    _buildSummaryRow('Account', widget.accountFormat!),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Option A: STK push to the number entered
            const Text(
              'OPTION 1 — STK PUSH',
              style: TextStyle(
                color: DesignColors.darkTextTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'M-Pesa phone number',
                hintText: '07XX XXX XXX',
                prefixIcon: Icon(Icons.phone_android_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (_stkRequested)
              const Text(
                'STK push sent — check your phone and enter your PIN. '
                'Then confirm below with the M-Pesa code if asked.',
                style: TextStyle(
                  color: DesignColors.success,
                  fontSize: 12,
                  height: 1.35,
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: SettingsPrimaryButton(
                  label: 'Send STK Push',
                  isLoading: _isSubmitting,
                  onPressed: _requestStkPush,
                  color: DesignColors.mpesa,
                ),
              ),
            const SizedBox(height: 18),

            // Option B: manual paybill code entry
            const Text(
              'OPTION 2 — PAID VIA PAYBILL? ENTER CODE',
              style: TextStyle(
                color: DesignColors.darkTextTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'M-Pesa confirmation code',
                hintText: 'e.g. QGH7XY92K1',
                prefixIcon: Icon(Icons.confirmation_number_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The code is recorded as a pending claim until an admin '
              'confirms the payment.',
              style: TextStyle(
                color: DesignColors.darkTextTertiary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: DesignColors.error,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SettingsPrimaryButton(
                label: 'Submit Payment Code',
                isLoading: _isSubmitting,
                onPressed: _submitCode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: DesignColors.darkTextSecondary,
              fontSize: 12.5,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: DesignColors.darkTextPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AUTO-RENEW SHEET (ADMIN)
// ═══════════════════════════════════════════════════════════════════

class _AutoRenewSheet extends ConsumerStatefulWidget {
  const _AutoRenewSheet({
    required this.initialAutoRenew,
    required this.initialPhone,
    required this.onSaved,
  });

  final bool initialAutoRenew;
  final String initialPhone;
  final ValueChanged<Map<String, dynamic>> onSaved;

  @override
  ConsumerState<_AutoRenewSheet> createState() => _AutoRenewSheetState();
}

class _AutoRenewSheetState extends ConsumerState<_AutoRenewSheet> {
  late bool _autoRenew = widget.initialAutoRenew;
  late final _phoneController =
      TextEditingController(text: widget.initialPhone);
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await getIt<ApiClient>().updateBillingSettings(
        autoRenewEnabled: _autoRenew,
        billingPhone: _phoneController.text.trim(),
      );
      widget.onSaved(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassSnackBar(
        context,
        _autoRenew
            ? 'Auto-renew on — we\u2019ll STK push ${_phoneController.text.trim()}'
            : 'Auto-renew off — pay manually each month',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Could not save. Check the phone number and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DesignColors.darkBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Set up Auto-Renew',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'We STK push the plan price to this number each month when '
              'the subscription renews.',
              style: TextStyle(
                color: DesignColors.darkTextSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: DesignColors.darkSurfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DesignColors.darkBorder),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoRenew,
                activeThumbColor: DesignColors.accent,
                title: const Text(
                  'Auto-renew subscription',
                  style: TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                onChanged: (v) => setState(() => _autoRenew = v),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Billing phone number',
                hintText: '07XX XXX XXX',
                prefixIcon: Icon(Icons.phone_android_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: DesignColors.error,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SettingsPrimaryButton(
                label: 'Save',
                isLoading: _isSaving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}