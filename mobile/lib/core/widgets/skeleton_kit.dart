import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// Placeholder rows that match the real rows, so the page keeps its shape while
/// data loads instead of jumping from a spinner.
///
/// ```dart
/// if (loading) const SkeletonList(rows: 8, leading: false);
/// ```
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({
    super.key,
    this.leading = false,
    this.trailing = true,
    this.twoLines = true,
    this.height = 64,
  });

  /// A round placeholder before the text (an avatar or an icon tile).
  final bool leading;
  final bool trailing;
  final bool twoLines;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (leading) ...[
            const ShimmerWidget(width: 40, height: 40, borderRadius: 12),
            const SizedBox(width: DesignSpacing.md),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerWidget(width: 160, height: 13),
                if (twoLines) ...[
                  const SizedBox(height: 8),
                  const ShimmerWidget(width: 96, height: 10),
                ],
              ],
            ),
          ),
          if (trailing) const ShimmerWidget(width: 64, height: 16),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 8,
    this.leading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
  });

  final int rows;
  final bool leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: rows,
      itemBuilder: (_, __) => SkeletonRow(leading: leading),
    );
  }
}
