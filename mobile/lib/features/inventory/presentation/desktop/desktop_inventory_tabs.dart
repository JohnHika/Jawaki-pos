import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// One place in the Inventory area: a tab in the page header.
class DesktopInventoryTab {
  const DesktopInventoryTab({
    required this.label,
    required this.path,
    this.count,
  });

  final String label;

  /// The route the tab opens. null marks an in-page tab (see [selected]).
  final String? path;
  final int? count;
}

/// The strip of sub-areas under the Inventory page title: stock levels,
/// receive stock, requests, restock suggestions. Tabs that are routes use
/// [onOpen]; tabs inside the stock page use [onSelectInPage].
class DesktopInventoryTabs extends StatelessWidget {
  const DesktopInventoryTabs({
    super.key,
    required this.tabs,
    required this.selectedLabel,
    required this.onSelect,
  });

  final List<DesktopInventoryTab> tabs;
  final String selectedLabel;

  /// Called with the tab the person picked. The caller decides whether that is
  /// a route change or an in-page switch.
  final ValueChanged<DesktopInventoryTab> onSelect;

  /// The tabs this person may open, in the order of the work: look, receive,
  /// request, plan.
  static List<DesktopInventoryTab> forRole({
    required bool isLocalWorkspace,
    required bool canManageStock,
    required bool canRequestStock,
    bool canSeeRestock = true,
    int? lowCount,
  }) {
    return [
      DesktopInventoryTab(
        label: 'Stock levels',
        path: '/inventory',
        count: lowCount != null && lowCount > 0 ? lowCount : null,
      ),
      if (canManageStock)
        const DesktopInventoryTab(
          label: 'Receive stock',
          path: '/inventory/receive',
        ),
      if (!isLocalWorkspace && (canManageStock || canRequestStock))
        const DesktopInventoryTab(
          label: 'Stock requests',
          path: '/inventory/stock-requests',
        ),
      if (canSeeRestock)
        const DesktopInventoryTab(
          label: 'Restock suggestions',
          path: '/inventory/restock-suggestions',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in tabs)
            Builder(builder: (context) {
              final selected = tab.label == selectedLabel;
              return InkWell(
                onTap: () => onSelect(tab),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
                  margin: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected ? p.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tab.label,
                        style: GoogleFonts.plusJakartaSans(
                          color: selected ? p.text : p.textMuted,
                          fontSize: 13.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (tab.count != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${tab.count}',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
