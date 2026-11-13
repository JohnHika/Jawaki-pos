import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/accountability_models.dart';

/// Which alerts the table shows.
enum DesktopAlertFilter { open, high, all }

/// How today's summary card is doing.
enum DesktopTodayState { none, loading, error, ready }

Color alertSeverityColor(AlertSeverity s) => switch (s) {
      AlertSeverity.high => DesignColors.error,
      AlertSeverity.medium => DesignColors.warning,
      AlertSeverity.low => DesignColors.info,
    };

String alertSeverityLabel(AlertSeverity s) => switch (s) {
      AlertSeverity.high => 'Serious',
      AlertSeverity.medium => 'Medium',
      AlertSeverity.low => 'Low',
    };

/// "BELOW_COST" becomes "Below cost".
String alertTypeLabel(String type) {
  if (type.isEmpty) return 'Alert';
  final words = type.toLowerCase().replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

/// Shop Alerts on a computer: a short summary of today, filter chips, a table
/// of alerts and, for the one picked, an inspector with a Mark seen button.
///
/// Plain data in, callbacks out; the routed page owns the providers.
class DesktopShopAlertsView extends StatelessWidget {
  const DesktopShopAlertsView({
    super.key,
    required this.title,
    required this.alerts,
    required this.openCount,
    required this.loadedOnce,
    required this.filter,
    required this.onFilter,
    required this.selectedId,
    required this.onSelect,
    required this.onSeen,
    required this.onSeenAll,
    required this.onRetry,
    this.error,
    this.onRules,
    this.todayState = DesktopTodayState.none,
    this.todayTitle,
    this.todayBody,
    this.onRefreshToday,
  });

  final String title;

  /// Every alert loaded, before the filter is applied.
  final List<ShopAlert> alerts;
  final int openCount;
  final bool loadedOnce;
  final String? error;
  final DesktopAlertFilter filter;
  final ValueChanged<DesktopAlertFilter> onFilter;
  final String? selectedId;
  final ValueChanged<ShopAlert?> onSelect;
  final ValueChanged<ShopAlert> onSeen;
  final VoidCallback onSeenAll;
  final VoidCallback onRetry;

  /// null hides the Rules button (the person may not manage rules).
  final VoidCallback? onRules;
  final DesktopTodayState todayState;
  final String? todayTitle;
  final String? todayBody;
  final VoidCallback? onRefreshToday;

  List<ShopAlert> get _visible => switch (filter) {
        DesktopAlertFilter.open =>
          alerts.where((a) => !a.acknowledged).toList(),
        DesktopAlertFilter.high =>
          alerts.where((a) => a.severity == AlertSeverity.high).toList(),
        DesktopAlertFilter.all => alerts,
      };

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final rows = _visible;
    final selected = alerts.where((a) => a.id == selectedId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: openCount > 0
              ? '$openCount ${openCount == 1 ? 'alert needs' : 'alerts need'} a look'
              : 'Nothing needs your attention',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            if (onRules != null)
              OutlinedButton.icon(
                style: desktopSecondaryButton(context),
                onPressed: onRules,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Rules'),
              ),
            if (openCount > 0)
              FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: onSeenAll,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Mark all seen'),
              ),
          ],
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: DesktopInspectorLayout(
            inspectorWidth: 380,
            onClose: () => onSelect(null),
            inspector: selected == null
                ? null
                : _AlertInspector(
                    alert: selected,
                    onClose: () => onSelect(null),
                    onSeen: () => onSeen(selected),
                  ),
            main: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (todayState != DesktopTodayState.none)
                  _TodayStrip(
                    state: todayState,
                    title: todayTitle,
                    body: todayBody,
                    onRefresh: onRefreshToday,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                  child: Row(
                    children: [
                      DesktopFilterChip(
                        label: 'New',
                        count: openCount,
                        selected: filter == DesktopAlertFilter.open,
                        onTap: () => onFilter(DesktopAlertFilter.open),
                      ),
                      const SizedBox(width: 8),
                      DesktopFilterChip(
                        label: 'Serious',
                        selected: filter == DesktopAlertFilter.high,
                        onTap: () => onFilter(DesktopAlertFilter.high),
                      ),
                      const SizedBox(width: 8),
                      DesktopFilterChip(
                        label: 'All',
                        selected: filter == DesktopAlertFilter.all,
                        onTap: () => onFilter(DesktopAlertFilter.all),
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: DesignColors.warning
                          .withValues(alpha: p.dark ? 0.16 : 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          style: desktopLinkButton(context),
                          onPressed: onRetry,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: DesktopDataTable<ShopAlert>(
                    rows: rows,
                    rowId: (a) => a.id,
                    selectedId: selectedId,
                    onRowSelected: onSelect,
                    loading: !loadedOnce && alerts.isEmpty,
                    minWidth: 560,
                    columns: [
                      DesktopColumn<ShopAlert>(
                        label: 'Level',
                        width: 96,
                        sortBy: (a) => a.severity.index,
                        cell: (_, a) => Align(
                          alignment: Alignment.centerLeft,
                          child: DesktopStatusChip(
                            label: alertSeverityLabel(a.severity),
                            color: alertSeverityColor(a.severity),
                          ),
                        ),
                      ),
                      DesktopColumn<ShopAlert>(
                        label: 'Alert',
                        flex: 4,
                        minWidth: 200,
                        sortBy: (a) => a.title.toLowerCase(),
                        cell: (_, a) => DesktopCellText(a.title,
                            strong: !a.acknowledged),
                      ),
                      DesktopColumn<ShopAlert>(
                        label: 'Who',
                        flex: 2,
                        minWidth: 90,
                        sortBy: (a) => (a.actorName ?? '').toLowerCase(),
                        cell: (_, a) => DesktopCellText(
                          a.actorName ?? '',
                          muted: true,
                        ),
                      ),
                      DesktopColumn<ShopAlert>(
                        label: 'When',
                        width: 110,
                        sortBy: (a) => a.createdAt.millisecondsSinceEpoch,
                        cell: (_, a) =>
                            DesktopCellText(timeAgo(a.createdAt), muted: true),
                      ),
                    ],
                    initialSortColumn: 3,
                    initialSortAscending: false,
                    empty: DesktopEmptyState(
                      icon: Icons.verified_user_outlined,
                      title: filter == DesktopAlertFilter.open
                          ? 'Nothing needs your attention'
                          : 'No alerts here',
                      message:
                          'Sales below cost, voids, stock written off, credit over the limit and a short till will show up here.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({
    required this.state,
    required this.title,
    required this.body,
    required this.onRefresh,
  });

  final DesktopTodayState state;
  final String? title;
  final String? body;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final text = switch (state) {
      DesktopTodayState.loading => 'Getting today’s summary',
      DesktopTodayState.error => 'Today’s summary isn’t available right now.',
      _ => body ?? '',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.today_rounded, size: 18, color: p.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state == DesktopTodayState.ready ? (title ?? 'Today') : 'Today',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Refresh summary',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class _AlertInspector extends StatelessWidget {
  const _AlertInspector({
    required this.alert,
    required this.onClose,
    required this.onSeen,
  });

  final ShopAlert alert;
  final VoidCallback onClose;
  final VoidCallback onSeen;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
    return DesktopInspector(
      title: alert.title,
      subtitle: timeAgo(alert.createdAt),
      onClose: onClose,
      footer: alert.acknowledged
          ? Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: p.textMuted),
                const SizedBox(width: 8),
                Text(
                  'You have seen this',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          : FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: onSeen,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Mark seen'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopStatusChip(
            label: alertSeverityLabel(alert.severity),
            color: alertSeverityColor(alert.severity),
          ),
          const SizedBox(height: 16),
          if (alert.body.isNotEmpty) row('What happened', alert.body),
          row('Kind', alertTypeLabel(alert.type)),
          if ((alert.actorName ?? '').isNotEmpty)
            row('Who did it', alert.actorName!),
        ],
      ),
    );
  }
}
