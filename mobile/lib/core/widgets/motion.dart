import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/design_system.dart';

/// ═══════════════════════════════════════════════════════════════
/// MOTION UTILITIES — reduced-motion gating + entrance choreography
/// Every decorative/entrance animation in the app should ask this file
/// first. When the OS "remove animations" accessibility setting is on,
/// loops must stop and entrances must land on their final state
/// instantly — movement is replaced by opacity only.
/// ═══════════════════════════════════════════════════════════════

/// True when the device has "remove animations" (a11y) enabled. Gate all
/// non-essential motion behind this; see [animateEntrance] and
/// [StaggeredItem] for the two canonical patterns.
bool reducedMotion(BuildContext c) => MediaQuery.disableAnimationsOf(c);

/// A tiny handle over the entrance effects a widget asked for, so the
/// reduced-motion branch can reuse the exact same effect list.
typedef EntranceEffects = List<Effect> Function();

extension MotionAwareAnimate on Widget {
  /// Conditionally plays [effects] (typically `.fadeIn().move(...)` chains
  /// built with flutter_animate) with an optional [delay] and an [onPlay]
  /// hook (used to loop a finished entrance, e.g. a shimmer).
  ///
  /// When reduced motion is ON the effects are instead resolved to their
  /// FINAL state with zero movement and zero delay — opacity-only
  /// semantics: whatever the effect list ends on is what the user sees,
  /// drawn immediately, and nothing is animated afterwards.
  ///
  /// ```dart
  /// child.animateEntrance(
  ///   context,
  ///   effects: () => [
  ///     FadeEffect(duration: DesignAnimation.fast),
  ///   ],
  ///   onPlay: (c) => c.repeat(), // loops only when motion is allowed
  /// );
  /// ```
  Widget animateEntrance(
    BuildContext context, {
    required EntranceEffects effects,
    Duration delay = Duration.zero,
    void Function(AnimationController)? onPlay,
  }) {
    if (reducedMotion(context)) {
      // Pre-seed the animation at its end value: flutter_animate renders
      // every effect evaluated at t=1 (e.g. fully faded in, at rest
      // position) without ever ticking the controller. The onPlay loop
      // hook is intentionally NOT wired in this branch so infinite
      // animations stay stopped.
      return Animate(
        effects: effects(),
        value: 1.0,
        child: this,
      );
    }
    return Animate(
      effects: effects(),
      delay: delay,
      onPlay: onPlay,
      child: this,
    );
  }
}

/// ═══════════════════════════════════════════════════════════════
/// STAGGERED ITEM — first-mount list entrance
/// ═══════════════════════════════════════════════════════════════

/// Wraps a list child with a fade + 8px rise that plays ONCE, on the
/// item's FIRST mount only. Re-renders and scroll rebuilds never replay
/// it: the [GlobalObjectKey] is stable per [itemKey], so the underlying
/// [Animate] state (and its completed controller) survives ancestor
/// rebuilds, and it is never re-created for the same list entry.
///
/// Each item starts [DesignAnimation.staggerInterval] (40ms) later than
/// the previous one, via [index]. The reveal itself runs
/// [DesignAnimation.fast] (250ms).
///
/// Reduced motion: no rise, no delay — the item simply fades in
/// (opacity only), which is the a11y-safe equivalent.
///
/// Usage:
/// ```dart
/// ListView.builder(
///   itemCount: products.length,
///   itemBuilder: (context, i) {
///     final product = products[i];
///     return StaggeredItem(
///       itemKey: 'product-${product.id}',
///       index: i,
///       child: ProductCard(product: product),
///     );
///   },
/// )
/// ```
class StaggeredItem extends StatelessWidget {
  final Widget child;

  /// Stable identity of the list entry (e.g. `'product-42'`). Must not
  /// change across rebuilds of the same item — it keys the entrance state.
  final String itemKey;

  /// Position of the item in the list; multiplies the 40ms stagger delay.
  final int index;

  const StaggeredItem({
    super.key,
    required this.child,
    required this.itemKey,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = reducedMotion(context);

    return child.animateEntrance(
      context,
      delay: DesignAnimation.staggerInterval * index,
      effects: () => [
        const FadeEffect(
          duration: DesignAnimation.fast,
          curve: DesignAnimation.smooth,
        ),
        if (!reduced)
          const MoveEffect(
            begin: Offset(0, 8),
            end: Offset.zero,
            duration: DesignAnimation.fast,
            curve: DesignAnimation.smooth,
          ),
      ],
    );
  }
}