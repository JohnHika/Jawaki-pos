import 'package:flutter/material.dart';

import 'device_class.dart';

/// The width of the pane a widget is drawn in, for widgets that size
/// themselves from "how much room do I have" (a product grid picking its
/// columns) and would otherwise read the whole screen's width. Falls back to
/// the screen width when no pane is above.
class PaneExtent extends InheritedWidget {
  const PaneExtent({super.key, required this.width, required super.child});

  final double width;

  static double? maybeWidthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneExtent>()?.width;

  static double widthOf(BuildContext context) =>
      maybeWidthOf(context) ?? MediaQuery.sizeOf(context).width;

  @override
  bool updateShouldNotify(PaneExtent oldWidget) => width != oldWidget.width;
}

/// How two panes are placed inside a page: side by side or stacked, and how
/// much room each gets. Pure so it can be checked without a screen.
@immutable
class TwoPanePlan {
  const TwoPanePlan({
    required this.axis,
    required this.primary,
    required this.gap,
    required this.secondary,
    this.atFold = false,
  });

  /// [Axis.horizontal] puts the panes side by side, [Axis.vertical] stacks
  /// them (primary on top).
  final Axis axis;

  /// Room for the first pane along [axis].
  final double primary;

  /// Dead space between them: the hinge, when the split follows one.
  final double gap;

  /// Room for the second pane along [axis].
  final double secondary;

  /// True when the split follows the device's fold or hinge.
  final bool atFold;

  /// Chooses the split for a page of [size].
  ///
  /// With a fold that crosses the page the panes sit on either side of it, so
  /// nothing is drawn under the crease and each half is a comfortable screen.
  /// Otherwise the second pane gets [fraction] of the width, kept between
  /// [secondaryMin] and [secondaryMax].
  ///
  /// [origin] is the page's top-left corner on the screen, which turns the
  /// fold's screen position into a position on this page.
  factory TwoPanePlan.compute({
    required Size size,
    FoldInfo fold = FoldInfo.none,
    Offset origin = Offset.zero,
    double fraction = 0.36,
    double secondaryMin = 300,
    double secondaryMax = 420,
    double primaryMin = 240,
  }) {
    final w = size.width;
    final h = size.height;
    final crease = fold.bounds?.shift(-origin);
    if (crease != null) {
      if (fold.isVertical) {
        final p = crease.left;
        final s = w - crease.right;
        final crosses = crease.bottom > 0 && crease.top < h;
        if (crosses && p >= primaryMin && s >= secondaryMin) {
          return TwoPanePlan(
            axis: Axis.horizontal,
            primary: p,
            gap: crease.width.clamp(0.0, 160.0),
            secondary: s,
            atFold: true,
          );
        }
      } else {
        // Half open like a laptop: browse on the top half, sell on the lower.
        final p = crease.top;
        final s = h - crease.bottom;
        final crosses = crease.right > 0 && crease.left < w;
        if (crosses && h >= 480 && p >= 200 && s >= 220) {
          return TwoPanePlan(
            axis: Axis.vertical,
            primary: p,
            gap: crease.height.clamp(0.0, 160.0),
            secondary: s,
            atFold: true,
          );
        }
      }
    }
    final s = (w * fraction).clamp(secondaryMin, secondaryMax).toDouble();
    return TwoPanePlan(
      axis: Axis.horizontal,
      primary: w - s,
      gap: 0,
      secondary: s,
    );
  }
}

/// A page with a main pane and a side pane that share the screen when there is
/// room, and fall back to one column when there is not.
///
/// On a phone, or a foldable folded shut, [narrowBuilder] draws the main pane
/// on its own (add a bottom bar, say). On a tablet, a till terminal, a phone
/// held sideways or a foldable opened up, [primary] and [secondary] sit next
/// to each other. A foldable half open puts one on each side of the hinge.
///
/// The main pane keeps its state (scroll position, search text) when the
/// screen reflows, because it is moved rather than rebuilt.
class AdaptiveTwoPane extends StatefulWidget {
  const AdaptiveTwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    required this.narrowBuilder,
    this.minWidth = 560,
    this.secondaryFraction = 0.36,
    this.secondaryMinWidth = 300,
    this.secondaryMaxWidth = 420,
  });

  /// The pane that stays when the page is narrow (the product browser).
  final Widget primary;

  /// The pane that only appears when there is room (the sale ticket).
  final Widget secondary;

  /// Draws the page in one column; [primary] is handed in so it can be placed.
  final Widget Function(BuildContext context, Widget primary) narrowBuilder;

  /// The page width where two panes start to fit.
  final double minWidth;
  final double secondaryFraction;
  final double secondaryMinWidth;
  final double secondaryMaxWidth;

  @override
  State<AdaptiveTwoPane> createState() => _AdaptiveTwoPaneState();
}

class _AdaptiveTwoPaneState extends State<AdaptiveTwoPane> {
  final _primaryKey = GlobalKey(debugLabel: 'two-pane-primary');
  Offset _origin = Offset.zero;

  /// Learns where this page starts on the screen so the fold's position can be
  /// read relative to it (a side rail or app bar pushes the page over or down).
  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    if (origin != _origin) setState(() => _origin = origin);
  }

  @override
  Widget build(BuildContext context) {
    final fold = context.foldInfo;
    if (fold.hasFold) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final primary = KeyedSubtree(key: _primaryKey, child: widget.primary);
        if (!width.isFinite || width < widget.minWidth) {
          return PaneExtent(
            width: width.isFinite ? width : MediaQuery.sizeOf(context).width,
            child: widget.narrowBuilder(context, primary),
          );
        }
        final plan = TwoPanePlan.compute(
          size: Size(width, constraints.maxHeight),
          fold: fold,
          origin: _origin,
          fraction: widget.secondaryFraction,
          secondaryMin: widget.secondaryMinWidth,
          secondaryMax: widget.secondaryMaxWidth,
        );
        if (plan.axis == Axis.vertical) {
          return Column(
            children: [
              SizedBox(
                height: plan.primary,
                child: PaneExtent(width: width, child: primary),
              ),
              SizedBox(height: plan.gap),
              Expanded(
                child: PaneExtent(width: width, child: widget.secondary),
              ),
            ],
          );
        }
        if (plan.atFold) {
          return Row(
            children: [
              SizedBox(
                width: plan.primary,
                child: PaneExtent(width: plan.primary, child: primary),
              ),
              SizedBox(width: plan.gap),
              Expanded(
                child: PaneExtent(
                  width: plan.secondary,
                  child: widget.secondary,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: PaneExtent(width: plan.primary, child: primary),
            ),
            SizedBox(
              width: plan.secondary,
              child: PaneExtent(width: plan.secondary, child: widget.secondary),
            ),
          ],
        );
      },
    );
  }
}
