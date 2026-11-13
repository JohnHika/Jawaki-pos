import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// The pages that make up Reports on the computer. The first seven are tabs of
/// the Reports page; Analytics and Forecast are their own routes but sit in
/// the same strip so the owner never has to go back to find another report.
enum DesktopReportKind {
  sales('Sales'),
  payments('Payments'),
  cashiers('Cashiers'),
  categories('Categories'),
  products('Top products'),
  stock('Stock'),
  customers('Customers'),
  analytics('Analytics'),
  forecast('Forecast');

  const DesktopReportKind(this.label);

  final String label;

  /// Reports that live on their own route.
  String? get route => switch (this) {
        analytics => '/reports/analytics',
        forecast => '/reports/inventory-forecast',
        _ => null,
      };

  /// The ones the licence puts behind Analytics (the phone gates them too).
  bool get needsAnalyticsLicence => switch (this) {
        payments || cashiers || categories || products || analytics => true,
        _ => false,
      };

  /// Reports that depend on the date range in the toolbar.
  bool get usesDateRange => switch (this) {
        sales || payments || cashiers || categories || products => true,
        _ => false,
      };
}

/// Hands the tab the owner picked on Analytics or Forecast to the Reports
/// page, which reads it once when it opens.
class DesktopReportsHandoff {
  const DesktopReportsHandoff._();

  static DesktopReportKind? pending;

  static DesktopReportKind take() {
    final kind = pending ?? DesktopReportKind.sales;
    pending = null;
    return kind;
  }
}

/// The report picker: a tab strip with a hairline under it. The selected tab
/// gets the accent underline; the rest stay quiet.
class DesktopReportTabs extends StatelessWidget {
  const DesktopReportTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final DesktopReportKind selected;
  final ValueChanged<DesktopReportKind> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final kind in DesktopReportKind.values) ...[
              if (kind == DesktopReportKind.analytics)
                _Divider(color: p.border),
              _Tab(
                kind: kind,
                selected: kind == selected,
                palette: p,
                onTap: () => onSelect(kind),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: 18,
          child: VerticalDivider(width: 1, thickness: 1, color: color),
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.kind,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final DesktopReportKind kind;
  final bool selected;
  final DesktopPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: p.hover,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? (p.dark ? const Color(0xFFFF7A33) : p.accent)
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            kind.label,
            maxLines: 1,
            style: GoogleFonts.plusJakartaSans(
              color: selected ? p.text : p.textMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves from one report page to another (used by Analytics and Forecast,
/// which are routes of their own). The seven plain reports live on /reports;
/// the chosen tab is handed over so it opens on the right one.
void openDesktopReport(BuildContext context, DesktopReportKind to) {
  final route = to.route;
  if (route != null) {
    context.go(route);
    return;
  }
  DesktopReportsHandoff.pending = to;
  context.go('/reports');
}
