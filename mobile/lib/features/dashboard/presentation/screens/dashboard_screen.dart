import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/app_markdown.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/theme/share_format_sheet.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../ai/presentation/screens/ai_chat_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../finance/presentation/end_of_day_prompt.dart';
import '../widgets/staff_invite_nudge.dart';
import '../../../onboarding/presentation/widgets/setup_progress_card.dart';
import '../widgets/home_cards.dart';
import '../desktop/desktop_home_models.dart';
import '../desktop/desktop_home_providers.dart';
import '../desktop/desktop_home_view.dart';
import '../../../accountability/presentation/providers/accountability_provider.dart';
import '../../../onboarding/presentation/setup_providers.dart';
import '../../../licence/domain/licence_standing.dart';
import '../../../licence/presentation/licence_providers.dart';
import '../../../home/domain/shop_guidance.dart';
import '../../../accountability/presentation/widgets/shop_attention_card.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/load_error.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../../notifications/presentation/widgets/notification_bell.dart';

final _dashboardSummaryProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final db = getIt<AppDatabase>();
  // Publish local figures as soon as they are read. Cloud totals refresh
  // independently so a slow connection cannot hold the dashboard's first
  // useful paint or subsequent local sale updates hostage.
  final updates = StreamController<Map<String, dynamic>>();
  Map<String, dynamic>? localSnapshot;
  Map<String, dynamic>? serverSalesSnapshot;
  final localWorkspace = getIt<AuthService>().isLocalWorkspace;
  var localRevision = 0;
  var serverRefreshInFlight = false;
  var disposed = false;

  Future<void> refreshLocal() async {
    final revision = ++localRevision;
    try {
      final local = await db.getDashboardSummary();
      if (disposed || revision != localRevision) return;
      localSnapshot = local;
      updates.add(
        serverSalesSnapshot == null
            ? local
            : mergeDashboardSummary(local, serverSalesSnapshot!),
      );
    } catch (error, stackTrace) {
      if (!disposed) updates.addError(error, stackTrace);
    }
  }

  Future<void> refreshServer() async {
    if (localWorkspace || disposed || serverRefreshInFlight) return;
    serverRefreshInFlight = true;
    try {
      final data = await getIt<ApiClient>().getDashboard();
      if (disposed) return;
      serverSalesSnapshot =
          (data['sales'] as Map<String, dynamic>?) ?? const {};
      final local = localSnapshot;
      if (local != null) {
        updates.add(mergeDashboardSummary(local, serverSalesSnapshot!));
      }
    } catch (_) {
      // Keep the local snapshot visible when the workspace cannot be reached.
    } finally {
      serverRefreshInFlight = false;
    }
  }

  final salesSub = db.watchTodaysSales().listen(
    (_) {
      unawaited(refreshLocal());
      unawaited(refreshServer());
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!disposed) updates.addError(error, stackTrace);
    },
  );
  final timer = localWorkspace
      ? null
      : Timer.periodic(
          const Duration(seconds: 45),
          (_) => unawaited(refreshServer()),
        );
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    salesSub.cancel();
    updates.close();
  });
  // Start both paths independently. Local data is emitted without waiting for
  // the API, while a successful cloud response replaces it with the merged view.
  unawaited(refreshLocal());
  unawaited(refreshServer());
  return updates.stream;
});

/// Combines all-device cloud totals with sales still waiting to sync from this
/// device. Legacy callers without unsynced counters retain the previous max
/// behavior because their local figures may already overlap the cloud totals.
@visibleForTesting
Map<String, dynamic> mergeDashboardSummary(
  Map<String, dynamic> local,
  Map<String, dynamic> serverSales,
) {
  final hasUnsyncedCounters = local.containsKey('unsyncedTransactionCount') &&
      local.containsKey('unsyncedRevenue') &&
      local.containsKey('unsyncedItemsSold');

  num pick(String localKey, String serverKey, num unsynced) {
    final localValue = (local[localKey] as num?) ?? 0;
    final serverValue = serverSales[serverKey];
    if (serverValue is! num) return localValue;
    if (hasUnsyncedCounters) return serverValue + unsynced;
    return localValue >= serverValue ? localValue : serverValue;
  }

  final transactionCount = pick(
    'transactionCount',
    'totalSales',
    (local['unsyncedTransactionCount'] as num?) ?? 0,
  );
  final totalRevenue = pick(
    'totalRevenue',
    'totalRevenue',
    (local['unsyncedRevenue'] as num?) ?? 0,
  );
  final serverAverage = serverSales['averageTicket'];
  final avgTicket =
      hasUnsyncedCounters && serverAverage is num && transactionCount > 0
          ? totalRevenue / transactionCount
          : pick('avgTicket', 'averageTicket', 0);

  return {
    'transactionCount': transactionCount,
    'totalRevenue': totalRevenue,
    'avgTicket': avgTicket,
    'itemsSold': pick(
      'itemsSold',
      'itemsSold',
      (local['unsyncedItemsSold'] as num?) ?? 0,
    ),
  };
}

final _todaysCostProvider = FutureProvider.autoDispose<double>((ref) async {
  final branchId = getIt<AuthService>().branchId;
  if (branchId == null) return 0.0;
  return getIt<AppDatabase>().getTodaysTotalPurchases(branchId);
});

/// Today's end-of-day close status for the dashboard's admin-only card —
/// null result means "not closed yet"; the underlying getDailyClose(...)
/// already distinguishes that from a load failure via its own exception.
final _eodStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  final auth = getIt<AuthService>();
  final branchId = auth.branchId;
  if (branchId == null || branchId.isEmpty) return null;
  if (auth.isLocalWorkspace) {
    final db = getIt<AppDatabase>();
    final today = DateTime.now();
    final summary = await db.getDailySalesSummary(branchId, today);
    final close = await db.getLatestLocalDailyClose(
      branchId: branchId,
      businessDate: summary['date']?.toString() ?? '',
    );
    var needsReconciliation = false;
    final closedAt = DateTime.tryParse(close?['closedAt']?.toString() ?? '');
    if (closedAt != null) {
      final start = DateTime(today.year, today.month, today.day);
      final end = start.add(const Duration(days: 1));
      needsReconciliation = await db.hasSalesActivityAfterClose(
            branchId: branchId,
            from: start,
            to: end,
            closedAt: closedAt,
          ) ||
          await db.hasLocalCashPayoutsAfterClose(
            branchId: branchId,
            from: start,
            to: end,
            closedAt: closedAt,
          ) ||
          _amountForDashboard(summary['cashCollections']) -
                  _amountForDashboard(close?['cashCollections']) >
              0.005 ||
          _amountForDashboard(summary['cashPayouts']) -
                  _amountForDashboard(close?['cashPayouts']) >
              0.005 ||
          _amountForDashboard(summary['cashRefunds']) -
                  _amountForDashboard(close?['cashRefunds']) >
              0.005 ||
          _amountForDashboard(summary['voidedCashReceived']) -
                  _amountForDashboard(close?['voidedCashReceived']) >
              0.005;
    }
    return {
      'localOnly': true,
      'close': close,
      'closeNeedsReconciliation': needsReconciliation,
    };
  }
  // Let the backend resolve "today" using the branch timezone so this card
  // agrees with End of Day when a device clock or timezone differs.
  return getIt<ApiClient>().getDailyClose(branchId);
});

double _amountForDashboard(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : 0.0;

/// Real AI-generated brief for the dashboard, replacing the previous
/// hardcoded template snippets. Null means "no live brief available" —
/// the UI falls back to the templated snippets rather than failing.
final _aiDailyBriefProvider = FutureProvider.autoDispose<String?>((ref) async {
  return AiChatService().fetchDailyBrief();
});

final _recentSalesProvider = StreamProvider<List<PendingSale>>((ref) {
  final db = getIt<AppDatabase>();
  return db.watchTodaysSales();
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  static final _currencyFmt = NumberFormat.currency(
    locale: 'en_KE',
    symbol: 'KES ',
    decimalDigits: 0,
  );
  static final _timeFmt = DateFormat('hh:mm a');
  static final _dateFmt = DateFormat('EEEE, d MMMM yyyy');

  Timer? _midnightTimer;
  // The calendar day the currently-shown "today" figures belong to. If the
  // clock rolls into a new day (either while the app is open, or between the
  // app being backgrounded and resumed), the dashboard must recompute
  // against the new day instead of keeping yesterday's totals on screen.
  late DateTime _shownDay;

  // Desktop Home only: which period is showing and when it was last read.
  HomeRange _homeRange = HomeRange.today;
  DateTime _updatedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _shownDay = _todayDate();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRollover();
    // After first frame, offer to close the day if it's past the branch's
    // configured closing time and today isn't closed yet (self-gates on
    // permission + hours + close status).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptEndOfDay());
  }

  void _maybePromptEndOfDay() {
    if (!mounted || getIt<AuthService>().isLocalWorkspace) return;
    EndOfDayPrompt.maybePrompt(context, ref.read(permissionsProvider));
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfDayChanged();
      _maybePromptEndOfDay();
    }
  }

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    // +2s cushion so we're firmly into the new day when it fires.
    final untilMidnight =
        nextMidnight.difference(now) + const Duration(seconds: 2);
    _midnightTimer = Timer(untilMidnight, () {
      if (!mounted) return;
      _rolloverToNewDay();
      _scheduleMidnightRollover();
    });
  }

  void _refreshIfDayChanged() {
    if (_todayDate() != _shownDay) {
      _rolloverToNewDay();
      // Re-arm the timer since the previous one was aligned to the old day.
      _scheduleMidnightRollover();
    }
  }

  /// The core of the fix: on a new day, rebuild the streams/futures so their
  /// "today" boundary is recomputed, and reset the day the AI brief and
  /// cost figures reflect. Without this the day-boundary captured when the
  /// streams were first created keeps yesterday's sales showing as "today".
  void _rolloverToNewDay() {
    _shownDay = _todayDate();
    ref.invalidate(_dashboardSummaryProvider);
    ref.invalidate(_recentSalesProvider);
    ref.invalidate(_todaysCostProvider);
    ref.invalidate(_aiDailyBriefProvider);
    ref.invalidate(_eodStatusProvider);
    if (mounted) setState(() {}); // refresh the header date too
  }

  Future<void> _refreshDashboard(WidgetRef ref) async {
    ref.invalidate(_dashboardSummaryProvider);
    ref.invalidate(_recentSalesProvider);
    ref.invalidate(_todaysCostProvider);
    ref.invalidate(_eodStatusProvider);
    ref.invalidate(_aiDailyBriefProvider);

    // Wait for the visible dashboard data to refresh so pull-to-refresh gives
    // useful feedback. Keep the gesture bounded if an optional network-backed
    // card (such as the AI brief) is slow or unavailable.
    final refreshes = <Future<void>>[
      ref.read(_dashboardSummaryProvider.future),
      ref.read(_recentSalesProvider.future),
      ref.read(_todaysCostProvider.future),
      ref.read(_eodStatusProvider.future),
      ref.read(_aiDailyBriefProvider.future),
    ].map((future) => future.then<void>((_) {}).catchError((_) {}));
    await Future.wait(
      refreshes,
    ).timeout(const Duration(seconds: 12), onTimeout: () => const <void>[]);
  }

  /// The time of today's first sale, as "7:42", or null before the first one.
  String? _firstSaleToday(List<PendingSale> sales) {
    final now = DateTime.now();
    DateTime? first;
    for (final sale in sales) {
      if (const {
        'VOIDED',
        'REFUNDED',
        'FAILED',
        'CANCELLED',
      }.contains(sale.status)) {
        continue;
      }
      final at = sale.createdAt.toLocal();
      if (at.year != now.year || at.month != now.month || at.day != now.day) {
        continue;
      }
      if (first == null || at.isBefore(first)) first = at;
    }
    return first == null ? null : DateFormat('H:mm').format(first);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = context.inDesktopShell;
    if (desktop) return _buildDesktop(context);
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final summaryAsync = ref.watch(_dashboardSummaryProvider);
    final salesAsync = ref.watch(_recentSalesProvider);
    final identity = ref.watch(tenantIdentityProvider);
    final businessLayout = ref.watch(businessLayoutProvider);
    final showDailyFigures = businessLayout.showsDashboardSection(
      'summary_metrics',
    );
    final showEndOfDay = businessLayout.showsDashboardSection('end_of_day');
    // The templated snapshot only repeats generic advice; in a device-only
    // shop the "up to date" card below takes its place.
    final showBusinessBrief =
        !isLocalWorkspace && businessLayout.showsDashboardSection('ai_brief');
    final showCostAndProfit = businessLayout.showsDashboardSection(
      'cost_profit',
    );
    final showRecentSales = businessLayout.showsDashboardSection(
      'recent_sales',
    );
    final needsSummary =
        showDailyFigures || showBusinessBrief || showCostAndProfit;
    final todaysSales = salesAsync.asData?.value ?? const <PendingSale>[];
    Widget takingsBlock(Map<String, dynamic> summary) {
      final split = splitTakings(
        todaysSales.map(
          (sale) => (
            method: sale.paymentMethod,
            reference: sale.paymentReference,
            total: sale.total,
            status: sale.status,
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeTakingsCard(
            revenue: _amountForDashboard(summary['totalRevenue']),
            transactions: (summary['transactionCount'] as num?)?.toInt() ?? 0,
            averageTicket: _amountForDashboard(summary['avgTicket']),
            itemsSold: _amountForDashboard(summary['itemsSold']),
            split: split,
            dateLabel: DateFormat('EEE d MMM').format(DateTime.now()),
            sellingSince: _firstSaleToday(todaysSales),
          ),
          const SizedBox(height: DesignSpacing.md),
          HomeStartSaleButton(onPressed: () => context.go('/')),
          if (split.recordedCount > 0) ...[
            const SizedBox(height: DesignSpacing.md),
            HomeRecordedReminder(
              count: split.recordedCount,
              onTap: () => context.push('/mpesa-match'),
            ),
          ],
        ],
      );
    }

    List<Widget> overviewCards(Map<String, dynamic> summary) {
      final cards = <Widget>[];
      void addCard(Widget card) => cards.add(card);

      if (showBusinessBrief) {
        addCard(_buildAiBrief(context, ref, summary));
      }
      if (showCostAndProfit) {
        addCard(_buildCostAndProfitCard(context, ref, summary));
      }
      return cards;
    }

    final overviewContent = summaryAsync.when<List<Widget>>(
      data: overviewCards,
      loading: () => needsSummary
          ? [
              if (!showDailyFigures)
                const Padding(
                  padding: EdgeInsets.all(DesignSpacing.md),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ]
          : const [],
      error: (error, _) => needsSummary
          ? [
              Padding(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                child: EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Couldn\'t load summary',
                  subtitle: loadErrorSubtitle(error),
                  iconColor: DesignColors.error,
                  actionLabel: isPermissionDenied(error) ? null : 'Retry',
                  onAction: isPermissionDenied(error)
                      ? null
                      : () => ref.invalidate(_dashboardSummaryProvider),
                ),
              ),
            ]
          : const [],
    );
    return Scaffold(
      appBar: desktop
          ? null
          : BrandedAppBar(
              title: identity.companyName.isNotEmpty
                  ? identity.companyName
                  : 'Home',
              showBackButton: false,
              showLogo: false,
              leading: Padding(
                padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
                child: TenantBrandMark(logoUrl: identity.logoUrl, size: 34),
              ),
              actions: [
                if (!getIt<AuthService>().isLocalWorkspace)
                  const NotificationBell(),
                IconButton(
                  tooltip: 'Browse a previous day',
                  icon: const Icon(Icons.calendar_month_rounded),
                  onPressed: () => _openDayPicker(context),
                ),
                // Refresh / share / log out live in one menu so the title keeps
                // its room on narrow phones and large font sizes.
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (value) {
                    switch (value) {
                      case 'refresh':
                        unawaited(_refreshDashboard(ref));
                      case 'share':
                        _shareDashboardReport(context, ref);
                      case 'logout':
                        _showDashboardLogoutDialog(context, ref);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.refresh_rounded),
                        title: Text('Refresh'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: ListTile(
                        leading: Icon(Icons.share_rounded),
                        title: Text('Share report'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.logout_rounded),
                        title: Text('Log out'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () => _refreshDashboard(ref),
        child: PageContainer(
          withScroll: true,
          maxWidth: desktop ? 1280 : 960,
          backgroundColor: desktop ? context.desktop.panel : null,
          padding: desktop ? const EdgeInsets.fromLTRB(24, 8, 24, 28) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desktop)
                DesktopPageHeader(
                  title: 'Dashboard',
                  subtitle: 'Today at your shop',
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () => _openDayPicker(context),
                      icon: const Icon(Icons.calendar_month_rounded, size: 17),
                      label: const Text('Choose day'),
                    ),
                    IconButton(
                      tooltip: 'Refresh dashboard',
                      onPressed: () => unawaited(_refreshDashboard(ref)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              Builder(
                builder: (context) {
                  final licence = ref.watch(licenceViewProvider).valueOrNull;
                  if (licence == null) return const SizedBox.shrink();
                  final standing = licence.standing;
                  final kind = switch (standing.status) {
                    LicenceStatus.salesPaused => LicenceStatusKind.paused,
                    LicenceStatus.grace => LicenceStatusKind.late,
                    LicenceStatus.trial when standing.daysLeft <= 3 =>
                      LicenceStatusKind.trial,
                    LicenceStatus.active when standing.daysLeft <= 3 =>
                      LicenceStatusKind.due,
                    _ => null,
                  };
                  if (kind == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: DesignSpacing.lg),
                    child: HomeLicenceBanner(
                      status: kind,
                      daysLeft: standing.daysLeft,
                      onTap: () => context.push('/settings/plan'),
                    ),
                  );
                },
              ),

              if (showDailyFigures) ...[
                summaryAsync.when(
                  data: takingsBlock,
                  loading: () => takingsBlock(const {
                    'transactionCount': 0,
                    'totalRevenue': 0.0,
                    'avgTicket': 0.0,
                    'itemsSold': 0,
                  }),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: DesignSpacing.xl),
              ],

              // Anything in the shop that needs the owner's eye (or an all-clear).
              if (!isLocalWorkspace) const ShopAttentionCard(),

              // Staff invite nudge — persistent across sessions until
              // at least one staff invitation is accepted.
              if (!isLocalWorkspace) const StaffInviteNudge(),

              // The owner of a shop kept on this phone sees how far setup has
              // got until every step is done or put off.
              if (isLocalWorkspace &&
                  getIt<AuthService>().isLocalWorkspaceOwner)
                const SetupProgressCard(),

              // End of Day — admin-only. Previously this lived only inside
              // Finance › Cash Flow, several taps deep; admins asked for it
              // to be reachable straight from the dashboard too. Staff
              // never see this card at all (canCloseEndOfDay is itself
              // sales.close_end_of_day, but the dashboard entry point is
              // additionally gated on the Admin role so a store manager who
              // was individually granted the permission still doesn't see
              // it duplicated here — only Finance stays their route).
              if (ref.watch(permissionsProvider).isAdmin && showEndOfDay) ...[
                _buildEndOfDayCard(context, ref),
                const SizedBox(height: DesignSpacing.xl),
              ],

              ShopUpToDateCard(
                profileId: businessLayout.preset.id,
                profileName: businessLayout.preset.name,
                onOpen: (path) => context.go(path),
              ),
              const SizedBox(height: DesignSpacing.xl),

              if (overviewContent.isNotEmpty) ...[
                for (var index = 0;
                    index < overviewContent.length;
                    index++) ...[
                  if (index > 0) const SizedBox(height: DesignSpacing.md),
                  overviewContent[index],
                ],
              ],

              if (showRecentSales) ...[
                const SizedBox(height: DesignSpacing.sm),
                SectionHeader(
                  icon: Icons.receipt_long_rounded,
                  title: 'Recent Sales',
                  subtitle: 'Today\'s transactions',
                  trailing: Text(
                    'Last 10',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? DesignColors.darkTextTertiary
                              : DesignColors.textTertiary,
                        ),
                  ),
                ),
                salesAsync.when(
                  data: (sales) {
                    if (sales.isEmpty) {
                      return const EmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: 'No sales today yet',
                        subtitle: 'Start selling to see transactions here',
                      );
                    }
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final divider = isDark
                        ? DesignColors.darkBorder
                        : DesignColors.surfaceBorder;
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: divider),
                        borderRadius: BorderRadius.circular(
                          DesignSpacing.radiusXl,
                        ),
                      ),
                      child: Column(
                        children: sales.take(10).toList().asMap().entries.map((
                          entry,
                        ) {
                          final isLast = entry.key == sales.take(10).length - 1;
                          final sale = entry.value;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => context.push('/receipt/${sale.id}'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : Border(
                                          bottom: BorderSide(color: divider),
                                        ),
                                ),
                                child: Row(
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        final look = _saleLook(
                                          sale.paymentMethod,
                                        );
                                        return Container(
                                          width: 38,
                                          height: 38,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: look.color.withValues(
                                              alpha: 0.16,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            look.icon,
                                            size: 18,
                                            color: look.color,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: DesignSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sale.receiptNumber,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark
                                                      ? DesignColors
                                                          .darkTextPrimary
                                                      : DesignColors
                                                          .textPrimary,
                                                ),
                                          ),
                                          const SizedBox(
                                            height: DesignSpacing.xs - 1,
                                          ),
                                          Text(
                                            '${_timeFmt.format(sale.createdAt)}  ·  ${paymentMethodLabel(sale.paymentMethod)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: isDark
                                                      ? DesignColors
                                                          .darkTextTertiary
                                                      : DesignColors
                                                          .textTertiary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: DesignSpacing.md),
                                    // A fixed ceiling (not Flexible): two flexible
                                    // children split the row in half, which left the
                                    // amount floating mid-row on wide screens.
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 130,
                                      ),
                                      child: FittedBox(
                                        alignment: Alignment.centerRight,
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _currencyFmt.format(sale.total),
                                          style: DesignType.numeric(
                                            fontSize: 15,
                                            color: isDark
                                                ? DesignColors.darkTextPrimary
                                                : DesignColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(DesignSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(DesignSpacing.xl),
                    child: EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Couldn\'t load recent sales',
                      subtitle: loadErrorSubtitle(e),
                      iconColor: DesignColors.error,
                      actionLabel: isPermissionDenied(e) ? null : 'Retry',
                      onAction: isPermissionDenied(e)
                          ? null
                          : () => ref.invalidate(_recentSalesProvider),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: DesignSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  // ── Desktop shell ──────────────────────────────────────────────────
  //
  // Inside the desktop shell Home is a different layout over the same data:
  // the providers above feed DesktopHomeView, which only draws.

  static const _desktopGoPaths = {
    '/',
    '/receipts',
    '/products',
    '/customers',
    '/reports',
    '/cash-flow',
    '/payments',
  };

  Future<void> _openFromDesktop(String path) async {
    if (!mounted) return;
    if (_desktopGoPaths.contains(path)) {
      context.go(path);
      return;
    }
    await context.push<Object?>(path);
    if (mounted && path == '/cash-flow/end-of-day') {
      ref.invalidate(_eodStatusProvider);
    }
  }

  Future<void> _refreshDesktop() async {
    ref.invalidate(desktopHomeRangeProvider);
    ref.invalidate(desktopTopProductsProvider);
    ref.invalidate(alertsProvider);
    await _refreshDashboard(ref);
    if (mounted) setState(() => _updatedAt = DateTime.now());
  }

  /// The end-of-day row for Needs attention, or null when the close is done.
  HomeAttentionItem? _eodAttention(AsyncValue<Map<String, dynamic>?> async) {
    final isLocal = getIt<AuthService>().isLocalWorkspace;
    const open = HomeAttentionItem(
      id: 'end-of-day',
      level: HomeAttentionLevel.info,
      title: "Close today's till",
      detail: 'Review the sales and count the till when you finish selling.',
      path: '/cash-flow/end-of-day',
    );
    return async.when(
      loading: () => null,
      error: (_, __) => const HomeAttentionItem(
        id: 'end-of-day',
        level: HomeAttentionLevel.warning,
        title: 'End of day needs a look',
        detail: "Review today's sales and count the till.",
        path: '/cash-flow/end-of-day',
      ),
      data: (close) {
        if (isLocal) {
          if (close?['close'] == null) return open;
          if (close?['closeNeedsReconciliation'] == true) {
            return const HomeAttentionItem(
              id: 'end-of-day',
              level: HomeAttentionLevel.warning,
              title: 'Till changed after closing',
              detail: 'Review the day and count the till again.',
              path: '/cash-flow/end-of-day',
            );
          }
          return null;
        }
        return close == null ? open : null;
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final businessLayout = ref.watch(businessLayoutProvider);
    final permissions = ref.watch(permissionsProvider);
    final range = _homeRange;
    final showFigures = businessLayout.showsDashboardSection('summary_metrics');
    final showCost = businessLayout.showsDashboardSection('cost_profit');
    final showRecent = businessLayout.showsDashboardSection('recent_sales');
    final showEndOfDay = businessLayout.showsDashboardSection('end_of_day');
    final showBrief =
        !isLocalWorkspace && businessLayout.showsDashboardSection('ai_brief');

    ref.listen<AsyncValue<Map<String, dynamic>>>(_dashboardSummaryProvider, (
      previous,
      next,
    ) {
      if (next.hasValue && mounted) setState(() => _updatedAt = DateTime.now());
    });

    // Figures for the chosen period, in the shape the view draws.
    final DesktopHomeData base;
    if (range == HomeRange.today) {
      final summaryAsync = ref.watch(_dashboardSummaryProvider);
      final salesAsync = ref.watch(_recentSalesProvider);
      final sales = (salesAsync.asData?.value ?? const <PendingSale>[])
          .map(homeSaleRowFromSale)
          .toList(growable: false);
      final summary = summaryAsync.asData?.value;
      final costAsync = showCost ? ref.watch(_todaysCostProvider) : null;
      final top = ref
              .watch(
                desktopTopProductsProvider((days: 1, stamp: sales.length)),
              )
              .asData
              ?.value ??
          const <HomeProductRow>[];
      final waiting = (!summaryAsync.hasValue && !summaryAsync.hasError) ||
          (!salesAsync.hasValue && !salesAsync.hasError);
      base = DesktopHomeData(
        range: range,
        loading: waiting,
        error: !summaryAsync.hasValue && summaryAsync.hasError
            ? loadErrorSubtitle(summaryAsync.error)
            : null,
        revenue: _amountForDashboard(summary?['totalRevenue']),
        transactions: (summary?['transactionCount'] as num?)?.toInt() ?? 0,
        avgTicket: _amountForDashboard(summary?['avgTicket']),
        itemsSold: _amountForDashboard(summary?['itemsSold']),
        split: splitOfSales(sales),
        cost: costAsync == null
            ? null
            : (costAsync.asData?.value ?? (costAsync.hasError ? 0.0 : null)),
        costLoading: costAsync != null && costAsync.isLoading,
        canAdjustCost: permissions.canRecordRestock,
        bars: hourlyBarsFromSales(sales),
        sales: sales,
        salesCount: sales.length,
        topProducts: top,
      );
    } else {
      final rangeAsync = ref.watch(desktopHomeRangeProvider(range.days));
      final loaded = rangeAsync.asData?.value;
      base = DesktopHomeData(
        range: range,
        loading: !rangeAsync.hasValue && !rangeAsync.hasError,
        error: !rangeAsync.hasValue && rangeAsync.hasError
            ? loadErrorSubtitle(rangeAsync.error)
            : null,
        revenue: loaded?.revenue ?? 0,
        transactions: loaded?.transactions ?? 0,
        avgTicket: loaded?.avgTicket ?? 0,
        itemsSold: loaded?.itemsSold ?? 0,
        split: loaded?.split ?? const TakingsSplit(),
        bars: loaded?.bars ?? const [],
        sales: loaded?.sales ?? const [],
        salesCount: loaded?.salesCount ?? 0,
        topProducts: loaded?.topProducts ?? const [],
        deviceOnly: loaded?.deviceOnly ?? false,
      );
    }

    // Needs attention: only what the phone Home already raises.
    final attention = <HomeAttentionItem>[];
    var attentionLoaded = true;
    if (!isLocalWorkspace &&
        permissions.has('accountability.view') &&
        businessLayout.isActionVisible('/shop-alerts')) {
      final alerts = ref.watch(alertsProvider);
      attentionLoaded = alerts.loadedOnce;
      final open = alerts.page.openCount;
      final high = alerts.page.openHigh;
      if (alerts.loadedOnce && open > 0) {
        attention.add(
          HomeAttentionItem(
            id: 'alerts',
            level: high > 0
                ? HomeAttentionLevel.serious
                : HomeAttentionLevel.warning,
            title: high > 0
                ? '$high serious ${high == 1 ? 'alert' : 'alerts'} to check'
                : '$open ${open == 1 ? 'thing' : 'things'} to look at',
            detail:
                'Sales below cost, voids, stock written off, credit and more.',
            path: '/shop-alerts',
          ),
        );
      }
    }
    final recorded = base.split.recordedCount;
    if (recorded > 0) {
      attention.add(
        HomeAttentionItem(
          id: 'recorded',
          level: HomeAttentionLevel.warning,
          title: recorded == 1
              ? '1 recorded payment to match'
              : '$recorded recorded payments to match',
          detail: 'Check them against your M-Pesa or bank statement.',
          path: '/mpesa-match',
        ),
      );
    }
    final licence = ref.watch(licenceViewProvider).valueOrNull;
    if (licence != null) {
      final standing = licence.standing;
      final days =
          standing.daysLeft == 1 ? '1 day' : '${standing.daysLeft} days';
      final licenceItem = switch (standing.status) {
        LicenceStatus.salesPaused => const HomeAttentionItem(
            id: 'licence',
            level: HomeAttentionLevel.serious,
            title: 'New sales are paused',
            detail:
                'Your records are safe. Open Plan and licence to pay and unlock.',
            path: '/settings/plan',
          ),
        LicenceStatus.grace => HomeAttentionItem(
            id: 'licence',
            level: HomeAttentionLevel.warning,
            title: 'Your payment is late',
            detail: 'New sales pause in $days.',
            path: '/settings/plan',
          ),
        LicenceStatus.trial when standing.daysLeft <= 3 => HomeAttentionItem(
            id: 'licence',
            level: HomeAttentionLevel.warning,
            title: 'Your free trial ends in $days',
            detail: 'Open Plan and licence to keep selling.',
            path: '/settings/plan',
          ),
        LicenceStatus.active when standing.daysLeft <= 3 => HomeAttentionItem(
            id: 'licence',
            level: HomeAttentionLevel.info,
            title: 'Your payment is due in $days',
            path: '/settings/plan',
          ),
        _ => null,
      };
      if (licenceItem != null) attention.add(licenceItem);
    }
    if (permissions.isAdmin && showEndOfDay) {
      final item = _eodAttention(ref.watch(_eodStatusProvider));
      if (item != null) attention.add(item);
    }
    if (isLocalWorkspace && getIt<AuthService>().isLocalWorkspaceOwner) {
      final checklist = ref.watch(setupChecklistProvider).valueOrNull;
      final next = checklist?.next;
      if (checklist != null && next != null) {
        attention.add(
          HomeAttentionItem(
            id: 'setup',
            level: HomeAttentionLevel.info,
            title:
                'Finish setting up (${checklist.doneCount} of ${checklist.steps.length})',
            detail:
                'Next: ${next.title[0].toLowerCase()}${next.title.substring(1)}',
            path: '/setup',
          ),
        );
      }
    }

    // Lower-priority extras under the grid: the daily brief and the nudge to
    // invite staff. Both stay quiet when they have nothing to say.
    final briefAsync = showBrief ? ref.watch(_aiDailyBriefProvider) : null;
    final brief = briefAsync?.asData?.value?.trim();
    final footerChildren = <Widget>[
      if (brief != null && brief.isNotEmpty)
        DesktopPanel(
          title: 'Daily brief',
          subtitle: 'Written for you by the assistant',
          child: AppMarkdown(
            brief,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: context.desktop.textMuted,
                ),
          ),
        ),
      if (!isLocalWorkspace) const StaffInviteNudge(),
    ];

    final data = DesktopHomeData(
      range: base.range,
      loading: base.loading,
      error: base.error,
      revenue: base.revenue,
      transactions: base.transactions,
      avgTicket: base.avgTicket,
      itemsSold: base.itemsSold,
      split: base.split,
      cost: base.cost,
      costLoading: base.costLoading,
      canAdjustCost: base.canAdjustCost,
      bars: base.bars,
      sales: base.sales,
      salesCount: base.salesCount,
      topProducts: base.topProducts,
      attention: attention,
      attentionLoaded: attentionLoaded,
      showFigures: showFigures,
      showProfit: showCost,
      showRecentSales: showRecent,
      deviceOnly: base.deviceOnly,
    );

    return Scaffold(
      backgroundColor: context.desktop.panel,
      body: DesktopHomeView(
        data: data,
        updatedAt: _updatedAt,
        onRangeChanged: (next) => setState(() => _homeRange = next),
        onRefresh: () => unawaited(_refreshDesktop()),
        onOpen: (path) => unawaited(_openFromDesktop(path)),
        onAdjustProfit: () => unawaited(
          _openProfitAdjustment(context, ref, data.revenue, data.cost ?? 0),
        ),
        onRetry: () {
          ref.invalidate(_dashboardSummaryProvider);
          ref.invalidate(desktopHomeRangeProvider);
        },
        footer: footerChildren.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < footerChildren.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    footerChildren[i],
                  ],
                ],
              ),
      ),
    );
  }

  /// Icon and colour for a sale's money group, matching the Sold today card.
  ({IconData icon, Color color}) _saleLook(String method) {
    switch (method.toUpperCase()) {
      case 'CASH':
        return (icon: Icons.payments_outlined, color: kCashColor);
      case 'MPESA_RECORDED':
        return (icon: Icons.smartphone_rounded, color: kRecordedColor);
      case 'BANK_RECORDED':
        return (icon: Icons.account_balance_rounded, color: kRecordedColor);
      case 'CREDIT':
        return (icon: Icons.person_outline_rounded, color: kCreditColor);
      default:
        return (icon: Icons.receipt_long_rounded, color: kOtherColor);
    }
  }

  List<String> _fallbackBriefSnippets(Map<String, dynamic> summary) {
    final revenue = (summary['totalRevenue'] as num?)?.toDouble() ?? 0;
    final transactions = (summary['transactionCount'] as num?)?.toInt() ?? 0;
    final avgTicket = (summary['avgTicket'] as num?)?.toDouble() ?? 0;
    final itemsSold = (summary['itemsSold'] as num?)?.toDouble() ?? 0;

    return <String>[
      transactions == 0
          ? 'No sales have landed today yet. Start with fast-moving items and watch stock before checkout.'
          : '$transactions transactions have brought in ${_currencyFmt.format(revenue)} today.',
      avgTicket > 0
          ? 'Average ticket is ${_currencyFmt.format(avgTicket)} across ${countLabel(itemsSold, 'item')} sold.'
          : 'Average ticket will appear once the first sale is completed.',
      itemsSold > 0
          ? 'Keep an eye on inventory after each sale so zero-stock items stay blocked from POS.'
          : 'Inventory and POS are linked, so received stock becomes sellable immediately.',
    ];
  }

  Widget _buildAiBrief(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> summary,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final briefAsync = ref.watch(_aiDailyBriefProvider);

    final cardBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return BorderDraw(
      radius: 18,
      color: DesignColors.accent.withValues(alpha: 0.55),
      delay: const Duration(milliseconds: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(DesignSpacing.lg),
              decoration: BoxDecoration(
                color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AxonAiIcon(
                        tenantLogoUrl:
                            ref.watch(tenantIdentityProvider).logoUrl,
                        size: 18,
                      ),
                      const SizedBox(width: DesignSpacing.sm),
                      Text(
                        isLocalWorkspace ? 'BUSINESS SNAPSHOT' : 'AI BRIEF',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: isDark
                                  ? DesignColors.darkTextTertiary
                                  : DesignColors.textTertiary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  briefAsync.when(
                    data: (brief) {
                      // A real AI-generated brief was returned — show it as-is
                      // instead of the templated fallback snippets.
                      if (brief != null && brief.trim().isNotEmpty) {
                        // Real markdown rendering (bold, tables, lists) — the AI's
                        // reply can include a markdown table of restock priorities,
                        // which a plain Text widget would show as literal
                        // "**bold**" and "| pipe | text |" instead of formatting.
                        return AppMarkdown(
                          brief.trim(),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.45,
                                    color: isDark
                                        ? DesignColors.darkTextSecondary
                                        : DesignColors.textSecondary,
                                  ),
                        );
                      }
                      return _buildBriefSnippets(
                        _fallbackBriefSnippets(summary),
                        isDark,
                      );
                    },
                    loading: () => Row(
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: isDark
                                ? DesignColors.darkTextTertiary
                                : DesignColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.sm),
                        Text(
                          'Thinking about today\'s numbers...',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: isDark
                                        ? DesignColors.darkTextTertiary
                                        : DesignColors.textTertiary,
                                  ),
                        ),
                      ],
                    ),
                    // Offline / AI unreachable — degrade to the templated snippets
                    // instead of showing an error where a business insight was
                    // expected.
                    error: (_, __) => _buildBriefSnippets(
                      _fallbackBriefSnippets(summary),
                      isDark,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: DesignColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefSnippets(List<String> snippets, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: snippets
          .map(
            (snippet) => Padding(
              padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
              child: Text(
                snippet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildEndOfDayCard(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final closeAsync = ref.watch(_eodStatusProvider);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        onTap: () async {
          await context.push('/cash-flow/end-of-day');
          if (context.mounted) ref.invalidate(_eodStatusProvider);
        },
        child: Container(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: border),
          ),
          child: closeAsync.when(
            loading: () => Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  child: Text(
                    'Checking today\'s close status…',
                    style: TextStyle(color: secondaryColor),
                  ),
                ),
              ],
            ),
            error: (_, __) => _buildEodCardContent(
              title: 'End of Day',
              subtitle: 'Review today\'s sales and count the till',
              status: 'Review',
              statusColor: DesignColors.warning,
              titleColor: titleColor,
              secondaryColor: secondaryColor,
            ),
            data: (close) {
              if (isLocalWorkspace) {
                if (close?['close'] == null) {
                  return _buildEodCardContent(
                    title: 'End of Day',
                    subtitle: 'Review today\'s sales and count the till',
                    status: 'Open',
                    statusColor: DesignColors.accent,
                    titleColor: titleColor,
                    secondaryColor: secondaryColor,
                  );
                }
                if (close?['closeNeedsReconciliation'] == true) {
                  return _buildEodCardContent(
                    title: 'End of Day',
                    subtitle:
                        'Till activity changed after closing — review and count again',
                    status: 'Review',
                    statusColor: DesignColors.warning,
                    titleColor: titleColor,
                    secondaryColor: secondaryColor,
                  );
                }
              }
              if (close == null) {
                return _buildEodCardContent(
                  title: 'End of Day',
                  subtitle: 'Today is open — review sales and count the till',
                  status: 'Open',
                  statusColor: DesignColors.accent,
                  titleColor: titleColor,
                  secondaryColor: secondaryColor,
                );
              }
              return _buildEodCardContent(
                title: 'End of Day',
                subtitle: 'Today\'s close is complete — view the summary',
                status: 'Closed',
                statusColor: DesignColors.success,
                titleColor: titleColor,
                secondaryColor: secondaryColor,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEodCardContent({
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required Color titleColor,
    required Color secondaryColor,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            border: Border.all(color: statusColor.withValues(alpha: 0.25)),
          ),
          child: Icon(
            status == 'Closed'
                ? Icons.lock_rounded
                : Icons.event_available_rounded,
            color: statusColor,
            size: 22,
          ),
        ),
        const SizedBox(width: DesignSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                subtitle,
                style: TextStyle(color: secondaryColor, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: DesignSpacing.sm),
        StatusBadge(label: status, color: statusColor),
        const SizedBox(width: DesignSpacing.xs),
        Icon(Icons.chevron_right_rounded, color: secondaryColor, size: 20),
      ],
    );
  }

  Widget _buildCostAndProfitCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> summary,
  ) {
    final revenue = (summary['totalRevenue'] as num?)?.toDouble() ?? 0;
    final costAsync = ref.watch(_todaysCostProvider);

    return costAsync.when(
      data: (cost) => _costCard(context, ref, revenue, cost),
      loading: () => _costCard(context, ref, revenue, 0, isLoading: true),
      error: (e, _) => _costCard(context, ref, revenue, 0),
    );
  }

  Widget _costCard(
    BuildContext context,
    WidgetRef ref,
    double revenue,
    double cost, {
    bool isLoading = false,
  }) {
    final profit = revenue - cost;
    final canAdjustCost = ref.watch(permissionsProvider).canRecordRestock;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            decoration: BoxDecoration(
              color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "TODAY'S COST & PROFIT",
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: isDark
                                ? DesignColors.darkTextTertiary
                                : DesignColors.textTertiary,
                          ),
                    ),
                    const Spacer(),
                    // Material+InkWell: real pressed/ripple state on the
                    // ADJUST control, with a >=44px hit target (the bare
                    // InkWell around a 14px icon row was far below it).
                    // Ink paints on this transparent Material, not the card.
                    if (canAdjustCost)
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          DesignSpacing.radiusFull,
                        ),
                        child: InkWell(
                          onTap: isLoading
                              ? null
                              : () => _openProfitAdjustment(
                                    context,
                                    ref,
                                    revenue,
                                    cost,
                                  ),
                          borderRadius: BorderRadius.circular(
                            DesignSpacing.radiusFull,
                          ),
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: DesignSpacing.huge,
                              minHeight: DesignSpacing.huge,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignSpacing.sm + DesignSpacing.xs,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.tune_rounded,
                                  size: 14,
                                  color: DesignColors.accent,
                                ),
                                const SizedBox(width: DesignSpacing.xs),
                                Text(
                                  'ADJUST',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: DesignColors.accent,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: DesignSpacing.md + 2),
                Row(
                  children: [
                    Expanded(
                      child: _costMetric(
                        'Cost of Goods',
                        isLoading ? '—' : formatMoney(cost),
                        isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: _costMetric(
                        // With no cost entered, "profit" would just repeat
                        // revenue as if every sale were pure margin.
                        cost <= 0 && !isLoading
                            ? 'Profit (no cost yet)'
                            : 'Profit',
                        isLoading ? '—' : formatMoney(profit),
                        cost <= 0 && !isLoading
                            ? (isDark
                                ? DesignColors.darkTextSecondary
                                : DesignColors.textSecondary)
                            : DesignColors.success,
                      ),
                    ),
                  ],
                ),
                if (cost <= 0 && !isLoading) ...[
                  const SizedBox(height: DesignSpacing.sm),
                  Text(
                    'Tap Adjust to enter what your stock cost today.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? DesignColors.darkTextTertiary
                              : DesignColors.textTertiary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: DesignColors.success),
          ),
        ],
      ),
    );
  }

  Widget _costMetric(String label, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: isDark
                    ? DesignColors.darkTextTertiary
                    : DesignColors.textTertiary,
              ),
        ),
        const SizedBox(height: DesignSpacing.xs - 1),
        Text(value, style: DesignType.numeric(fontSize: 17, color: color)),
      ],
    );
  }

  Future<void> _openProfitAdjustment(
    BuildContext context,
    WidgetRef ref,
    double revenue,
    double cost,
  ) async {
    final saved = await context.push<bool>(
      '/dashboard/profit-adjustment',
      extra: {
        'date': DateTime.now(),
        'currentRevenue': revenue,
        'currentCost': cost,
      },
    );
    if (saved == true) {
      ref.invalidate(_todaysCostProvider);
    }
  }

  Future<void> _showDashboardLogoutDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out',
      message:
          'Are you sure you want to log out? Any unsynced data will remain saved locally.',
      confirmLabel: 'Log out',
      confirmColor: DesignColors.error,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(authControllerProvider.notifier).logout();
  }

  /// Calendar icon in the dashboard app bar: pick any past date and open
  /// that day's real backend-sourced sales + an AI brief for it. Restricted
  /// to today-or-earlier — there's nothing to browse in the future.
  Future<void> _openDayPicker(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _shownDay,
      firstDate: DateTime(now.year - 3),
      lastDate: _todayDate(),
      helpText: 'View a previous day',
    );
    if (picked == null || !context.mounted) return;
    context.push('/dashboard/day/${DateFormat('yyyy-MM-dd').format(picked)}');
  }

  Future<void> _shareDashboardReport(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Share Daily Report',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.plainText],
    );
    if (format == null || !context.mounted) return;

    final db = getIt<AppDatabase>();
    final summary = await db.getDashboardSummary();
    final identity = ref.read(tenantIdentityProvider);

    if (format == ShareFormat.plainText) {
      final report = '''
  Daily Summary
  ═════════════
${_dateFmt.format(DateTime.now())}

Revenue:     ${_currencyFmt.format(summary['totalRevenue'] ?? 0)}
Transactions: ${summary['transactionCount'] ?? 0}
Avg Ticket:  ${_currencyFmt.format(summary['avgTicket'] ?? 0)}
Items Sold:  ${summary['itemsSold'] ?? 0}

Sent from your POS workspace
''';
      await ExportDocumentService.sharePlainText(
        report,
        subject: 'Daily Sales Report',
      );
      return;
    }

    final logoBytes = await ExportDocumentService.fetchLogoBytes(
      identity.logoUrl,
      allowNetwork: !getIt<AuthService>().isLocalWorkspace,
    );
    final bytes = await ExportDocumentService.buildPdfReport(
      title: 'Daily Sales Report',
      companyName: identity.companyName,
      subtitle: _dateFmt.format(DateTime.now()),
      logoBytes: logoBytes,
      sections: [
        PdfReportSection(
          heading: 'Summary',
          headers: const ['Metric', 'Value'],
          rows: [
            ['Revenue', _currencyFmt.format(summary['totalRevenue'] ?? 0)],
            ['Transactions', '${summary['transactionCount'] ?? 0}'],
            ['Avg Ticket', _currencyFmt.format(summary['avgTicket'] ?? 0)],
            ['Items Sold', '${summary['itemsSold'] ?? 0}'],
          ],
        ),
      ],
    );
    await ExportDocumentService.sharePdf(bytes, 'daily_sales_report');
  }
}
