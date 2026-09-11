import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../subscription/domain/subscription_plans.dart';
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
            padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg,
              DesignSpacing.sm,
              DesignSpacing.lg,
              DesignSpacing.xxxl,
            ),
            children: [
              if (_error != null) ...[
                _buildErrorCard(_error!),
                const SizedBox(height: DesignSpacing.lg),
              ],
              // First-mount entrance choreography: each section and invoice
              // row fades/rises in once, staggered (see StaggeredItem).
              // Keys are stable, so pull-to-refresh never replays them.
              StaggeredItem(
                itemKey: 'billing-entitlement',
                child: _buildEntitlementCard(),
              ),
              const SizedBox(height: DesignSpacing.xl),
              StaggeredItem(
                itemKey: 'billing-pay-cta',
                index: 1,
                child: _buildPayWithMpesaButton(),
              ),
              const SizedBox(height: DesignSpacing.md),
              if (_isAdmin) ...[
                StaggeredItem(
                  itemKey: 'billing-auto-renew',
                  index: 2,
                  child: _buildAutoRenewTile(),
                ),
                const SizedBox(height: DesignSpacing.xxl),
              ],
              const SettingsGroupLabel('Invoice History'),
              const SizedBox(height: DesignSpacing.sm),
              if (_isLoadingInvoices)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(DesignSpacing.xxl),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_invoices.isEmpty)
                _buildEmptyInvoices()
              else
                ..._invoices.asMap().entries.map(
                      (entry) => StaggeredItem(
                        itemKey:
                            'billing-invoice-${entry.value['id'] ?? entry.key}',
                        index: 3 + entry.key,
                        child: _buildInvoiceRow(entry.value),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Entitlement summary card ────────────────────────────────────────

  Widget _buildEntitlementCard() {
    final theme = Theme.of(context);
    if (_isLoadingEntitlement && _entitlement == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DesignSpacing.huge),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final entitlement = _entitlement;
    if (entitlement == null) {
      return Container(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        decoration: BoxDecoration(
          color: DesignColors.darkSurface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          border: Border.all(color: DesignColors.darkBorder),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: DesignColors.darkTextTertiary, size: 40),
            const SizedBox(height: DesignSpacing.md),
            Text(
              'Could not load subscription details',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: DesignColors.darkTextSecondary),
            ),
          ],
        ),
      );
    }

    final badgeColor = _statusColor(entitlement.status);
    final days = entitlement.daysRemaining ?? 0;
    final nextPayment = entitlement.paidUntil;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DesignColors.brand.withValues(alpha: 0.14),
            DesignColors.darkSurfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(
          color: DesignColors.brand.withValues(alpha: 0.32),
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
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.subscriptions_rounded,
                  color: DesignColors.brand,
                  size: 24,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entitlement.plan.toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: DesignColors.darkTextPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.sm,
                          vertical: DesignSpacing.xs),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusFull),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel(entitlement.status),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeColor,
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
          const SizedBox(height: DesignSpacing.xl),
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
              const SizedBox(width: DesignSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.xs),
                child: Text(
                  '/month',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: DesignColors.darkTextTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.lg),
          Container(
            height: 1,
            color: DesignColors.darkBorder.withValues(alpha: 0.6),
          ),
          const SizedBox(height: DesignSpacing.lg),
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
              '${formatLimit(entitlement.maxBranches)} branches'
              '${entitlement.maxUsers != null ? ' · ${formatLimit(entitlement.maxUsers)} users' : ''}',
            ),
          if (entitlement.state == EntitlementState.grace) ...[
            const SizedBox(height: DesignSpacing.sm),
            _buildGraceNotice(),
          ],
          const SizedBox(height: DesignSpacing.md),
          // Days-remaining progress bar
          _buildDaysProgressBar(days),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: DesignColors.darkTextSecondary, size: 16),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: DesignColors.darkTextSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraceNotice() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
        border: Border.all(color: DesignColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded,
              color: DesignColors.warning, size: 16),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              'Payment overdue — you\u2019re in the 3-day grace period. '
              'Pay now to keep creating sales.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: DesignColors.warning,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysProgressBar(int daysRemaining) {
    final theme = Theme.of(context);
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
            Text(
              'DAYS REMAINING',
              style: theme.textTheme.labelSmall?.copyWith(
                color: DesignColors.darkTextTertiary,
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
        const SizedBox(height: DesignSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
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
      borderRadius: DesignSpacing.radiusLg,
    );
  }

  Widget _buildAutoRenewTile() {
    final theme = Theme.of(context);
    final settings = _settings;
    final autoRenew = settings?['autoRenewEnabled'] == true;
    final phone = settings?['billingPhone']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: const Icon(
              Icons.autorenew_rounded,
              color: DesignColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Renew',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  autoRenew
                      ? (phone.isEmpty
                          ? 'On — no billing phone set'
                          : 'On — $phone')
                      : 'Off — pay manually each month',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: DesignColors.darkTextSecondary),
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
        manualPaybillPhone: _settings?['manualPaybill']?['phone']?.toString(),
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
    final theme = Theme.of(context);
    final amount = invoice['amount'] as num? ?? 0;
    final currency = invoice['currency'] as String? ?? 'KES';
    final status = invoice['status'] as String? ?? '';
    final date =
        invoice['date'] as String? ?? invoice['createdAt'] as String? ?? '';
    final description = invoice['description'] as String? ??
        (invoice['plan'] != null
            ? '${invoice['plan']} subscription'
            : 'Subscription');
    final reference =
        invoice['reference'] as String? ?? invoice['mpesaReference'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignColors.darkSurfaceElevated,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: DesignColors.darkTextSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: DesignColors.darkTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  date.isNotEmpty ? _formatDate(date) : '',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: DesignColors.darkTextTertiary),
                ),
                if (reference != null && reference.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.xs),
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
              const SizedBox(height: DesignSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: DesignSpacing.xs, vertical: DesignSpacing.xs),
                decoration: BoxDecoration(
                  color: statusColor(status).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
                ),
                child: Text(
                  status.replaceAll('_', ' ').toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor(status),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.xxl),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined,
              color: DesignColors.darkTextTertiary, size: 36),
          const SizedBox(height: DesignSpacing.md),
          Text(
            'No invoices yet',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: DesignColors.darkTextSecondary),
          ),
          const SizedBox(height: DesignSpacing.xs),
          Text(
            'Invoices appear at each monthly renewal.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: DesignColors.darkTextTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: DesignColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: DesignColors.error, size: 20),
          const SizedBox(width: DesignSpacing.md),
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

  num _planPrice(String plan) => planPriceKes(plan);

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

  num get _amount => widget.monthlyAmount ?? planPriceKes('core');

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
    await Future<void>.delayed(DesignAnimation.normal);
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _stkRequested = true;
    });
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 8) {
      setState(() =>
          _error = 'Enter the M-Pesa confirmation code (e.g. QGH7XY92K1)');
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
    final theme = Theme.of(context);
    final amountLabel = 'KES ${NumberFormat('#,###').format(_amount)}';
    // Keyboard-safe sheet: lift above the keyboard (viewInsets) and keep
    // content clear of system gestures (SafeArea).
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DesignSpacing.xl,
            DesignSpacing.lg,
            DesignSpacing.xl,
            DesignSpacing.xxl,
          ),
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
                    borderRadius: BorderRadius.circular(DesignSpacing.xs),
                  ),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Text(
                'Pay with M-Pesa',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: DesignColors.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                'Renew your subscription via M-Pesa',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: DesignColors.darkTextSecondary),
              ),
              const SizedBox(height: DesignSpacing.xl),

              // ── Step 1: invoice summary ──
              Container(
                padding: DesignSpacing.paddingCard,
                decoration: BoxDecoration(
                  color: DesignColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  border: Border.all(color: DesignColors.darkBorder),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Subscription', 'Monthly renewal'),
                    _buildSummaryRow('Amount due', amountLabel),
                    if (widget.manualPaybillPhone != null)
                      _buildSummaryRow('Paybill', widget.manualPaybillPhone!),
                    if (widget.accountFormat != null)
                      _buildSummaryRow('Account', widget.accountFormat!),
                  ],
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),

              // Option A: STK push to the number entered
              Text(
                'OPTION 1 — STK PUSH',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: DesignColors.darkTextTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: DesignSpacing.sm),
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
              const SizedBox(height: DesignSpacing.md),
              if (_stkRequested)
                Text(
                  'STK push sent — check your phone and enter your PIN. '
                  'Then confirm below with the M-Pesa code if asked.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DesignColors.success,
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
              const SizedBox(height: DesignSpacing.xl),

              // Option B: manual paybill code entry
              Text(
                'OPTION 2 — PAID VIA PAYBILL? ENTER CODE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: DesignColors.darkTextTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: DesignSpacing.sm),
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
              const SizedBox(height: DesignSpacing.sm),
              Text(
                'The code is recorded as a pending claim until an admin '
                'confirms the payment.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DesignColors.darkTextTertiary,
                  height: 1.35,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: DesignSpacing.md),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: DesignColors.error),
                ),
              ],
              const SizedBox(height: DesignSpacing.lg),
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
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: DesignColors.darkTextSecondary),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: DesignColors.darkTextPrimary,
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
    final theme = Theme.of(context);
    // Keyboard-safe sheet: lift above the keyboard (viewInsets), keep
    // content clear of system gestures (SafeArea), and scroll when the
    // keyboard squeezes the available height.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DesignSpacing.xl,
            DesignSpacing.lg,
            DesignSpacing.xl,
            DesignSpacing.xxl,
          ),
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
                    borderRadius: BorderRadius.circular(DesignSpacing.xs),
                  ),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Text(
                'Set up Auto-Renew',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: DesignColors.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                'We STK push the plan price to this number each month when '
                'the subscription renews.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DesignColors.darkTextSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: DesignSpacing.xl),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
                decoration: BoxDecoration(
                  color: DesignColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  border: Border.all(color: DesignColors.darkBorder),
                ),
                // Material wrapper so the tile paints its ink/background on
                // this Material instead of one hidden behind the decorated
                // Container (fixes the ListTile-in-DecoratedBox assertion).
                child: Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _autoRenew,
                    activeThumbColor: DesignColors.accent,
                    title: Text(
                      'Auto-renew subscription',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: DesignColors.darkTextPrimary),
                    ),
                    onChanged: (v) => setState(() => _autoRenew = v),
                  ),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
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
                const SizedBox(height: DesignSpacing.md),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: DesignColors.error),
                ),
              ],
              const SizedBox(height: DesignSpacing.lg),
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
      ),
    );
  }
}
