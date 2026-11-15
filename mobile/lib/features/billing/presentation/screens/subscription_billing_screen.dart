import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/legal/policy_catalog.dart';
import '../../../../core/widgets/legal_link.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../subscription/domain/subscription_plans.dart';
import '../../domain/billing_entitlement.dart';
import '../../domain/billing_snapshot.dart';
import '../desktop/desktop_billing_view.dart';
import '../widgets/plan_compare_sheet.dart';
import '../../../finance/presentation/desktop/desktop_figures_row.dart';
import '../providers/entitlement_provider.dart';
import '../../../../core/desktop/adaptive_sheet.dart';
import '../../../../core/desktop/desktop_refresh.dart';

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
    case 'NEEDS_REVIEW':
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
    case 'NEEDS_REVIEW':
      return 'On hold for review';
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

  /// `GET /subscription/plan`: the plan in force, any change scheduled for the
  /// next renewal, and the prices invoices use.
  Map<String, dynamic>? _plan;
  List<dynamic> _invoices = [];
  String? _invoiceError;
  bool _isLoadingEntitlement = true;
  bool _isLoadingInvoices = true;
  bool _invoicesLoadedOnce = false;
  bool _isChangingPlan = false;
  String? _error;

  /// One load at a time: pull-to-refresh, a payment return and a retry all
  /// join the load already running instead of starting another.
  Future<void>? _loading;
  final _snapshotStore = const BillingSnapshotStore();
  String? _paystackInvoiceBusyId;
  final Map<String, String> _mpesaInvoiceStatuses = {};
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
    final fromSettings = planById(_settings?['plan']?.toString());
    if (fromSettings != null) return fromSettings;
    return planById(_plan?['plan']?.toString());
  }

  SubscriptionPlan? get _pendingPlan =>
      planById(_settings?['pendingPlan']?.toString() ??
          _plan?['pendingPlan']?.toString());

  /// A change to a different plan that starts at the next renewal.
  ScheduledPlanChange? get _scheduledChange {
    final raw = _plan?['pendingChange'] ?? _settings?['pendingChange'];
    if (raw is! Map) return null;
    final id = raw['plan']?.toString().toLowerCase();
    if (id == null || planById(id) == null || id == 'trial') return null;
    return ScheduledPlanChange(
      planId: id,
      effectiveAt: DateTime.tryParse(raw['effectiveAt']?.toString() ?? ''),
    );
  }

  /// True only while there is genuinely nothing to show yet.
  bool get _showSkeleton =>
      _entitlement == null && _plan == null && (_isLoadingEntitlement || _loading != null);

  /// Calm status line while a saved copy is on screen and a refresh runs.
  bool get _isRefreshing => _loading != null;

  String? get _tenantId {
    if (!getIt.isRegistered<AuthService>()) return null;
    final user = getIt<AuthService>().currentUser;
    return (user?['tenantId'] ?? (user?['tenant'] as Map?)?['id'])?.toString();
  }

  @override
  void initState() {
    super.initState();
    _paystackLinkSubscription = _appLinks.uriLinkStream.listen(
      _handlePaystackReturn,
      onError: (_) {},
    );
    unawaited(_readInitialPaystackLink());
    unawaited(_startWithSnapshot());
  }

  /// Paint the saved copy at once (stale-while-revalidate), then refresh
  /// behind it. A copy younger than five minutes needs no refresh.
  Future<void> _startWithSnapshot() async {
    await PlanPrices.restore();
    final snapshot = await _snapshotStore.load(_tenantId);
    if (!mounted) return;
    final fresh = snapshot?.isFresh() ?? false;
    if (snapshot != null) {
      setState(() {
        // Snapshots are only written from a live answer, so a young one still
        // counts as live; an older one is shown as saved until refreshed.
        _entitlement = snapshot.entitlement == null
            ? null
            : BillingEntitlement.fromMap(
                snapshot.entitlement!,
                source: fresh
                    ? EntitlementSource.live
                    : EntitlementSource.offlineCache,
              );
        _plan = snapshot.plan;
        _invoices = snapshot.invoices;
        _invoicesLoadedOnce = true;
        _settings = snapshot.settings;
        _isLoadingEntitlement = false;
        _isLoadingInvoices = false;
      });
    }
    if (!fresh) unawaited(_loadData());
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

  /// Loads everything the page shows. Calls made while a load is running join
  /// it, so two triggers never race to overwrite each other.
  Future<void> _loadData() {
    final running = _loading;
    if (running != null) return running;
    late final Future<void> run;
    run = _runLoad().whenComplete(() {
      if (identical(_loading, run)) _loading = null;
      if (mounted) setState(() {});
    });
    _loading = run;
    if (mounted) setState(() {});
    return run;
  }

  /// Loads again after something changed (a payment, a plan change): waits for
  /// any load already running, whose answer may predate the change.
  Future<void> _reload() async {
    final running = _loading;
    if (running != null) await running;
    await _loadData();
  }

  Future<void> _runLoad() async {
    await Future.wait([_loadEntitlement(), _loadInvoices(), _loadPlan()]);
    if (_isAdmin) {
      await _loadSettings();
    }
    await _saveSnapshot();
  }

  /// Keep the latest live answer so the next visit paints at once. A failed
  /// refresh never reaches here with anything but the last good values.
  Future<void> _saveSnapshot() async {
    final entitlement = _entitlement;
    if (entitlement == null || entitlement.source != EntitlementSource.live) {
      return;
    }
    await _snapshotStore.save(
      _tenantId,
      BillingSnapshot(
        savedAt: DateTime.now(),
        entitlement: entitlement.toMap(),
        plan: _plan,
        invoices: _invoices,
        settings: _settings,
      ),
    );
  }

  Future<void> _loadEntitlement() async {
    // A saved copy is already on screen: refresh behind it, no spinner.
    if (_entitlement == null && mounted) {
      setState(() {
        _isLoadingEntitlement = true;
        _error = null;
      });
    }
    try {
      // Live fetch (falls back to the last known answer or the offline cache).
      final entitlement = await refreshEntitlement();
      if (!mounted) return;
      setState(() {
        // Never replace something we can show with nothing, and never replace
        // a confirmed answer with an older saved one.
        final current = _entitlement;
        if (entitlement != null &&
            entitlement.source != EntitlementSource.live &&
            current?.source == EntitlementSource.live) {
          // Keep the confirmed details, but say they are no longer confirmed.
          _entitlement = current!.copyWith(source: EntitlementSource.offlineCache);
        } else if (entitlement != null) {
          _entitlement = entitlement;
        }
        _isLoadingEntitlement = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingEntitlement = false;
        // Only worth an error card when there is nothing else to show.
        _error = _entitlement == null ? _friendlyError(error) : null;
      });
    }
  }

  Future<void> _loadInvoices() async {
    if (!_invoicesLoadedOnce && mounted) {
      setState(() {
        _isLoadingInvoices = true;
        _invoiceError = null;
      });
    }
    try {
      final invoices = await _apiClient.getBillingInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _isLoadingInvoices = false;
        _invoicesLoadedOnce = true;
        _invoiceError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingInvoices = false;
        // Keep the invoices already shown; only say so when there are none.
        _invoiceError = _invoices.isEmpty ? _friendlyError(error) : null;
      });
    }
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await _apiClient.getSubscriptionPlan();
      await PlanPrices.apply(plan['availablePlans']);
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (_) {
      // The plan and its prices are refinements; the entitlement drives the
      // page, and a saved copy or the bundled prices stand in.
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
    return apiErrorMessage(error);
  }

  // ── Plan changes ────────────────────────────────────────────────────

  String? get _statusUpper => _entitlement?.status.toUpperCase();

  /// A trial, an active plan or an overdue one can be changed. A suspended or
  /// lapsed one is settled by paying first.
  bool get _canManagePlan {
    final status = _statusUpper;
    return _isAdmin &&
        _billingPlan != null &&
        (status == 'TRIAL' ||
            status == 'ACTIVE' ||
            status == 'PAST_DUE' ||
            status == 'GRACE_PERIOD');
  }

  bool get _isOverdue {
    final status = _statusUpper;
    return status == 'PAST_DUE' || status == 'GRACE_PERIOD';
  }

  DateTime? get _renewsOn => DateTime.tryParse(_entitlement?.paidUntil ?? '');

  /// Manage plan: every plan side by side, with upgrade, downgrade and keep.
  Future<void> _openManagePlan() async {
    if (!_canManagePlan) {
      _showPaymentMessage(
        _billingPlan == null
            ? 'Your plan is still loading. Try again in a moment.'
            : 'Plan changes open again once your subscription payment is confirmed.',
      );
      return;
    }
    final current = (_billingPlan?.id ?? 'core').toLowerCase();
    final saved = await showAdaptiveModalSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.themed(DesignColors.darkSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => PlanCompareSheet(
        currentPlanId: current,
        isTrial: _statusUpper == 'TRIAL',
        overdue: _isOverdue,
        renewsOn: _renewsOn,
        scheduled: _scheduledChange,
        errorText: _friendlyError,
        onChange: _saveChosenPlan,
        onCancelChange: _cancelScheduledChange,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      showGlassSnackBar(
        context,
        'Plan change saved',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
    }
  }

  Future<void> _saveChosenPlan(String planId) async {
    setState(() => _isChangingPlan = true);
    try {
      await _apiClient.acceptLegalPolicy(
        policyType: 'BILLING_TERMS',
        policyVersion: policyVersion('BILLING_TERMS'),
      );
      await _apiClient.changeSubscriptionPlan(planId: planId.toUpperCase());
      // Refresh the page behind the sheet while it shows the confirmation.
      unawaited(_reload());
    } finally {
      if (mounted) setState(() => _isChangingPlan = false);
    }
  }

  Future<void> _cancelScheduledChange() async {
    await _apiClient.cancelSubscriptionPlanChange();
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    if (context.inDesktopShell) return _buildDesktop();
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Scaffold(
        backgroundColor: context.themed(DesignColors.darkBg),
        appBar: const BrandedAppBar(
          title: 'Plan & Billing',
        ),
        body: DesktopRefresh(
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
              // A refresh behind saved details: a hairline, not a spinner.
              if (_isRefreshing && _entitlement != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
                  child: const LinearProgressIndicator(
                    key: ValueKey('billing-refreshing'),
                    minHeight: 2,
                    color: DesignColors.accent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const SizedBox(height: DesignSpacing.sm),
              ],
              if (_error != null && _entitlement == null) ...[
                _buildErrorCard(_error!),
                const SizedBox(height: DesignSpacing.lg),
              ],
              if (_entitlement?.source == EntitlementSource.offlineCache &&
                  !_isRefreshing) ...[
                _buildBillingNotice(
                  'Showing your last saved billing details. We could not confirm them just now.',
                  onRetry: _loadData,
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
              else if (_showSkeleton)
                const _SkeletonBlock(height: 76)
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
              if (_isLoadingInvoices && _invoices.isEmpty) ...const [
                _SkeletonBlock(height: 64),
                SizedBox(height: DesignSpacing.sm),
                _SkeletonBlock(height: 64),
              ] else if (_invoices.isEmpty && _invoiceError == null)
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

  // ── Computer layout ─────────────────────────────────────────────────

  /// Plan & Billing inside the desktop shell: the same state and payment
  /// calls as the phone page, drawn as figures, two panels and a table.
  Widget _buildDesktop() {
    final entitlement = _entitlement;
    final billingPlan = _billingPlan;
    final days = entitlement?.daysRemaining;
    final overdue = entitlement?.daysOverdue ?? 0;
    final nextPayment = entitlement?.paidUntil;

    String? daysHint;
    if (days != null) {
      if (days <= 0) {
        daysHint = overdue > 0
            ? 'Overdue by $overdue ${overdue == 1 ? 'day' : 'days'}'
            : 'Due for renewal';
      } else {
        daysHint = '$days ${days == 1 ? 'day' : 'days'} left';
      }
    }

    final figures = <DesktopFigure>[
      DesktopFigure(
        label: 'Plan',
        value: billingPlan?.name ?? 'Unavailable',
        hint: billingPlan == null
            ? null
            : billingPlan.id == 'trial'
                ? 'Free trial'
                : 'KES ${_formatAmount(billingPlan.priceKes)} a month',
      ),
      DesktopFigure(
        label: 'Status',
        value: entitlement == null ? '—' : _statusLabel(entitlement.status),
        hint: entitlement?.source == EntitlementSource.offlineCache
            ? 'Saved on this computer'
            : null,
      ),
      DesktopFigure(
        label: 'Next payment',
        value: nextPayment == null ? '—' : _formatDate(nextPayment),
        hint: daysHint,
        valueColor: days != null && days <= 0 ? DesignColors.error : null,
      ),
      DesktopFigure(
        label: 'Branches and users',
        value: entitlement?.maxBranches == null
            ? '—'
            : '${formatLimit(entitlement!.maxBranches)} branches',
        hint: entitlement?.maxUsers == null
            ? null
            : '${formatLimit(entitlement!.maxUsers)} users',
      ),
    ];

    final notices = <DesktopBillingNotice>[
      if (_error != null && entitlement == null)
        DesktopBillingNotice(_error!, tone: DesktopBillingTone.error),
      if (entitlement?.source == EntitlementSource.offlineCache &&
          !_isRefreshing)
        const DesktopBillingNotice(
          'Showing your last saved billing details. We could not confirm them just now; use Refresh to try again.',
        ),
      if (_scheduledChange != null && _isAdmin)
        DesktopBillingNotice(_scheduledChangeSentence()),
      if (entitlement?.state == EntitlementState.grace)
        const DesktopBillingNotice(
          'Payment overdue — you’re in the 3-day grace period. '
          'Pay now to keep creating sales.',
        ),
      if (entitlement != null &&
          (entitlement.state == EntitlementState.unknown ||
              billingPlan == null) &&
          entitlement.source != EntitlementSource.offlineCache &&
          !_isRefreshing)
        const DesktopBillingNotice(
          'We could not confirm your plan and renewal date yet.',
        ),
    ];

    final admin = _isAdmin;
    final isTrial = entitlement?.status.toUpperCase() == 'TRIAL';
    final license = entitlement?.license;
    final settings = _settings;
    final autoRenew = settings?['autoRenewEnabled'] == true;
    final phone = settings?['billingPhone']?.toString() ?? '';

    String seats(int? n) => n == null
        ? '—'
        : n >= 1000
            ? 'Unlimited'
            : '$n';

    return Scaffold(
      body: DesktopBillingView(
        loading: entitlement == null && (_isLoadingEntitlement || _isRefreshing),
        unavailable: entitlement == null,
        figures: figures,
        notices: notices,
        onRefresh: _loadData,
        renewal: _desktopRenewal(),
        planSummary: admin ? _planSummary() : null,
        choosePlan: admin && _canManagePlan
            ? DesktopBillingAction(
                label: isTrial ? 'Choose plan' : 'Change plan',
                icon: Icons.tune_rounded,
                onPressed: _isChangingPlan ? null : _openManagePlan,
              )
            : null,
        licence: admin && license != null
            ? DesktopBillingLicence(
                modules: [
                  for (final key in LicensedFeature.labels.keys)
                    (
                      label: LicensedFeature.labels[key]!,
                      allowed: (license.planFeatures[key] ?? true) &&
                          license.allows(key),
                    ),
                ],
                limits:
                    'Up to ${seats(license.maxBranches)} branches · ${seats(license.maxUsers)} users',
                licenceKey: license.licenseKey,
                expired: license.expired,
              )
            : null,
        autoRenew: admin
            ? DesktopBillingAutoRenew(
                enabled: autoRenew,
                summary: autoRenew
                    ? (phone.isEmpty
                        ? 'Add a billing phone so we can charge it'
                        : 'On — $phone')
                    : 'Off — pay each invoice through secure checkout',
                onConfigure: _showAutoRenewSheet,
              )
            : null,
        onFreeDays: admin ? () => context.push('/referrals') : null,
        invoices: [
          for (final raw in _invoices)
            _desktopInvoice(Map<String, dynamic>.from(raw as Map)),
        ],
        invoicesLoading: _isLoadingInvoices,
        invoiceError: _invoiceError,
        onRetryInvoices: _loadInvoices,
      ),
    );
  }

  DesktopBillingRenewal _desktopRenewal() {
    if (_billingPlan == null) {
      return DesktopBillingRenewal(
        message: _showSkeleton || _isRefreshing
            ? 'Loading your plan…'
            : 'We could not load your plan yet, so a payment cannot start. Check your connection and retry.',
        secondary: DesktopBillingAction(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: _loadData,
        ),
      );
    }
    final renewal = _renewalDecision();
    switch (renewal.kind) {
      case _RenewalKind.notice:
        return DesktopBillingRenewal(message: renewal.message);
      case _RenewalKind.preparing:
        return DesktopBillingRenewal(
          message: renewal.message,
          secondary: DesktopBillingAction(
            label: 'Refresh status',
            icon: Icons.refresh_rounded,
            onPressed: _loadData,
          ),
        );
      case _RenewalKind.pendingMpesa:
        final invoice = renewal.invoice!;
        final invoiceId = invoice['id']?.toString() ?? '';
        final needsReview = _mpesaInvoiceStatuses[invoiceId] == 'NEEDS_REVIEW';
        return DesktopBillingRenewal(
          message: renewal.message,
          secondary: DesktopBillingAction(
            label: 'Check M-Pesa status',
            icon: Icons.refresh_rounded,
            busy: invoiceId.isNotEmpty && _paystackInvoiceBusyId == invoiceId,
            onPressed: invoiceId.isEmpty ||
                    _paystackInvoiceBusyId != null ||
                    needsReview
                ? null
                : () => _checkMpesaRenewalStatus(invoiceId),
          ),
        );
      case _RenewalKind.pay:
        final busy = _paystackInvoiceBusyId == 'current';
        return DesktopBillingRenewal(
          message: 'A subscription payment is due. '
              'Pay securely by card or M-Pesa to keep every feature on.',
          primary: DesktopBillingAction(
            label: busy ? 'Opening secure checkout…' : 'Pay subscription securely',
            icon: Icons.lock_rounded,
            busy: busy,
            onPressed: busy ? null : _startPaystackInvoicePayment,
          ),
          note: _payerNote,
        );
    }
  }

  DesktopBillingInvoice _desktopInvoice(Map<String, dynamic> invoice) {
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
    final invoiceId = invoice['id']?.toString() ?? '';
    final mpesaCheckoutId = invoice['mpesaCheckoutId']?.toString() ?? '';
    final hasReference = reference != null && reference.isNotEmpty;

    DesktopBillingAction? check;
    if (status.toUpperCase() == 'PENDING' &&
        provider == 'PAYSTACK' &&
        hasReference) {
      check = DesktopBillingAction(
        label: 'Check payment',
        icon: Icons.refresh_rounded,
        busy: _paystackInvoiceBusyId == reference,
        onPressed: _paystackInvoiceBusyId == reference
            ? null
            : () => _verifyPaystackPayment(reference),
      );
    } else if (status.toUpperCase() != 'PAID' &&
        provider == 'JENGA_STK' &&
        mpesaCheckoutId.isNotEmpty &&
        invoiceId.isNotEmpty) {
      check = DesktopBillingAction(
        label: 'Check M-Pesa status',
        icon: Icons.refresh_rounded,
        busy: _paystackInvoiceBusyId == invoiceId,
        onPressed: _paystackInvoiceBusyId == null
            ? () => _checkMpesaRenewalStatus(invoiceId)
            : null,
      );
    }

    return DesktopBillingInvoice(
      id: invoiceId.isNotEmpty ? invoiceId : '$description-$date',
      description: description,
      dateLabel: date.isNotEmpty ? _formatDate(date) : '—',
      date: DateTime.tryParse(date),
      amount: amount.toDouble(),
      amountLabel: '$currency ${_formatAmount(amount)}',
      statusLabel: status.isEmpty
          ? '—'
          : (_statusLabel(status) == status
              ? status.replaceAll('_', ' ')
              : _statusLabel(status)),
      statusColor: statusColor(status),
      method: !hasReference
          ? ''
          : provider == 'PAYSTACK'
              ? 'Card'
              : 'M-Pesa',
      reference: hasReference ? reference : null,
      check: check,
    );
  }

  // ── Entitlement summary card ────────────────────────────────────────

  Widget _buildEntitlementCard() {
    final theme = Theme.of(context);
    if (_entitlement == null && (_isLoadingEntitlement || _isRefreshing)) {
      // Same footprint as the card it becomes, so nothing jumps when it lands.
      return const _SkeletonBlock(
        key: ValueKey('billing-skeleton'),
        height: 244,
        radius: DesignSpacing.radiusXl,
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
            Icon(Icons.cloud_off_rounded,
                color: context.themed(DesignColors.darkTextTertiary), size: 40),
            const SizedBox(height: DesignSpacing.md),
            Text(
              'We could not load your plan yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.themed(DesignColors.darkTextSecondary)),
            ),
            const SizedBox(height: DesignSpacing.sm),
            TextButton.icon(
              key: const ValueKey('billing-retry'),
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
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
        color: isDark
            ? context.themed(DesignColors.darkSurfaceElevated)
            : const Color(0xFFFFE6D2),
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
          if (_scheduledChange != null)
            _buildInfoRow(Icons.swap_horiz_rounded, _scheduledChangeSentence()),
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
    final isTrial = _statusUpper == 'TRIAL';
    final scheduled = _scheduledChange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _manageTile(plan, isTrial, _planSummary()),
        if (scheduled != null) ...[
          const SizedBox(height: DesignSpacing.sm),
          _buildScheduledChangeBanner(),
        ],
      ],
    );
  }

  /// "Switching to Core on 1 Dec 2026" for a change waiting on the renewal.
  String _scheduledChangeSentence() {
    final s = _scheduledChange!;
    final when =
        s.effectiveAt == null ? 'your next renewal' : _formatDate(s.effectiveAt!.toIso8601String());
    return 'Switching to ${planDisplayName(s.planId)} on $when';
  }

  Widget _buildScheduledChangeBanner() {
    return Container(
      key: const ValueKey('scheduled-change-banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSpacing.md,
        vertical: DesignSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: DesignColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: DesignColors.accent),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              _scheduledChangeSentence(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextPrimary),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          TextButton(
            key: const ValueKey('cancel-scheduled-change'),
            onPressed: _isChangingPlan ? null : _cancelScheduledFromBanner,
            child: const Text('Cancel change'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelScheduledFromBanner() async {
    setState(() => _isChangingPlan = true);
    try {
      await _cancelScheduledChange();
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Change cancelled. You are staying on ${_billingPlan?.name ?? 'your plan'}.',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
    } catch (error) {
      if (mounted) _showPaymentMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _isChangingPlan = false);
    }
  }

  /// The "Manage plan" sentence, shared by the phone tile and the computer panel.
  String _planSummary() {
    final plan = _billingPlan;
    final status = _statusUpper;
    final isTrial = status == 'TRIAL';
    final isActive = status == 'ACTIVE';
    final String planSummary;
    if (plan == null) {
      planSummary = _showSkeleton || _isRefreshing
          ? 'Loading your plan…'
          : 'We could not load your plan yet. Pull down to try again';
    } else if (_entitlement == null || status == null || status == 'UNKNOWN') {
      planSummary = 'We could not confirm your subscription status yet';
    } else if (_entitlement!.source != EntitlementSource.live) {
      planSummary = _isRefreshing
          ? '${plan.name} · checking the latest…'
          : 'Saved status: ${_statusLabel(status)} · not confirmed just now';
    } else if (isTrial) {
      planSummary = _pendingPlan == null
          ? '${plan.name} · choose the plan for after your trial'
          : '${plan.name} · ${_pendingPlan!.name} selected for after your trial';
    } else if (isActive) {
      planSummary = _scheduledChange == null
          ? '${plan.name} · active · tap to see other plans'
          : '${plan.name} · ${_scheduledChangeSentence().toLowerCase()}';
    } else {
      planSummary = '${plan.name} · ${_statusLabel(status)}';
    }
    return planSummary;
  }

  Widget _manageTile(SubscriptionPlan? plan, bool isTrial, String planSummary) {
    final canTap = _canManagePlan && !_isChangingPlan;
    return TapScale(
      enabled: canTap,
      child: Material(
        color: context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          side: BorderSide(color: context.themed(DesignColors.darkBorder)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('manage-plan-tile'),
          onTap: canTap ? _openManagePlan : null,
          child: Padding(
            padding: const EdgeInsets.all(DesignSpacing.md),
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
                        planSummary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  context.themed(DesignColors.darkTextSecondary),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                if (canTap)
                  Text(
                    isTrial ? 'Choose' : 'Change',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: DesignColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                if (canTap)
                  Icon(Icons.chevron_right_rounded,
                      color: context.themed(DesignColors.darkTextTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  String get _payerEmail {
    if (!getIt.isRegistered<AuthService>()) return '';
    return getIt<AuthService>().currentUser?['email']?.toString().trim() ?? '';
  }

  String get _payerNote => _payerEmail.isEmpty
      ? 'The payment partner uses the signed-in shop account email for the subscription checkout.'
      : 'Subscription payer email: $_payerEmail. This is the signed-in shop account email.';

  Widget _buildPayWithMpesaButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GradientButton(
          label: _paystackInvoiceBusyId == 'current'
              ? 'Opening secure checkout…'
              : 'Pay subscription securely',
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
                _payerNote,
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
    final renewal = _renewalDecision();
    return switch (renewal.kind) {
      _RenewalKind.notice => _buildBillingNotice(renewal.message),
      _RenewalKind.preparing => _buildInvoicePreparationNotice(renewal.message),
      _RenewalKind.pendingMpesa => _buildPendingMpesaRenewal(renewal.invoice!),
      _RenewalKind.pay => _buildPayWithMpesaButton(),
    };
  }

  String _mpesaPendingMessage(Map<String, dynamic> invoice) {
    final invoiceId = invoice['id']?.toString() ?? '';
    final needsReview = _mpesaInvoiceStatuses[invoiceId] == 'NEEDS_REVIEW';
    return needsReview
        ? 'The provider reported an amount mismatch. This invoice is held for review; contact support before retrying.'
        : 'An M-Pesa renewal prompt is still being confirmed. Approve it on the billing phone, then check its status here.';
  }

  /// What the renewal area should say or offer right now. The phone and the
  /// computer layouts both render this one decision.
  _Renewal _renewalDecision() {
    // Only the very first look has nothing to go on; after that a refresh
    // happens behind what is already shown.
    if ((_isLoadingEntitlement && _entitlement == null) ||
        (_isLoadingInvoices && !_invoicesLoadedOnce)) {
      return const _Renewal(
        _RenewalKind.notice,
        'Checking whether a subscription payment is due…',
      );
    }

    final entitlement = _entitlement;
    if (entitlement != null &&
        entitlement.source != EntitlementSource.live &&
        _isRefreshing) {
      return const _Renewal(
        _RenewalKind.notice,
        'Checking your latest billing details…',
      );
    }
    if (entitlement == null ||
        entitlement.source != EntitlementSource.live ||
        entitlement.status.toUpperCase() == 'UNKNOWN') {
      return const _Renewal(
        _RenewalKind.preparing,
        'We could not confirm your subscription just now. Refresh before starting a payment.',
      );
    }
    final openInvoice = _openInvoiceForPayment();
    final invoiceStatus = openInvoice?['status']?.toString().toUpperCase();
    if (invoiceStatus == 'NEEDS_REVIEW') {
      return const _Renewal(
        _RenewalKind.notice,
        'This invoice is on hold for a payment review. Do not retry it; contact support@archeaxon.com with the invoice reference.',
      );
    }
    final provider = openInvoice?['provider']?.toString().toUpperCase();
    if (provider == 'JENGA_STK_INITIALIZING') {
      return const _Renewal(
        _RenewalKind.preparing,
        'The M-Pesa renewal request is being prepared. Refresh in a moment before starting another payment.',
      );
    }
    if (provider == 'JENGA_STK' &&
        openInvoice?['mpesaCheckoutId']?.toString().isNotEmpty == true) {
      return _Renewal(
        _RenewalKind.pendingMpesa,
        _mpesaPendingMessage(openInvoice!),
        invoice: openInvoice,
      );
    }
    if (provider == 'JENGA_STK') {
      return const _Renewal(
        _RenewalKind.preparing,
        'An M-Pesa renewal is reserved but its status reference is unavailable. Refresh the invoice before retrying.',
      );
    }
    if (provider == 'PAYSTACK_INITIALIZING' ||
        (provider == 'PAYSTACK' &&
            openInvoice?['authorizationUrl']?.toString().isNotEmpty != true)) {
      return const _Renewal(
        _RenewalKind.preparing,
        'Secure checkout is being prepared. Refresh in a moment before trying again.',
      );
    }
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

    if (paymentDue) return const _Renewal(_RenewalKind.pay, '');
    if (status == 'TRIAL') {
      final end = entitlement.paidUntil;
      return _Renewal(
        _RenewalKind.notice,
        end == null
            ? 'Your free trial is active. No subscription payment is due yet.'
            : 'Your free trial is active through ${_formatDate(end)}. No subscription payment is due yet.',
      );
    }
    if (status == 'ACTIVE') {
      final end = entitlement.paidUntil;
      return _Renewal(
        _RenewalKind.notice,
        end == null
            ? 'Your subscription is active. No payment is due now.'
            : 'Your subscription is active through ${_formatDate(end)}. No payment is due now.',
      );
    }
    return const _Renewal(_RenewalKind.pay, '');
  }

  Map<String, dynamic>? _openInvoiceForPayment() {
    for (final rawInvoice in _invoices) {
      final invoice = Map<String, dynamic>.from(rawInvoice as Map);
      if (invoice['status']?.toString().toUpperCase() != 'PAID') {
        return invoice;
      }
    }
    return null;
  }

  Widget _buildInvoicePreparationNotice(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBillingNotice(message),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh status'),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingMpesaRenewal(Map<String, dynamic> invoice) {
    final invoiceId = invoice['id']?.toString() ?? '';
    final busy = invoiceId.isNotEmpty && _paystackInvoiceBusyId == invoiceId;
    final needsReview = _mpesaInvoiceStatuses[invoiceId] == 'NEEDS_REVIEW';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBillingNotice(_mpesaPendingMessage(invoice)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: invoiceId.isEmpty ||
                    _paystackInvoiceBusyId != null ||
                    needsReview
                ? null
                : () => _checkMpesaRenewalStatus(invoiceId),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(busy ? 'Checking…' : 'Check M-Pesa status'),
          ),
        ),
      ],
    );
  }

  Future<void> _checkMpesaRenewalStatus(String invoiceId) async {
    if (_paystackInvoiceBusyId != null) return;
    setState(() => _paystackInvoiceBusyId = invoiceId);
    try {
      final result = await _apiClient.verifyMpesaSubscriptionPayment(invoiceId);
      if (!mounted) return;
      final invoiceStatus =
          result['invoiceStatus']?.toString().toUpperCase() ?? '';
      final paymentStatus = result['status']?.toString().toUpperCase() ?? '';
      setState(() {
        if (invoiceStatus == 'PAID' ||
            ['FAILED', 'CANCELLED', 'CANCELED'].contains(paymentStatus)) {
          _mpesaInvoiceStatuses.remove(invoiceId);
        } else {
          _mpesaInvoiceStatuses[invoiceId] = paymentStatus;
        }
      });
      if (invoiceStatus == 'PAID') {
        ref.read(entitlementRefreshTickProvider.notifier).state++;
        await _reload();
        if (mounted) {
          _showPaymentMessage('Monthly subscription payment confirmed.');
        }
      } else {
        await _loadInvoices();
        if (!mounted) return;
        if (['FAILED', 'CANCELLED', 'CANCELED'].contains(paymentStatus)) {
          _showPaymentMessage(
            'The M-Pesa request did not complete. The invoice is still due; you can continue with secure checkout.',
            isError: true,
          );
        } else if (paymentStatus == 'NEEDS_REVIEW') {
          _showPaymentMessage(
            'The provider reported a payment amount mismatch. The invoice is on hold; contact support before retrying.',
            isError: true,
          );
        } else {
          _showPaymentMessage(
            'M-Pesa is still processing. Approve the prompt, then check again.',
          );
        }
      }
    } catch (error) {
      if (mounted) _showPaymentMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _paystackInvoiceBusyId = null);
    }
  }

  Future<void> _startPaystackInvoicePayment() async {
    setState(() => _paystackInvoiceBusyId = 'current');
    try {
      final checkout = await _apiClient.initializePaystackSubscriptionPayment();
      if (checkout['status'] == 'PAID') {
        await _reload();
        if (mounted) _showPaymentMessage('This invoice is already paid.');
        return;
      }
      final url = checkout['authorizationUrl']?.toString();
      final uri = url == null || url.isEmpty ? null : Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'checkout.paystack.com') {
        throw const _CheckoutUnavailable();
      }
      if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
        throw const _CheckoutUnavailable();
      }
    } catch (error) {
      if (!mounted) return;
      if (error is _CheckoutUnavailable) {
        // Every tap asks for a link again, and links that have gone stale are
        // replaced on the server, so trying again gets a fresh one.
        _showPaymentMessage(
          'We could not open the secure checkout. Try again for a fresh link.',
          isError: true,
          retry: _startPaystackInvoicePayment,
        );
      } else {
        final held = error is DioException &&
            (error.response?.statusCode == 409 ||
                error.response?.statusCode == 403);
        _showPaymentMessage(
          _friendlyError(error),
          isError: true,
          retry: held ? null : _startPaystackInvoicePayment,
        );
      }
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
      final status = result['status']?.toString().toUpperCase();
      if (status == 'PAID') {
        ref.read(entitlementRefreshTickProvider.notifier).state++;
        await _reload();
        if (mounted) {
          _showPaymentMessage('Monthly subscription payment confirmed.');
        }
      } else if (status == 'NEEDS_REVIEW') {
        await _loadInvoices();
        if (mounted) {
          _showPaymentMessage(
            'Payment is on hold for a billing review. Contact support@archeaxon.com before retrying.',
            isError: true,
          );
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

  void _showPaymentMessage(
    String message, {
    bool isError = false,
    Future<void> Function()? retry,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? DesignColors.error : DesignColors.success,
        duration: retry == null
            ? const Duration(seconds: 4)
            : const Duration(seconds: 8),
        action: retry == null
            ? null
            : SnackBarAction(
                label: 'Try again',
                textColor: Colors.white,
                onPressed: () => unawaited(retry()),
              ),
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
            child: Text(
                'We could not load your plan yet, so a payment cannot start. Check your connection and retry.'),
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
                      : 'Off — pay each invoice through secure checkout',
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
    showAdaptiveModalSheet(
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
    final invoiceId = invoice['id']?.toString() ?? '';
    final mpesaCheckoutId = invoice['mpesaCheckoutId']?.toString() ?? '';

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
                    '${provider == 'PAYSTACK' ? 'Card' : 'M-Pesa'} $reference',
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
                if (status.toUpperCase() != 'PAID' &&
                    provider == 'JENGA_STK' &&
                    mpesaCheckoutId.isNotEmpty &&
                    invoiceId.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.xs),
                  TextButton.icon(
                    onPressed: _paystackInvoiceBusyId == null
                        ? () => _checkMpesaRenewalStatus(invoiceId)
                        : null,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Check M-Pesa status'),
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

  Widget _buildBillingNotice(String message, {VoidCallback? onRetry}) {
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
          if (onRetry != null)
            TextButton(
              key: const ValueKey('billing-notice-retry'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
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

enum _RenewalKind { notice, preparing, pendingMpesa, pay }

/// The renewal area's current state, shared by the phone and computer layouts.
class _Renewal {
  const _Renewal(this.kind, this.message, {this.invoice});

  final _RenewalKind kind;
  final String message;
  final Map<String, dynamic>? invoice;
}

/// Status badge colors shared with the banner tests — public because the
/// reminder banner and tests reuse the same palette.
Color statusColor(String? status) => _statusColor(status);

/// The checkout page could not be opened (no usable link, or the device
/// refused to open it). Not an error worth showing raw; the owner just retries.
class _CheckoutUnavailable implements Exception {
  const _CheckoutUnavailable();
}

/// A placeholder with the footprint of what is loading, so the page does not
/// jump when the real card arrives. Pulses softly; still when motion is off.
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    super.key,
    required this.height,
    this.radius = DesignSpacing.radiusLg,
  });

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base = context.themed(DesignColors.darkSurface);
    final shape = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.themed(DesignColors.darkBorder)),
      ),
    );
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return shape;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: context.themed(DesignColors.darkSurfaceElevated),
      child: shape,
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
      setState(() =>
          _error = 'Accept the Auto-Renew Authorization before enabling it.');
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
        autoRenewAuthorizationVersion:
            _autoRenew ? policyVersion('AUTO_RENEWAL_AUTHORIZATION') : null,
      );
      widget.onSaved(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassSnackBar(
        context,
        _autoRenew
            ? 'Auto-renew on — we\u2019ll STK push ${_phoneController.text.trim()}'
            : 'Auto-renew off — pay each invoice through secure checkout',
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
                  title: const TermsConsentText(
                    before:
                        'I authorize monthly M-Pesa STK prompts for the invoice amount to this phone. Each prompt still requires approval on the phone. See ',
                    linkText: 'auto-renewal terms',
                    after: '.',
                    route: '/legal/auto-renewal',
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: LegalLinkText(
                    text: 'Read Auto-Renew Authorization',
                    route: '/legal/auto-renewal',
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
