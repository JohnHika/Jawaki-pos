import 'package:flutter/material.dart';

import '../desktop/desktop_layout.dart';
import '../responsive/device_class.dart';
import '../theme/design_system.dart';

/// A list on the left and the picked item on the right, for tablets, till
/// terminals and unfolded fold phones. On a phone (and on the computer shell,
/// which has its own list-detail views) only the list is drawn and the caller
/// keeps opening the item as a page.
///
/// ```dart
/// MasterDetail(
///   masterBuilder: (context, twoPane) => ListView(... onTap: twoPane
///       ? () => setState(() => _selected = id)
///       : () => context.push('/things/$id')),
///   detail: _selected == null ? null : ThingView(embedded: true),
///   emptyIcon: Icons.people_outline_rounded,
///   emptyTitle: 'Pick a customer',
/// )
/// ```
///
/// The split is measured on the page itself ([Breakpoints.twoColumn]), so a
/// page that sits beside a rail still falls back to one column when it is too
/// narrow, and a fold phone that is opened up gets two columns while the same
/// phone folded keeps one.
class MasterDetail extends StatelessWidget {
  const MasterDetail({
    super.key,
    required this.masterBuilder,
    required this.detail,
    this.masterWidth = 380,
    this.emptyIcon = Icons.touch_app_rounded,
    this.emptyTitle = 'Pick one from the list',
    this.emptyBody,
  });

  /// Draws the list. [twoPane] says whether a detail pane is showing beside it,
  /// so a tap should select instead of opening a new page.
  final Widget Function(BuildContext context, bool twoPane) masterBuilder;

  /// The picked item, or null to show the empty prompt.
  final Widget? detail;

  /// Width of the list column; the detail takes the rest.
  final double masterWidth;

  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyBody;

  /// Whether a page of [width] should show two columns in this context.
  static bool wantsTwoPanes(BuildContext context, double width) {
    if (context.inDesktopShell) return false;
    if (context.isPhoneLayout) return false;
    return width >= Breakpoints.twoColumn;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = wantsTwoPanes(context, constraints.maxWidth);
        if (!twoPane) return masterBuilder(context, false);

        final border = context.themed(DesignColors.darkBorder);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: masterWidth.clamp(300, constraints.maxWidth * 0.5),
              child: masterBuilder(context, true),
            ),
            VerticalDivider(width: 1, thickness: 1, color: border),
            Expanded(
              child: detail ??
                  _EmptyDetail(
                    icon: emptyIcon,
                    title: emptyTitle,
                    body: emptyBody,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48, color: context.themed(DesignColors.darkTextTertiary)),
            const SizedBox(height: DesignSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: context.themed(DesignColors.darkTextPrimary),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: DesignSpacing.xs),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.themed(DesignColors.darkTextSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
