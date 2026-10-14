import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/design_system.dart';
import 'motion.dart';

/// ═══════════════════════════════════════════════════════════════
/// MOTION KIT EXTRAS — a second set of one-shot entrance, change and
/// emphasis animations that sit beside `motion_kit.dart`.
///
/// Same rules as the main kit: reduced-motion aware (lands on the final
/// frame instantly), finite (nothing loops), one controller each.
/// ═══════════════════════════════════════════════════════════════

/// Plays once on first mount, then rests on its last frame.
class _OneShot extends StatefulWidget {
  const _OneShot({
    required this.builder,
    required this.child,
    required this.duration,
    required this.curve,
    this.delay = Duration.zero,
  });

  final Widget Function(BuildContext, double t, Widget child) builder;
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  @override
  State<_OneShot> createState() => _OneShotState();
}

class _OneShotState extends State<_OneShot> with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  Ticker? _wait;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      // A Ticker (not a Timer) so the delay follows the frame clock.
      _wait = createTicker((elapsed) {
        if (elapsed >= widget.delay) {
          _wait?.stop();
          if (mounted) _c.forward();
        }
      })
        ..start();
    }
  }

  @override
  void dispose() {
    _wait?.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: widget.curve);
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, curved.value, child!),
    );
  }
}

// 1 ─ FlipIn: turns over on the vertical axis, like a card being dealt.
class FlipIn extends StatelessWidget {
  const FlipIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeOutBack,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY((1 - t) * math.pi / 2.2),
            child: child,
          ),
        ),
      );
}

// 2 ─ BlurIn: arrives out of focus and sharpens.
class BlurIn extends StatelessWidget {
  const BlurIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.sigma = 8,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double sigma;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeOut,
        child: child,
        builder: (context, t, child) {
          final s = sigma * (1 - t);
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: s < 0.2
                ? child
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
                    child: child,
                  ),
          );
        },
      );
}

// 3 ─ WipeIn: revealed left-to-right by a sliding edge.
class WipeIn extends StatelessWidget {
  const WipeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 560),
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeInOutCubic,
        child: child,
        builder: (context, t, child) => ClipRect(
          child: Align(
            alignment: alignment,
            widthFactor: t.clamp(0.0, 1.0),
            child: child,
          ),
        ),
      );
}

// 4 ─ UnfoldIn: grows open from its top edge (accordion feel).
class UnfoldIn extends StatelessWidget {
  const UnfoldIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 460),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, t, child) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t.clamp(0.0, 1.0),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
        ),
      );
}

// 5 ─ DropIn: falls from above and bounces to rest.
class DropIn extends StatelessWidget {
  const DropIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.distance = 36,
    this.duration = const Duration(milliseconds: 720),
  });

  final Widget child;
  final Duration delay;
  final double distance;
  final Duration duration;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.bounceOut,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: (t * 3).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -distance * (1 - t)),
            child: child,
          ),
        ),
      );
}

// 6 ─ SwingIn: tips in from a tilt, like a hanging sign settling.
class SwingIn extends StatelessWidget {
  const SwingIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 640),
    this.angle = 0.28,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double angle;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.elasticOut,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: (t * 2.5).clamp(0.0, 1.0),
          child: Transform.rotate(
            alignment: Alignment.topCenter,
            angle: angle * (1 - t),
            child: child,
          ),
        ),
      );
}

// 7 ─ ZoomOutIn: starts oversized and settles (hero numbers, totals).
class ZoomSettle extends StatelessWidget {
  const ZoomSettle({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.from = 1.35,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double from;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: from + (1 - from) * t, child: child),
        ),
      );
}

// 8 ─ CircleReveal: expands out of a point as a circular mask.
class CircleReveal extends StatelessWidget {
  const CircleReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.center = Alignment.center,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Alignment center;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeInOutCubic,
        child: child,
        builder: (context, t, child) => t >= 1
            ? child
            : ClipPath(clipper: _CircleClipper(t, center), child: child),
      );
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.t, this.center);

  final double t;
  final Alignment center;

  @override
  Path getClip(Size size) {
    final c = center.alongSize(size);
    final far = math.sqrt(size.width * size.width + size.height * size.height);
    return Path()..addOval(Rect.fromCircle(center: c, radius: far * t));
  }

  @override
  bool shouldReclip(_CircleClipper old) => old.t != t || old.center != center;
}

// 9 ─ LetterRise: each letter rises in turn (titles, greetings).
class LetterRise extends StatelessWidget {
  const LetterRise(
    this.text, {
    super.key,
    this.style,
    this.delay = Duration.zero,
    this.step = const Duration(milliseconds: 28),
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final Duration delay;
  final Duration step;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final total = Duration(milliseconds: 380 + step.inMilliseconds * text.length);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: _OneShot(
        delay: delay,
        duration: total,
        curve: Curves.linear,
        child: const SizedBox.shrink(),
        builder: (context, t, _) {
          final base = style ?? DefaultTextStyle.of(context).style;
          final spans = <InlineSpan>[];
          for (var i = 0; i < text.length; i++) {
            final start = (step.inMilliseconds * i) / total.inMilliseconds;
            final local =
                ((t - start) / (380 / total.inMilliseconds)).clamp(0.0, 1.0);
            final e = Curves.easeOutCubic.transform(local);
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Opacity(
                opacity: e,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - e)),
                  child: Text(text[i], style: base),
                ),
              ),
            ));
          }
          return Text.rich(TextSpan(children: spans), textAlign: textAlign);
        },
      ),
    );
  }
}

// 10 ─ BorderDraw: an outline traces itself around a rounded rectangle.
class BorderDraw extends StatelessWidget {
  const BorderDraw({
    super.key,
    required this.child,
    this.color,
    this.radius = 20,
    this.strokeWidth = 1.6,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 900),
  });

  final Widget child;
  final Color? color;
  final double radius;
  final double strokeWidth;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? DesignColors.accent;
    return _OneShot(
      delay: delay,
      duration: duration,
      curve: Curves.easeInOutCubic,
      child: child,
      builder: (context, t, child) => CustomPaint(
        foregroundPainter: _BorderPainter(t, tint, radius, strokeWidth),
        child: child,
      ),
    );
  }
}

class _BorderPainter extends CustomPainter {
  _BorderPainter(this.t, this.color, this.radius, this.width);

  final double t;
  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return; // finished: the card keeps its own border
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color.withValues(alpha: 1 - t * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
    }
  }

  @override
  bool shouldRepaint(_BorderPainter old) => old.t != t || old.color != color;
}

// 11 ─ ArcGauge: a circular gauge that sweeps to its value.
class ArcGauge extends StatelessWidget {
  const ArcGauge({
    super.key,
    required this.value,
    this.size = 64,
    this.strokeWidth = 7,
    this.color,
    this.trackColor,
    this.child,
    this.duration = const Duration(milliseconds: 900),
  });

  /// 0..1
  final double value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;
  final Widget? child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    final tint = color ?? DesignColors.accent;
    final track = trackColor ?? tint.withValues(alpha: 0.14);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: reducedMotion(context) ? Duration.zero : duration,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _ArcPainter(v, tint, track, strokeWidth),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.v, this.color, this.track, this.width);

  final double v;
  final Color color;
  final Color track;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(width / 2, width / 2) &
        Size(size.width - width, size.height - width);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    if (v > 0) {
      canvas.drawArc(
          rect, -math.pi / 2, math.pi * 2 * v, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.v != v || old.color != color || old.track != track;
}

// 12 ─ RollingNumber: odometer digits roll when the number changes.
class RollingNumber extends StatelessWidget {
  const RollingNumber(
    this.text, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 420),
  });

  final String text;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final d = reducedMotion(context) ? Duration.zero : duration;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < text.length; i++)
            // Keyed from the right so the units digit keeps its identity when
            // the number grows a digit.
            _RollingChar(
              key: ValueKey<int>(text.length - i),
              char: text[i],
              style: base,
              duration: d,
            ),
        ],
      ),
    );
  }
}

class _RollingChar extends StatelessWidget {
  const _RollingChar({
    super.key,
    required this.char,
    required this.style,
    required this.duration,
  });

  final String char;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey<String>(char);
          return ClipRect(
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, incoming ? 0.9 : -0.9),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
          );
        },
        child: Text(char, key: ValueKey<String>(char), style: style),
      );
}

// 13 ─ BumpOnChange: the child pops whenever [trigger] changes.
class BumpOnChange extends StatefulWidget {
  const BumpOnChange({
    super.key,
    required this.trigger,
    required this.child,
    this.scale = 1.22,
  });

  final Object? trigger;
  final Widget child;
  final double scale;

  @override
  State<BumpOnChange> createState() => _BumpOnChangeState();
}

class _BumpOnChangeState extends State<BumpOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void didUpdateWidget(BumpOnChange old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !reducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          // 1 → scale → 1 with an overshoot on the way back.
          final bump = math.sin(_c.value * math.pi) * (widget.scale - 1);
          return Transform.scale(scale: 1 + bump, child: child);
        },
      );
}

// 14 ─ FlashOnChange: background flashes a tint when [trigger] changes.
class FlashOnChange extends StatefulWidget {
  const FlashOnChange({
    super.key,
    required this.trigger,
    required this.child,
    this.color,
    this.radius = 10,
  });

  final Object? trigger;
  final Widget child;
  final Color? color;
  final double radius;

  @override
  State<FlashOnChange> createState() => _FlashOnChangeState();
}

class _FlashOnChangeState extends State<FlashOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didUpdateWidget(FlashOnChange old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !reducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? DesignColors.accent;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.22 * (1 - _c.value)),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: child,
      ),
    );
  }
}

// 15 ─ SwipeNudge: slides sideways and back once, hinting a swipe action.
class SwipeNudge extends StatelessWidget {
  const SwipeNudge({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 700),
    this.distance = 26,
  });

  final Widget child;
  final Duration delay;
  final double distance;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: const Duration(milliseconds: 900),
        curve: Curves.linear,
        child: child,
        builder: (context, t, child) {
          // Out and back, easing both ways, finishing exactly at rest.
          final wave = math.sin(t * math.pi);
          return Transform.translate(
            offset: Offset(-distance * wave * wave, 0),
            child: child,
          );
        },
      );
}

// 16 ─ CascadeScale: grid/list items scale up from the centre in turn.
class CascadeScale extends StatelessWidget {
  const CascadeScale({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 45),
    this.maxAnimated = 14,
  });

  final int index;
  final Widget child;
  final Duration step;
  final int maxAnimated;

  @override
  Widget build(BuildContext context) {
    if (index >= maxAnimated) return child;
    return _OneShot(
      delay: step * index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.82 + 0.18 * t, child: child),
      ),
    );
  }
}

// 17 ─ SkeletonSwap: shimmer placeholder cross-fades into the content.
class SkeletonSwap extends StatelessWidget {
  const SkeletonSwap({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
    this.duration = const Duration(milliseconds: 360),
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: reducedMotion(context) ? Duration.zero : duration,
        switchInCurve: Curves.easeOut,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(a), child: c),
        ),
        child: loading
            ? KeyedSubtree(key: const ValueKey('skeleton'), child: skeleton)
            : KeyedSubtree(key: const ValueKey('content'), child: child),
      );
}

// 18 ─ PressDepth: sinks and dims while pressed, like a physical key.
class PressDepth extends StatefulWidget {
  const PressDepth({
    super.key,
    required this.child,
    this.onTap,
    this.depth = 3,
    this.radius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double depth;
  final double radius;

  @override
  State<PressDepth> createState() => _PressDepthState();
}

class _PressDepthState extends State<PressDepth> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final quick = reducedMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 110);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: quick,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _down ? widget.depth : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: _down ? 0.04 : 0.12),
              blurRadius: _down ? 2 : 10,
              offset: Offset(0, _down ? 1 : widget.depth + 2),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

// 19 ─ TiltOnDrag: card tilts toward the finger in 3D, springs back on release.
class TiltOnDrag extends StatefulWidget {
  const TiltOnDrag({super.key, required this.child, this.maxTilt = 0.12});

  final Widget child;
  final double maxTilt;

  @override
  State<TiltOnDrag> createState() => _TiltOnDragState();
}

class _TiltOnDragState extends State<TiltOnDrag> {
  Offset _tilt = Offset.zero;

  void _update(Offset local, Size size) {
    if (size.isEmpty || reducedMotion(context)) return;
    final dx = (local.dx / size.width - 0.5) * 2;
    final dy = (local.dy / size.height - 0.5) * 2;
    setState(() => _tilt = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Listener(
          onPointerDown: (e) => _update(e.localPosition, box.biggest),
          onPointerMove: (e) => _update(e.localPosition, box.biggest),
          onPointerUp: (_) => setState(() => _tilt = Offset.zero),
          onPointerCancel: (_) => setState(() => _tilt = Offset.zero),
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(begin: Offset.zero, end: _tilt),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (context, t, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0014)
                ..rotateX(-t.dy * widget.maxTilt)
                ..rotateY(t.dx * widget.maxTilt),
              child: child,
            ),
            child: widget.child,
          ),
        ),
      );
}

// 20 ─ SoftEntrance: fade + tiny scale, the calmest option for dense lists.
class SoftEntrance extends StatelessWidget {
  const SoftEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 340),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) => _OneShot(
        delay: delay,
        duration: duration,
        curve: Curves.easeOut,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
        ),
      );
}

/// `[...].cascaded()` — grid/list children scale in from the centre in turn.
extension CascadeChildren on List<Widget> {
  List<Widget> cascaded({
    Duration step = const Duration(milliseconds: 45),
    int maxAnimated = 14,
  }) =>
      [
        for (var i = 0; i < length; i++)
          i < maxAnimated
              ? CascadeScale(
                  index: i,
                  step: step,
                  maxAnimated: maxAnimated,
                  child: this[i])
              : this[i],
      ];
}
