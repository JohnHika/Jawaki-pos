import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../dashboard/presentation/desktop/desktop_bar_chart.dart';

/// One payment method in the period.
class DesktopPayMethod {
  const DesktopPayMethod({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final double total;
  final Color color;
}

/// One busy hour of the day.
class DesktopPayHour {
  const DesktopPayHour({
    required this.hour,
    required this.count,
    required this.total,
  });

  /// 0-23.
  final int hour;
  final int count;
  final double total;

  String get label {
    final period = hour >= 12 ? 'PM' : 'AM';
    final shown = hour % 12 == 0 ? 12 : hour % 12;
    return '$shown:00 $period';
  }
}

/// Payment analytics on a computer: period chips, a strip of figures, the
/// trend as a flat bar chart, and a table each for methods and busy hours.
///
/// It only draws. The routed screen owns loading, the period and the refresh.
class DesktopPaymentAnalyticsView extends StatelessWidget {
  const DesktopPaymentAnalyticsView({
    super.key,
    required this.periods,
    required this.selectedPeriod,
    required this.onPeriod,
    required this.totalAmount,
    required this.transactionCount,
    required this.averagePayment,
    required this.methods,
    required this.trend,
    required this.peakHours,
    required this.onRefresh,
    this.loading = false,
    this.errorMessage,
    this.localNotice,
    this.trendTitle = 'Takings over time',
  });

  final List<String> periods;
  final int selectedPeriod;
  final ValueChanged<int> onPeriod;
  final double totalAmount;
  final int transactionCount;
  final double averagePayment;
  final List<DesktopPayMethod> methods;
  final List<DesktopChartBar> trend;
  final List<DesktopPayHour> peakHours;
  final VoidCallback onRefresh;
  final bool loading;
  final String? errorMessage;

  /// "Showing sales saved on this computer", when the figures are not from
  /// the cloud.
  final String? localNotice;
  final String trendTitle;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'Payment analytics',
          subtitle: 'How customers paid, and when',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Expanded(child: _body(context, p)),
      ],
    );
  }

  Widget _body(BuildContext context, DesktopPalette p) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load payment analytics",
        message: errorMessage,
        action: OutlinedButton.icon(
          style: desktopSecondaryButton(context),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
        ),
      );
    }
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: DesktopContent(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < periods.length; i++)
                      DesktopFilterChip(
                        label: periods[i],
                        selected: selectedPeriod == i,
                        onTap: () => onPeriod(i),
                      ),
                  ],
                ),
                if (localNotice != null) ...[
                  const SizedBox(width: 16),
                  Expanded(child: _notice(context, localNotice!)),
                ],
              ],
            ),
            const SizedBox(height: 14),
            DesktopMetricStrip(
              metrics: [
                DesktopMetric(
                  label: 'Total payments',
                  value: formatMoney(totalAmount),
                ),
                DesktopMetric(
                  label: 'Transactions',
                  value: '$transactionCount',
                ),
                DesktopMetric(
                  label: 'Average payment',
                  value: formatMoney(averagePayment),
                ),
                DesktopMetric(
                  label: 'Payment methods',
                  value: '${methods.length}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (transactionCount == 0)
              const DesktopPanel(
                child: SizedBox(
                  height: 220,
                  child: DesktopEmptyState(
                    icon: Icons.query_stats_rounded,
                    title: 'No transactions in this period',
                    message:
                        'Payment breakdowns, trends and busy hours will appear here once sales come in.',
                  ),
                ),
              )
            else ...[
              _twoColumn(
                left: DesktopPanel(
                  title: trendTitle,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DesktopBarChart(
                      bars: trend,
                      height: 200,
                      semanticLabel: trendTitle,
                    ),
                  ),
                ),
                right: _methodsPanel(context),
              ),
              const SizedBox(height: 16),
              _hoursPanel(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _twoColumn({required Widget left, required Widget right}) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 880) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 16), right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: left),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: right),
        ],
      );
    });
  }

  Widget _notice(BuildContext context, String text) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DesignColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.computer_rounded,
              size: 16, color: DesignColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodsPanel(BuildContext context) {
    final grand = methods.fold<double>(0, (a, m) => a + m.total);
    final columns = <DesktopColumn<DesktopPayMethod>>[
      DesktopColumn<DesktopPayMethod>(
        label: 'Method',
        flex: 3,
        minWidth: 100,
        sortBy: (m) => m.label,
        cell: (context, m) => Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: m.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: DesktopCellText(m.label, strong: true)),
          ],
        ),
      ),
      DesktopColumn<DesktopPayMethod>(
        label: 'Count',
        width: 64,
        numeric: true,
        sortBy: (m) => m.count,
        cell: (context, m) =>
            DesktopCellText('${m.count}', numeric: true, muted: true),
      ),
      DesktopColumn<DesktopPayMethod>(
        label: 'Share',
        width: 64,
        numeric: true,
        sortBy: (m) => m.total,
        cell: (context, m) => DesktopCellText(
          grand > 0 ? '${(m.total / grand * 100).round()}%' : '0%',
          numeric: true,
          muted: true,
        ),
      ),
      DesktopColumn<DesktopPayMethod>(
        label: 'Total',
        width: 112,
        numeric: true,
        sortBy: (m) => m.total,
        cell: (context, m) =>
            DesktopCellText(formatMoney(m.total), numeric: true, strong: true),
      ),
    ];
    return DesktopPanel(
      title: 'By payment method',
      padding: EdgeInsets.zero,
      clip: true,
      child: SizedBox(
        height: 252,
        child: DesktopDataTable<DesktopPayMethod>(
          columns: columns,
          rows: methods,
          rowId: (m) => m.label,
          minWidth: 0,
          initialSortColumn: 3,
          initialSortAscending: false,
          empty: const DesktopEmptyState(
            icon: Icons.payments_outlined,
            title: 'No payment data',
          ),
        ),
      ),
    );
  }

  Widget _hoursPanel(BuildContext context) {
    final traffic = peakHours.fold<int>(0, (a, h) => a + h.count);
    final columns = <DesktopColumn<DesktopPayHour>>[
      DesktopColumn<DesktopPayHour>(
        label: 'Hour',
        flex: 2,
        minWidth: 100,
        sortBy: (h) => h.hour,
        cell: (context, h) => DesktopCellText(h.label, strong: true),
      ),
      DesktopColumn<DesktopPayHour>(
        label: 'Transactions',
        width: 120,
        numeric: true,
        sortBy: (h) => h.count,
        cell: (context, h) => DesktopCellText('${h.count}', numeric: true),
      ),
      DesktopColumn<DesktopPayHour>(
        label: 'Share of traffic',
        width: 130,
        numeric: true,
        sortBy: (h) => h.count,
        cell: (context, h) => DesktopCellText(
          traffic > 0 ? '${(h.count / traffic * 100).toStringAsFixed(1)}%' : '0%',
          numeric: true,
          muted: true,
        ),
      ),
      DesktopColumn<DesktopPayHour>(
        label: 'Takings',
        width: 130,
        numeric: true,
        sortBy: (h) => h.total,
        cell: (context, h) =>
            DesktopCellText(formatMoney(h.total), numeric: true, strong: true),
      ),
    ];
    return DesktopPanel(
      title: 'Busy hours',
      subtitle: 'When customers pay',
      padding: EdgeInsets.zero,
      clip: true,
      child: SizedBox(
        height: 252,
        child: DesktopDataTable<DesktopPayHour>(
          columns: columns,
          rows: peakHours,
          rowId: (h) => h.hour,
          minWidth: 0,
          initialSortColumn: 1,
          initialSortAscending: false,
          empty: const DesktopEmptyState(
            icon: Icons.access_time_rounded,
            title: 'No busy-hours data',
          ),
        ),
      ),
    );
  }
}
