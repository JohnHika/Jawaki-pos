import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/legal/policy_catalog.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/motion_kit.dart';
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
      return DesignColors.textTertiary;
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
      return 'Payment processing';
    case 'UNKNOWN':
      return 'Status unavailable';
    default:
      return status ?? 'Unknown';
  }
}

/// Settings → Subscription & Billing (ADMIN).
///
/// Shows the signed entitlement, due Paystack checkout, Auto-Renew settings,
/// and provider-confirmed invoice history.
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
  String? _invoiceError;
  bool _isLoadingEntitlement = true;
  bool _isLoadingInvoices = true;
  bool _isChangingPlan = false;
  String? _error;
  String? _paystackInvoiceBusyId;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _paystackLinkSubscription;

  bool get _isAdmin {
    final forced = SubscriptionBillingScreen.overrideIsAdmin;
    if (forced != null) return forced;
    final user = getIt<AuthService>().currentUser;
    final role = user?['role']?.toString().toUpperCase();
    return role == 'ADMIN';
  }

  SubscriptionPlan? get _billingPlan {
    final entitlementPlan = planById(_entitlement?.plan);
    if (entitlementPlan != null) return entitlementPlan;
    return planById(_settings?['plan']?.toString());
  }

  SubscriptionPlan? get _pendingPlan =>
      planById(_settings?['pendingPlan']?.toString());

  @override
  void initState() {
    super.initState();
    _paystackLinkSubscription = _appLinks.uriLinkStream.listen(
      _handlePaystackReturn,
      onError: (_) {},
    );
    unawaited(_readInitialPaystackLink());
    _loadData();
  }

  @override
  void dispose() {
    unawaited(_paystackLinkSubscription?.cancel());
    super.dispose();
  }

  Future<void> _readInitialPaystackLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) await _handlePaystackReturn(uri);
    } catch (_) {}
  }

  Future<void> _handlePaystackReturn(Uri uri) async {
    if (!mounted ||
        uri.scheme != 'axonpos' ||
        uri.host != 'payment' ||
        uri.path != '/billing') {
      return;
    }
    final reference = uri.queryParameters['reference']?.trim();
    if (reference == null || reference.isEmpty) return;
    await _verifyPaystackPayment(reference);
  }

  Future<void> _loadData() async {
    await Future.wait([_loadEntitlement(), _loadInvoices()]);
    if (_isAdmin) {
      await _loadSettings();
    }
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
    setState(() {
      _isLoadingInvoices = true;
      _invoiceError = null;
    });
    try {
      final invoices = await _apiClient.getBillingInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _isLoadingInvoices = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingInvoices = false;
        _invoiceError = _friendlyError(error);
      });
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
      final body = error.response?.data;
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
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

  void _showChangePlanSheet() {
    final currentPlan = (_billingPlan?.id ?? 'core').toLowerCase();
    String selectedPlan = currentPlan == 'trial'
        ? (_pendingPlan?.id ?? 'core').toLowerCase()
        : currentPlan;
    bool acceptedBillingTerms = false;

    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.themed(DesignColors.darkSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
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
                        color: context.themed(DesignColors.darkBorder),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusFull),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  Text(
                    'Choose your plan',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          color: context.themed(DesignColors.darkTextPrimary),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.xs),
                  Text(
                    'Choose the plan for after your trial. Paid features start only after the subscription payment is confirmed.',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: context.themed(DesignColors.darkTextSecondary),
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  for (final plan in kAvailablePlans) ...[
                    _PlanRadioTile(
                      name: plan.name,
                      priceLabel: '${formatKes(plan.priceKes)}/month',
                      tagline: plan.tagline,
                      isCurrent: plan.id == currentPlan,
                      isSelected: selectedPlan == plan.id,
                      onTap: _isChangingPlan
                          ? null
                          : () => setSheetState(() {
                                if (selectedPlan != plan.id) {
                                  acceptedBillingTerms = false;
                                }
                                selectedPlan = plan.id;
                              }),
                    ),
                    if (plan != kAvailablePlans.last)
                      const SizedBox(height: DesignSpacing.sm),
                  ],
                  const SizedBox(height: DesignSpacing.lg),
                  CheckboxListTile(
                    value: acceptedBillingTerms,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _isChangingPlan
                        ? null
                        : (value) => setSheetState(
                              () => acceptedBillingTerms = value ?? false,
                            ),
                    title: const Text(
                      'I agree to the subscription, billing and refund terms for the plan shown above.',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          GoRouter.of(sheetContext).push('/legal/billing'),
                      child: const Text('Read subscription and billing terms'),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: SettingsPrimaryButton(
                      label: _isChangingPlan
                          ? 'Saving plan…'
                          : 'Continue with ${planDisplayName(selectedPlan)}',
                      isLoading: _isChangingPlan,
                      onPressed: selectedPlan == currentPlan ||
                              !acceptedBillingTerms ||
                              _isChangingPlan
                          ? null
                          : () async {
                              setState(() => _isChangingPlan = true);
                              try {
                                await _apiClient.acceptLegalPolicy(
                                  policyType: 'BILLING_TERMS',
                                  policyVersion: policyVersion('BILLING_TERMS'),
                                );
                                await _apiClient.changeSubscriptionPlan(
                                  planId: selectedPlan.toUpperCase(),
                                );
                                if (!mounted || !sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                                await _loadData();
                                if (!mounted) return;
                                showGlassSnackBar(
                                  context,
                                  '${planDisplayName(selectedPlan)} saved for after your trial',
                                  icon: Icons.check_circle_rounded,
                                  color: DesignColors.success,
                                );
                              } catch (error) {
                                if (!mounted) return;
                                showGlassSnackBar(
                                  context,
                                  _friendlyError(error),
                                  icon: Icons.error_outline_rounded,
                                  color: DesignColors.error,
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _isChangingPlan = false);
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Scaffold(
        backgroundColor: context.themed(DesignColors.darkBg),
        appBar: const BrandedAppBar(
          title: 'Plan & Billing',
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg,
              DesignSpacing.md,
              DesignSpacing.lg,
              DesignSpacing.xxxl,
            ),
            children: [
              if (_error != null) ...[
                _buildErrorCard(_error!),
                const SizedBox(height: DesignSpacing.lg),
              ],
              if (_entitlement?.source == EntitlementSource.offlineCache) ...[
                _buildBillingNotice(
                  'Showing saved billing details. Reconnect to confirm your current status.',
                ),
                const SizedBox(height: DesignSpacing.md),
              ],
              // First-mount entrance choreography: each section and invoice
              // row fades/rises in once, staggered (see StaggeredItem).
              // Keys are stable, so pull-to-refresh never replays them.
              StaggeredItem(
                itemKey: 'billing-entitlement',
                child: _buildEntitlementCard(),
              ),
              const SizedBox(height: DesignSpacing.xl),
              if (_isAdmin) ...[
                const SettingsGroupLabel('Plan'),
                const SizedBox(height: DesignSpacing.sm),
                _buildManagePlanTile(),
                if (_entitlement?.license != null) ...[
                  const SizedBox(height: DesignSpacing.md),
                  _buildLicenseCard(_entitlement!.license!),
                ],
                const SizedBox(height: DesignSpacing.xl),
              ],
              const SettingsGroupLabel('Renewal'),
              const SizedBox(height: DesignSpacing.sm),
              if (_billingPlan != null)
                StaggeredItem(
                  itemKey: 'billing-pay-cta',
                  index: 1,
                  child: _buildRenewalPaymentAction(),
                )
              else
                _buildPayUnavailableCard(),
              const SizedBox(height: DesignSpacing.md),
              if (_isAdmin) ...[
                StaggeredItem(
                  itemKey: 'billing-auto-renew',
                  index: 2,
                  child: _buildAutoRenewTile(),
                ),
                const SizedBox(height: DesignSpacing.md),
                ListCard(
                  leading: const Icon(Icons.redeem_rounded,
                      color: DesignColors.accent),
                  title: 'Free days',
                  subtitle:
                      'Invite other shops and get free days, or enter a promo code',
                  onTap: () => context.push('/referrals'),
                ),
                const SizedBox(height: DesignSpacing.xl),
                const SizedBox(height: DesignSpacing.xxl),
              ],
              const SettingsGroupLabel('Invoice History'),
              const SizedBox(height: DesignSpacing.sm),
              if (_invoiceError != null) ...[
                _buildInvoiceError(_invoiceError!),
                const SizedBox(height: DesignSpacing.md),
              ],
              if (_isLoadingInvoices && _invoices.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(DesignSpacing.xxl),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_invoices.isEmpty && _invoiceError == null)
                _buildEmptyInvoices()
              else if (_invoices.isNotEmpty)
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
          color:
              context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          border: Border.all(color: context.themed(DesignColors.darkBorder)),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded,
                color: context.themed(DesignColors.darkTextTertiary), size: 40),
            const SizedBox(height: DesignSpacing.md),
            Text(
              'Could not load subscription details',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.themed(DesignColors.darkTextSecondary)),
            ),
          ],
        ),
      );
    }

    final billingPlan = _billingPlan;
    final badgeColor = _statusColor(entitlement.status);
    final days = entitlement.daysRemaining;
    final nextPayment = entitlement.paidUntil;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  DesignColors.brand.withValues(alpha: 0.14),
                  context.themed(DesignColors.darkSurfaceElevated),
                ]
              : const [Color(0xFFFFE6D2), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(
          color: isDark
              ? DesignColors.brand.withValues(alpha: 0.32)
              : DesignColors.accent.withValues(alpha: 0.28),
        ),
        boxShadow: DesignShadows.soft(isDark),
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
                  color: (isDark ? DesignColors.brand : DesignColors.accent)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                ),
                child: Icon(
                  Icons.subscriptions_rounded,
                  color: isDark ? DesignColors.brand : DesignColors.accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      billingPlan?.name ?? 'Billing details unavailable',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.themed(DesignColors.darkTextPrimary),
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
                          color: context.readable(badgeColor),
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
          if (billingPlan != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CountUpText(
                  _amountLabel(billingPlan),
                  style: DesignType.numeric(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: context.themed(DesignColors.darkTextPrimary),
                  ),
                ),
                if (billingPlan.id != 'trial') ...[
                  const SizedBox(width: DesignSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignSpacing.xs),
                    child: Text(
                      '/month',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.themed(DesignColors.darkTextTertiary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: DesignSpacing.lg),
          Container(
            height: 1,
            color:
                context.themed(DesignColors.darkBorder).withValues(alpha: 0.6),
          ),
          const SizedBox(height: DesignSpacing.lg),
          // Next payment + days remaining
          if (nextPayment != null)
            _buildInfoRow(
              Icons.calendar_today_rounded,
              'Next payment: ${_formatDate(nextPayment)}',
            ),
          // The progress bar below already shows the days left.
          if (days != null && days <= 0)
            _buildInfoRow(
              Icons.hourglass_bottom_rounded,
              entitlement.daysOverdue > 0
                  ? 'Overdue by ${entitlement.daysOverdue} ${entitlement.daysOverdue == 1 ? 'day' : 'days'}'
                  : 'Due for renewal',
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
          if ((entitlement.state == EntitlementState.unknown ||
                  billingPlan == null) &&
              entitlement.source != EntitlementSource.offlineCache) ...[
            const SizedBox(height: DesignSpacing.sm),
            _buildBillingNotice(
              'Reconnect to confirm your plan and renewal date.',
            ),
          ],
          if (days != null) ...[
            const SizedBox(height: DesignSpacing.md),
            _buildDaysProgressBar(days, overdue: entitlement.daysOverdue),
          ],
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
          Icon(icon,
              color: context.themed(DesignColors.darkTextSecondary), size: 16),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: context.themed(DesignColors.darkTextSecondary)),
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

  Widget _buildDaysProgressBar(int daysRemaining, {int overdue = 0}) {
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
              overdue > 0 ? 'OVERDUE' : 'DAYS REMAINING',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.themed(DesignColors.darkTextTertiary),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            CountUpText(
              overdue > 0 ? '$overdue' : '$daysRemaining',
              style: DesignType.numeric(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.readable(color),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignSpacing.sm),
        AnimatedProgressBar(
          value: fraction,
          height: 6,
          color: color,
          trackColor: context.themed(DesignColors.darkBorder),
        ),
      ],
    );
  }

  /// What this company's licence covers: modules, seats, key and expiry.
  Widget _buildLicenseCard(ClientLicense license) {
    final primary = context.themed(DesignColors.darkTextPrimary);
    final secondary = context.themed(DesignColors.darkTextSecondary);
    final modules = LicensedFeature.labels.keys.toList();
    String seats(int? n) => n == null
        ? '—'
        : n >= 1000
            ? 'Unlimited'
            : '$n';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your licence',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (license.expired)
            Padding(
              padding: const EdgeInsets.only(top: DesignSpacing.xs),
              child: Text(
                'Your licence has expired. Contact support to renew it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.readable(DesignColors.error),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          const SizedBox(height: DesignSpacing.sm),
          for (final key in modules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    (license.planFeatures[key] ?? true) && license.allows(key)
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    size: 18,
                    color: (license.planFeatures[key] ?? true) &&
                            license.allows(key)
                        ? DesignColors.success
                        : secondary,
                  ),
                  const SizedBox(width: DesignSpacing.sm),
                  Expanded(
                    child: Text(
                      LicensedFeature.labels[key]!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: primary),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: DesignSpacing.xl),
          Text(
            'Up to ${seats(license.maxBranches)} branches · ${seats(license.maxUsers)} users',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: secondary),
          ),
          if (license.licenseKey != null) ...[
            const SizedBox(height: DesignSpacing.xs),
            SelectableText(
              'Licence key ${license.licenseKey}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: secondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManagePlanTile() {
    final plan = _billingPlan;
    final status = _entitlement?.status.toUpperCase();
    final isTrial = status == 'TRIAL';
    final isActive = status == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignColors.brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: const Icon(Icons.tune_rounded,
                color: DesignColors.brand, size: 20),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage plan',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: context.themed(DesignColors.darkTextPrimary),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  plan == null
                      ? 'Reconnect to load your current plan'
                      : isTrial
                          ? _pendingPlan == null
                              ? '${plan.name} · choose the plan for after your trial'
                              : '${plan.name} · ${_pendingPlan!.name} selected for after your trial'
                          : isActive
                              ? '${plan.name} · active subscription'
                              : '${plan.name} · payment required',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.themed(DesignColors.darkTextSecondary),
                      ),
                ),
              ],
            ),
          ),
          if (isTrial)
            TextButton(
              onPressed:
                  _isChangingPlan || plan == null ? null : _showChangePlanSheet,
              child: const Text('Choose'),
            ),
        ],
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Widget _buildPayWithMpesaButton() {
    var payerEmail = '';
    if (getIt.isRegistered<AuthService>()) {
      payerEmail =
          getIt<AuthService>().currentUser?['email']?.toString().trim() ?? '';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GradientButton(
          label: _paystackInvoiceBusyId == 'current'
              ? 'Opening Paystack…'
              : 'Pay subscription with Paystack',
          icon: Icons.lock_rounded,
          onPressed: _paystackInvoiceBusyId == 'current'
              ? null
              : _startPaystackInvoicePayment,
          isLoading: _paystackInvoiceBusyId == 'current',
          height: 52,
          borderRadius: DesignSpacing.radiusLg,
        ),
        const SizedBox(height: DesignSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: DesignColors.textSecondary),
            const SizedBox(width: DesignSpacing.xs),
            Expanded(
              child: Text(
                payerEmail.isEmpty
                    ? 'Paystack uses the signed-in shop account email for the subscription checkout.'
                    : 'Subscription payer email: $payerEmail. This is the signed-in shop account email.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DesignColors.textSecondary,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRenewalPaymentAction() {
    if (_isLoadingEntitlement || _isLoadingInvoices) {
      return _buildBillingNotice('Checking whether a subscription payment is due…');
    }

    final entitlement = _entitlement;
    if (entitlement == null) return _buildPayWithMpesaButton();
    final hasOpenInvoice = _invoices.any((rawInvoice) {
      final invoice = Map<String, dynamic>.from(rawInvoice as Map);
      return invoice['status']?.toString().toUpperCase() != 'PAID';
    });
    final paidUntil = DateTime.tryParse(entitlement.paidUntil ?? '');
    final periodEnded = paidUntil != null && !paidUntil.isAfter(DateTime.now());
    final status = entitlement.status.toUpperCase();
    final paymentDue = hasOpenInvoice ||
        periodEnded ||
        entitlement.restrictedMode ||
        status == 'PAST_DUE' ||
        status == 'SUSPENDED';

    if (paymentDue) return _buildPayWithMpesaButton();
    if (status == 'TRIAL') {
      final end = entitlement.paidUntil;
      return _buildBillingNotice(
        end == null
            ? 'Your free trial is active. No subscription payment is due yet.'
            : 'Your free trial is active through ${_formatDate(end)}. No subscription payment is due yet.',
      );
    }
    if (status == 'ACTIVE') {
      final end = entitlement.paidUntil;
      return _buildBillingNotice(
        end == null
            ? 'Your subscription is active. No payment is due now.'
            : 'Your subscription is active through ${_formatDate(end)}. No payment is due now.',
      );
    }
    return _buildPayWithMpesaButton();
  }

  Future<void> _startPaystackInvoicePayment() async {
    setState(() => _paystackInvoiceBusyId = 'current');
    try {
      final checkout = await _apiClient.initializePaystackSubscriptionPayment();
      if (checkout['status'] == 'PAID') {
        await _loadData();
        if (mounted) _showPaymentMessage('This invoice is already paid.');
        return;
      }
      final url = checkout['authorizationUrl']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Paystack did not return a checkout link.');
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'checkout.paystack.com') {
        throw Exception('Paystack returned an invalid checkout link.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open the Paystack checkout page.');
      }
    } catch (error) {
      if (mounted) _showPaymentMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _paystackInvoiceBusyId = null);
    }
  }

  Future<void> _verifyPaystackPayment(String reference) async {
    if (_paystackInvoiceBusyId != null) return;
    setState(() => _paystackInvoiceBusyId = reference);
    try {
      final result =
          await _apiClient.verifyPaystackSubscriptionPayment(reference);
      if (!mounted) return;
      if (result['status']?.toString().toUpperCase() == 'PAID') {
        ref.read(entitlementRefreshTickProvider.notifier).state++;
        await _loadData();
        if (mounted) {
          _showPaymentMessage('Monthly subscription payment confirmed.');
        }
      } else {
        _showPaymentMessage(
            'Payment is still being confirmed. Refresh again in a moment.');
      }
    } catch (error) {
      if (mounted) _showPaymentMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _paystackInvoiceBusyId = null);
    }
  }

  void _showPaymentMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? DesignColors.error : DesignColors.success,
      ),
    );
  }

  Widget _buildPayUnavailableCard() {
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded,
              color: context.themed(DesignColors.darkTextSecondary)),
          const SizedBox(width: DesignSpacing.md),
          const Expanded(
            child: Text('Reconnect to load your plan before making a payment.'),
          ),
          TextButton(onPressed: _loadData, child: const Text('Retry')),
        ],
      ),
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
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
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
                    color: context.themed(DesignColors.darkTextPrimary),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  autoRenew
                      ? (phone.isEmpty
                          ? 'Add a billing phone so we can charge it'
                          : 'On — $phone')
                      : 'Off — pay each invoice through Paystack',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: context.themed(DesignColors.darkTextSecondary)),
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

  void _showAutoRenewSheet() {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.themed(DesignColors.darkSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
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
    final amount = parseBillingAmount(invoice['amount']);
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
    final provider = invoice['provider']?.toString().toUpperCase() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.themed(DesignColors.darkSurfaceElevated),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: context.themed(DesignColors.darkTextSecondary),
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
                    color: context.themed(DesignColors.darkTextPrimary),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  date.isNotEmpty ? _formatDate(date) : '',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: context.themed(DesignColors.darkTextTertiary)),
                ),
                if (reference != null && reference.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.xs),
                  Text(
                    '${provider == 'PAYSTACK' ? 'Paystack' : 'M-Pesa'} $reference',
                    style: DesignType.numeric(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: provider == 'PAYSTACK'
                          ? DesignColors.brand
                          : DesignColors.mpesa,
                    ),
                  ),
                ],
                if (status.toUpperCase() == 'PENDING' &&
                    provider == 'PAYSTACK' &&
                    reference != null &&
                    reference.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.xs),
                  TextButton.icon(
                    onPressed: _paystackInvoiceBusyId == reference
                        ? null
                        : () => _verifyPaystackPayment(reference),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Check payment'),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.xs,
                        vertical: DesignSpacing.xs,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                  color: context.themed(DesignColors.darkTextPrimary),
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
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              color: context.themed(DesignColors.darkTextTertiary), size: 36),
          const SizedBox(height: DesignSpacing.md),
          Text(
            'No invoices yet',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: context.themed(DesignColors.darkTextSecondary)),
          ),
          const SizedBox(height: DesignSpacing.xs),
          Text(
            'Invoices appear at each monthly renewal.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                color: context.themed(DesignColors.darkTextTertiary)),
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

  Widget _buildInvoiceError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSpacing.md,
        vertical: DesignSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: DesignColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: DesignColors.error, size: 18),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(child: Text(message)),
          TextButton(onPressed: _loadInvoices, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBillingNotice(String message) {
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: DesignColors.warning, size: 18),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String _amountLabel(SubscriptionPlan plan) {
    if (plan.id == 'trial') return 'Free trial';
    return 'KES ${_formatAmount(plan.priceKes)}';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
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
//  CHANGE PLAN SHEET
// ═══════════════════════════════════════════════════════════════════

/// A single selectable plan row inside the change-plan sheet. Deliberately
/// a plain tappable Container rather than RadioListTile — Flutter 3.32+
/// deprecated RadioListTile's groupValue/onChanged in favor of an ancestor
/// RadioGroup, which is unnecessary ceremony for one simple sheet-local
/// selection like this.
class _PlanRadioTile extends StatelessWidget {
  const _PlanRadioTile({
    required this.name,
    required this.priceLabel,
    required this.tagline,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  final String name;
  final String priceLabel;
  final String tagline;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected
          ? DesignColors.accent.withValues(alpha: 0.1)
          : context.themed(DesignColors.darkSurfaceElevated),
      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(DesignSpacing.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(
              color: isSelected
                  ? DesignColors.accent
                  : context.themed(DesignColors.darkBorder),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? DesignColors.accent
                      : context.themed(DesignColors.darkTextTertiary),
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: context.themed(DesignColors.darkTextPrimary),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: DesignSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: DesignSpacing.sm, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  DesignColors.success.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                  DesignSpacing.radiusFull),
                            ),
                            child: Text(
                              'Current',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: context.readable(DesignColors.success),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? DesignColors.accentDark
                            : context.themed(DesignColors.darkTextPrimary),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.themed(DesignColors.darkTextSecondary),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
  bool _acceptedAutoRenewal = false;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_autoRenew && !_acceptedAutoRenewal) {
      setState(() => _error = 'Accept the Auto-Renew Authorization before enabling it.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await getIt<ApiClient>().updateBillingSettings(
        autoRenewEnabled: _autoRenew,
        billingPhone: _phoneController.text.trim(),
        autoRenewAuthorizationVersion: _autoRenew
            ? policyVersion('AUTO_RENEWAL_AUTHORIZATION')
            : null,
      );
      widget.onSaved(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassSnackBar(
        context,
        _autoRenew
            ? 'Auto-renew on — we\u2019ll STK push ${_phoneController.text.trim()}'
            : 'Auto-renew off — pay each invoice through Paystack',
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
                    color: context.themed(DesignColors.darkBorder),
                    borderRadius: BorderRadius.circular(DesignSpacing.xs),
                  ),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Text(
                'Set up Auto-Renew',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: context.themed(DesignColors.darkTextPrimary),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                'We STK push the plan price to this number each month when '
                'the subscription renews.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.themed(DesignColors.darkTextSecondary),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: DesignSpacing.xl),
              if (_autoRenew) ...[
                CheckboxListTile(
                  value: _acceptedAutoRenewal,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(
                            () => _acceptedAutoRenewal = value ?? false,
                          ),
                  title: const Text(
                    'I authorize monthly M-Pesa STK prompts for the invoice amount to this phone. Each prompt still requires approval on the phone.',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        GoRouter.of(context).push('/legal/auto-renewal'),
                    child: const Text('Read Auto-Renew Authorization'),
                  ),
                ),
                const SizedBox(height: DesignSpacing.sm),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
                decoration: BoxDecoration(
                  color: context.themed(DesignColors.darkSurfaceElevated),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  border: Border.all(
                      color: context.themed(DesignColors.darkBorder)),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: context.themed(DesignColors.darkTextPrimary)),
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
