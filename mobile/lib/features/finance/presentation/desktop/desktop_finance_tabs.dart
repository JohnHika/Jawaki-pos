import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// The three money pages that share one tab strip on a computer.
enum FinanceSection {
  overview('Overview', '/finance'),
  expenses('Expenses', '/expenses'),
  cashFlow('Cash flow', '/cash-flow');

  const FinanceSection(this.label, this.path);

  final String label;
  final String path;
}

/// Overview | Expenses | Cash flow, drawn under the page title. Each tab is
/// its own route, so the tabs go to the page and the back button still works.
/// A tab the signed-in role cannot open is left out, and a single tab is not
/// worth showing.
class DesktopFinanceTabs extends StatelessWidget {
  const DesktopFinanceTabs({
    super.key,
    required this.current,
    required this.available,
    this.onSelect,
  });

  final FinanceSection current;
  final Set<FinanceSection> available;

  /// Defaults to `context.go(section.path)`.
  final ValueChanged<FinanceSection>? onSelect;

  /// The tabs to show for a role.
  static Set<FinanceSection> forRole({
    required bool canViewFinance,
    required bool canViewCashFlow,
  }) =>
      {
        if (canViewFinance) FinanceSection.overview,
        if (canViewFinance) FinanceSection.expenses,
        if (canViewCashFlow) FinanceSection.cashFlow,
      };

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final tabs = [
      for (final s in FinanceSection.values)
        if (available.contains(s) || s == current) s,
    ];
    if (tabs.length < 2) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          for (final s in tabs)
            _Tab(
              label: s.label,
              selected: s == current,
              onTap: s == current
                  ? null
                  : () => onSelect != null
                      ? onSelect!(s)
                      : context.go(s.path),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return InkWell(
      onTap: onTap,
      hoverColor: p.hover,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? p.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: selected ? p.text : p.textMuted,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
