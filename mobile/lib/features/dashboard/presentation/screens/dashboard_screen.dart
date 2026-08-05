import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:gpt_markdown_lite/gpt_markdown_lite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/theme/share_format_sheet.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../ai/presentation/screens/ai_chat_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../finance/presentation/end_of_day_prompt.dart';
import '../widgets/staff_invite_nudge.dart';

final _dashboardSummaryProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) async* {
  final db = getIt<AppDatabase>();
  await for (final _ in db.watchTodaysSales()) {
    yield await db.getDashboardSummary();
  }
});

final _todaysCostProvider = FutureProvider.autoDispose<double>((ref) async {
  final branchId = getIt<AuthService>().branchId;
  if (branchId == null) return 0.0;
  return getIt<AppDatabase>().getTodaysTotalPurchases(branchId);
});

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
    if (!mounted) return;
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
    if (mounted) setState(() {}); // refresh the header date too
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(_dashboardSummaryProvider);
    final salesAsync = ref.watch(_recentSalesProvider);
    final identity = ref.watch(tenantIdentityProvider);
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Dashboard',
        showBackButton: false,
        showLogo: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
          child: TenantBrandMark(logoUrl: identity.logoUrl, size: 34),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(_dashboardSummaryProvider);
              ref.invalidate(_recentSalesProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareDashboardReport(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_dashboardSummaryProvider);
          ref.invalidate(_recentSalesProvider);
        },
        child: PageContainer(
          withScroll: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting header
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.userFirstName.isNotEmpty
                          ? 'Good ${_getGreeting()}, ${identity.userFirstName}'
                          : 'Good ${_getGreeting()}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      identity.companyName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DesignColors.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dateFmt.format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? DesignColors.darkTextSecondary
                            : DesignColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Staff invite nudge — persistent across sessions until
              // at least one staff invitation is accepted.
              const StaffInviteNudge(),

              // Summary Cards - Using Wrap+LayoutBuilder to prevent overflow in Column
              summaryAsync.when(
                data: (summary) => Column(
                  children: [
                    _buildSummaryGrid(context, summary),
                    const SizedBox(height: 12),
                    _buildAiBrief(context, ref, summary),
                    const SizedBox(height: 12),
                    _buildCostAndProfitCard(context, ref, summary),
                  ],
                ),
                loading: () => _buildSummaryGrid(context, {
                  'transactionCount': 0,
                  'totalRevenue': 0.0,
                  'avgTicket': 0.0,
                  'itemsSold': 0,
                }),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load summary',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(_dashboardSummaryProvider),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Recent Sales Section
              SectionHeader(
                icon: Icons.receipt_long_rounded,
                title: 'Recent Sales',
                subtitle: 'Today\'s transactions',
                trailing: Text(
                  'Last 10',
                  style: TextStyle(
                    fontSize: 12,
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children:
                          sales.take(10).toList().asMap().entries.map((entry) {
                        final isLast = entry.key == sales.take(10).length - 1;
                        final sale = entry.value;
                        return InkWell(
                          onTap: () => context.push('/receipt/${sale.id}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : Border(bottom: BorderSide(color: divider)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: DesignColors.accent
                                        .withValues(alpha: 0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_rounded,
                                    size: 18,
                                    color: DesignColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sale.receiptNumber,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: isDark
                                              ? DesignColors.darkTextPrimary
                                              : DesignColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${sale.paymentMethod.toUpperCase()}  ·  ${_timeFmt.format(sale.createdAt)}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark
                                              ? DesignColors.darkTextTertiary
                                              : DesignColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
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
                        );
                      }).toList(),
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load recent sales',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(_recentSalesProvider),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(BuildContext context, Map<String, dynamic> summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate card width to fit 2 per row with proper spacing
        final cardWidth = (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Today's Revenue
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: "Today's Revenue",
                value: _currencyFmt.format(summary['totalRevenue'] ?? 0),
                icon: Icons.trending_up_rounded,
                color: DesignColors.success,
              ),
            ),
            // Transactions
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Transactions',
                value: '${summary['transactionCount'] ?? 0}',
                icon: Icons.receipt_long_rounded,
                color: DesignColors.brand,
              ),
            ),
            // Avg. Ticket
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Avg. Ticket',
                value: _currencyFmt.format(summary['avgTicket'] ?? 0),
                icon: Icons.shopping_cart_rounded,
                color: DesignColors.info,
              ),
            ),
            // Items Sold
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Items Sold',
                value: '${summary['itemsSold'] ?? 0}',
                icon: Icons.inventory_2_rounded,
                color: DesignColors.accent,
              ),
            ),
          ],
        );
      },
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  List<String> _fallbackBriefSnippets(Map<String, dynamic> summary) {
    final revenue = (summary['totalRevenue'] as num?)?.toDouble() ?? 0;
    final transactions = (summary['transactionCount'] as num?)?.toInt() ?? 0;
    final avgTicket = (summary['avgTicket'] as num?)?.toDouble() ?? 0;
    final itemsSold = (summary['itemsSold'] as num?)?.toInt() ?? 0;

    return <String>[
      transactions == 0
          ? 'No sales have landed today yet. Start with fast-moving items and watch stock before checkout.'
          : '$transactions transactions have brought in ${_currencyFmt.format(revenue)} today.',
      avgTicket > 0
          ? 'Average ticket is ${_currencyFmt.format(avgTicket)} across $itemsSold sold items.'
          : 'Average ticket will appear once the first sale is completed.',
      itemsSold > 0
          ? 'Keep an eye on inventory after each sale so zero-stock items stay blocked from POS.'
          : 'Inventory and POS are linked, so received stock becomes sellable immediately.',
    ];
  }

  Widget _buildAiBrief(
      BuildContext context, WidgetRef ref, Map<String, dynamic> summary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final briefAsync = ref.watch(_aiDailyBriefProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(
          left: const BorderSide(color: DesignColors.accent, width: 3),
          top: BorderSide(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder),
          right: BorderSide(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder),
          bottom: BorderSide(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AxonAiIcon(
                tenantLogoUrl: ref.watch(tenantIdentityProvider).logoUrl,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'AI BRIEF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          briefAsync.when(
            data: (brief) {
              // A real AI-generated brief was returned — show it as-is
              // instead of the templated fallback snippets.
              if (brief != null && brief.trim().isNotEmpty) {
                // Real markdown rendering (bold, tables, lists) — the AI's
                // reply can include a markdown table of restock priorities,
                // which a plain Text widget would show as literal
                // "**bold**" and "| pipe | text |" instead of formatting.
                return GptMarkdown(
                  brief.trim(),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                );
              }
              return _buildBriefSnippets(
                  _fallbackBriefSnippets(summary), isDark);
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
                const SizedBox(width: 8),
                Text(
                  'Thinking about today\'s numbers...',
                  style: TextStyle(
                    fontSize: 13,
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
            error: (_, __) =>
                _buildBriefSnippets(_fallbackBriefSnippets(summary), isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildBriefSnippets(List<String> snippets, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: snippets
          .map(
            (snippet) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                snippet,
                style: TextStyle(
                  fontSize: 13.5,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(
          left: const BorderSide(color: DesignColors.success, width: 3),
          top: BorderSide(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder),
          right: BorderSide(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder),
          bottom: BorderSide(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "TODAY'S COST & PROFIT",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: isLoading
                    ? null
                    : () => _openProfitAdjustment(context, ref, revenue, cost),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 14, color: DesignColors.accent),
                    SizedBox(width: 4),
                    Text('ADJUST',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: DesignColors.accent,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _costMetric(
                  'Cost of Goods',
                  isLoading ? '—' : 'KES ${cost.toStringAsFixed(0)}',
                  isDark
                      ? DesignColors.darkTextPrimary
                      : DesignColors.textPrimary,
                ),
              ),
              Expanded(
                child: _costMetric(
                  'Profit',
                  isLoading ? '—' : 'KES ${profit.toStringAsFixed(0)}',
                  DesignColors.success,
                ),
              ),
            ],
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
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: isDark
                ? DesignColors.darkTextTertiary
                : DesignColors.textTertiary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: DesignType.numeric(fontSize: 17, color: color),
        ),
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
      await ExportDocumentService.sharePlainText(report,
          subject: 'Daily Sales Report');
      return;
    }

    final logoBytes =
        await ExportDocumentService.fetchLogoBytes(identity.logoUrl);
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
