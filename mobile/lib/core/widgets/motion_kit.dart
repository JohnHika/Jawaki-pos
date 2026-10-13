import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/design_system.dart';
import 'motion.dart';

/// ═══════════════════════════════════════════════════════════════
/// MOTION KIT — small, reusable animation primitives
///
/// Everything here is:
///  * reduced-motion aware (the OS "remove animations" setting turns each
///    one into an instant, static render),
///  * FINITE (nothing loops forever, so `pumpAndSettle` and idle battery
///    stay healthy), and
///  * cheap (one controller, no layout churn).
///
/// The shared design-system widgets (cards, headers, empty states, nav bar,
/// buttons, badges…) already use these, so most screens animate without
/// each one wiring anything. Reach for them directly for one-offs.
/// ═══════════════════════════════════════════════════════════════

enum SlideFrom { bottom, top, left, right, none }

Offset _offsetFor(SlideFrom from, double distance) => switch (from) {
      SlideFrom.bottom => Offset(0, distance),
      SlideFrom.top => Offset(0, -distance),
      SlideFrom.left => Offset(-distance, 0),
      SlideFrom.right => Offset(distance, 0),
      SlideFrom.none => Offset.zero,
    };

// ───────────────────────────────────────────────────────────────
// 1. FadeSlideIn — fade + slide entrance, plays once on first mount
// ───────────────────────────────────────────────────────────────
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.from = SlideFrom.bottom,
    this.distance = 14,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final SlideFrom from;
  final double distance;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
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
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: widget.curve);
    final offset = _offsetFor(widget.from, widget.distance);
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: offset * (1 - curved.value),
          child: child,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 2. PopIn — springy scale-in (badges, success marks, FAB)
// ───────────────────────────────────────────────────────────────
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 460),
    this.beginScale = 0.6,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double beginScale;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
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
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(
        parent: _c, curve: const Interval(0, 0.5, curve: Curves.easeOut));
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: fade.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: widget.beginScale + (1 - widget.beginScale) * scale.value,
          child: child,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 3. TapScale — press-shrink feedback that never steals the tap
// ───────────────────────────────────────────────────────────────
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.scale = 0.96,
    this.enabled = true,
  });

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _down && !reducedMotion(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 4. CountUpText — numbers inside any formatted string roll to their
//    new value ("KES 2,090" -> "KES 2,450"), keeping prefix/suffix.
// ───────────────────────────────────────────────────────────────
class CountUpText extends StatefulWidget {
  const CountUpText(
    this.text, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 800),
    this.maxLines,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final Duration duration;
  final int? maxLines;
  final TextAlign? textAlign;

  /// Splits "KES 12,345.50 today" into prefix / number / suffix, or null.
  static ({String prefix, double value, int decimals, bool grouped, String suffix})?
      parse(String text) {
    final m = RegExp(r'^(\D*?)(-?\d[\d,]*(?:\.\d+)?)(.*)$', dotAll: true)
        .firstMatch(text);
    if (m == null) return null;
    final raw = m.group(2)!;
    final value = double.tryParse(raw.replaceAll(',', ''));
    if (value == null) return null;
    final dot = raw.indexOf('.');
    return (
      prefix: m.group(1)!,
      value: value,
      decimals: dot < 0 ? 0 : raw.length - dot - 1,
      grouped: raw.contains(','),
      suffix: m.group(3)!,
    );
  }

  static String _fmt(double v, int decimals, bool grouped) {
    final fixed = v.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    var whole = parts[0];
    if (grouped) {
      whole = whole.replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    }
    final body = parts.length > 1 ? '$whole.${parts[1]}' : whole;
    return v < 0 ? '-$body' : body;
  }

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  double _from = 0;
  double _to = 0;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    final p = CountUpText.parse(widget.text);
    _to = p?.value ?? 0;
    _from = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_first) {
      _first = false;
      if (reducedMotion(context) || CountUpText.parse(widget.text) == null) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    final p = CountUpText.parse(widget.text);
    if (p == null || widget.text == old.text) return;
    final current = _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value);
    _from = current;
    _to = p.value;
    if (reducedMotion(context)) {
      _c.value = 1;
    } else {
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
    final p = CountUpText.parse(widget.text);
    if (p == null) {
      return Text(widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          textAlign: widget.textAlign);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        final v = _from + (_to - _from) * t;
        return Text(
          '${p.prefix}${CountUpText._fmt(v, p.decimals, p.grouped)}${p.suffix}',
          style: widget.style,
          maxLines: widget.maxLines,
          textAlign: widget.textAlign,
        );
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 5. Floating — gentle bob for empty-state art (a few cycles, then rests)
// ───────────────────────────────────────────────────────────────
class Floating extends StatefulWidget {
  const Floating({
    super.key,
    required this.child,
    this.amplitude = 6,
    this.cycles = 4,
  });

  final Widget child;
  final double amplitude;
  final int cycles;

  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: Duration(milliseconds: 1800 * widget.cycles));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !reducedMotion(context)) {
      _started = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // Fade the bob out over the last cycle so it settles smoothly.
        final settle = 1 - Curves.easeIn.transform(((_c.value - 0.75) / 0.25).clamp(0, 1));
        final dy = math.sin(_c.value * widget.cycles * 2 * math.pi) *
            widget.amplitude *
            settle;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 6. AnimatedCheckmark — ring + tick that draws itself (success states)
// ───────────────────────────────────────────────────────────────
class AnimatedCheckmark extends StatefulWidget {
  const AnimatedCheckmark({
    super.key,
    this.size = 88,
    this.color = DesignColors.success,
    this.strokeWidth = 5,
    this.delay = Duration.zero,
  });

  final double size;
  final Color color;
  final double strokeWidth;
  final Duration delay;

  @override
  State<AnimatedCheckmark> createState() => _AnimatedCheckmarkState();
}

class _AnimatedCheckmarkState extends State<AnimatedCheckmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _CheckPainter(
            progress: _c.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(
      {required this.progress, required this.color, required this.strokeWidth});

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth;
    final ringT = Curves.easeOutCubic.transform((progress / 0.55).clamp(0, 1));
    final tickT = Curves.easeOutCubic.transform(((progress - 0.45) / 0.55).clamp(0, 1));

    // Soft filled disc that fades up behind the ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.12 * ringT),
    );

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * ringT,
      false,
      ring,
    );

    final a = Offset(size.width * 0.29, size.height * 0.52);
    final b = Offset(size.width * 0.44, size.height * 0.66);
    final c = Offset(size.width * 0.72, size.height * 0.36);
    final path = Path()..moveTo(a.dx, a.dy);
    final firstLen = (b - a).distance;
    final secondLen = (c - b).distance;
    final total = firstLen + secondLen;
    final drawn = total * tickT;
    if (drawn <= firstLen) {
      final p = a + (b - a) * (drawn / firstLen);
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = b + (c - b) * ((drawn - firstLen) / secondLen);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, ring);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

// ───────────────────────────────────────────────────────────────
// 7. ConfettiBurst — one-shot celebration (sale completed)
// ───────────────────────────────────────────────────────────────
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.count = 46,
    this.duration = const Duration(milliseconds: 1900),
    this.colors = const [
      DesignColors.accent,
      DesignColors.brand,
      DesignColors.success,
      DesignColors.warning,
      DesignColors.info,
    ],
  });

  final int count;
  final Duration duration;
  final List<Color> colors;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final List<_Particle> _ps;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _ps = List.generate(widget.count, (i) {
      final angle = (-math.pi / 2) + (rnd.nextDouble() - 0.5) * math.pi * 1.25;
      return _Particle(
        angle: angle,
        speed: 220 + rnd.nextDouble() * 360,
        spin: (rnd.nextDouble() - 0.5) * 14,
        size: 5 + rnd.nextDouble() * 6,
        color: widget.colors[i % widget.colors.length],
        round: rnd.nextBool(),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !reducedMotion(context)) {
      _started = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_ps, _c.value),
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.size,
    required this.color,
    required this.round,
  });
  final double angle, speed, spin, size;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.ps, this.t);
  final List<_Particle> ps;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.34);
    for (final p in ps) {
      final dx = math.cos(p.angle) * p.speed * t;
      // Gravity pulls each piece back down after the initial burst.
      final dy = math.sin(p.angle) * p.speed * t + 520 * t * t;
      final pos = origin + Offset(dx, dy);
      final alpha = (1 - Curves.easeIn.transform(((t - 0.6) / 0.4).clamp(0, 1)));
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ───────────────────────────────────────────────────────────────
// 8. BadgeBounce — pops whenever [value] changes (cart count, alerts)
// ───────────────────────────────────────────────────────────────
class BadgeBounce extends StatefulWidget {
  const BadgeBounce({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  State<BadgeBounce> createState() => _BadgeBounceState();
}

class _BadgeBounceState extends State<BadgeBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(BadgeBounce old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !reducedMotion(context)) {
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
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // 1 -> 1.35 -> 1 with a springy settle.
        final t = _c.value;
        final s = 1 + 0.35 * math.sin(t * math.pi) * (1 - t * 0.4);
        return Transform.scale(scale: s, child: child);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 9. AnimatedProgressBar — fills smoothly to [value] (0..1)
// ───────────────────────────────────────────────────────────────
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color = DesignColors.accent,
    this.trackColor,
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final double height;
  final Color color;
  final Color? trackColor;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = trackColor ??
        (isDark ? DesignColors.darkBorder : DesignColors.surfaceSubtle);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
        duration: reducedMotion(context) ? Duration.zero : duration,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: track,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 10. Shake — horizontal shake whenever [trigger] changes (bad input)
// ───────────────────────────────────────────────────────────────
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480));

  @override
  void didUpdateWidget(Shake old) {
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
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final dx = math.sin(t * math.pi * 6) * 9 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 11. SlideSwitcher — value changes slide + fade (totals, status text)
// ───────────────────────────────────────────────────────────────
class SlideSwitcher extends StatelessWidget {
  const SlideSwitcher({
    super.key,
    required this.child,
    this.from = SlideFrom.bottom,
    this.duration = const Duration(milliseconds: 260),
  });

  /// Give the child a ValueKey so a change is detected.
  final Widget child;
  final SlideFrom from;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: _offsetFor(from, 0.4),
            end: Offset.zero,
          ).animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 12. RippleRings — expanding rings behind a hero icon (payment success)
// ───────────────────────────────────────────────────────────────
class RippleRings extends StatefulWidget {
  const RippleRings({
    super.key,
    required this.child,
    this.color = DesignColors.success,
    this.size = 140,
    this.rings = 3,
  });

  final Widget child;
  final Color color;
  final double size;
  final int rings;

  @override
  State<RippleRings> createState() => _RippleRingsState();
}

class _RippleRingsState extends State<RippleRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !reducedMotion(context)) {
      _started = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _RingsPainter(
                  t: _c.value, color: widget.color, rings: widget.rings),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t, required this.color, required this.rings});
  final double t;
  final Color color;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < rings; i++) {
      final local = ((t * 1.6) - i * 0.28).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final r = size.width * (0.28 + 0.22 * Curves.easeOut.transform(local));
      canvas.drawCircle(
        c,
        r + local * size.width * 0.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - local) + 0.5
          ..color = color.withValues(alpha: 0.5 * (1 - local)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

// ───────────────────────────────────────────────────────────────
// 13. Typewriter — AI replies / hints type themselves out
// ───────────────────────────────────────────────────────────────
class Typewriter extends StatefulWidget {
  const Typewriter(
    this.text, {
    super.key,
    this.style,
    this.charsPerSecond = 55,
  });

  final String text;
  final TextStyle? style;
  final int charsPerSecond;

  @override
  State<Typewriter> createState() => _TypewriterState();
}

class _TypewriterState extends State<Typewriter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(
        milliseconds: (widget.text.length * 1000 / widget.charsPerSecond)
            .round()
            .clamp(1, 6000)),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final n = (widget.text.length * _c.value).round();
        return Text(widget.text.substring(0, n), style: widget.style);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 14. PulseDot — "live"/"online" dot that pulses a few times, then rests
// ───────────────────────────────────────────────────────────────
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    this.color = DesignColors.success,
    this.size = 8,
    this.pulses = 5,
  });

  final Color color;
  final double size;
  final int pulses;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: Duration(milliseconds: 1400 * widget.pulses));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !reducedMotion(context)) {
      _started = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 3,
      height: widget.size * 3,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final phase = (_c.value * widget.pulses) % 1.0;
          return CustomPaint(
            painter: _PulsePainter(
                phase: _c.isCompleted ? 1 : phase,
                color: widget.color,
                dot: widget.size / 2),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.phase, required this.color, required this.dot});
  final double phase;
  final Color color;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (phase < 1) {
      canvas.drawCircle(
        c,
        dot + (size.width / 2 - dot) * phase,
        Paint()..color = color.withValues(alpha: 0.35 * (1 - phase)),
      );
    }
    canvas.drawCircle(c, dot, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.phase != phase;
}

// ───────────────────────────────────────────────────────────────
// 15. StaggerIn — wraps a list of widgets in staggered FadeSlideIn
// ───────────────────────────────────────────────────────────────
extension StaggerChildren on List<Widget> {
  /// `children: [...].staggered()` — each child rises in 55ms after the last.
  List<Widget> staggered({
    Duration step = const Duration(milliseconds: 55),
    SlideFrom from = SlideFrom.bottom,
    int maxAnimated = 12,
  }) {
    return [
      for (var i = 0; i < length; i++)
        i < maxAnimated
            ? FadeSlideIn(delay: step * i, from: from, child: this[i])
            : this[i],
    ];
  }
}

// ───────────────────────────────────────────────────────────────
// 16. AnimatedGlowBorder — soft accent glow that eases in around a card
// ───────────────────────────────────────────────────────────────
class GlowOnSelect extends StatelessWidget {
  const GlowOnSelect({
    super.key,
    required this.selected,
    required this.child,
    this.color = DesignColors.accent,
    this.radius = 18,
  });

  final bool selected;
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: selected ? 0.28 : 0),
            blurRadius: selected ? 18 : 0,
            spreadRadius: selected ? 1 : 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 17. SpringIcon — icon that springs when it changes (nav, toggles)
// ───────────────────────────────────────────────────────────────
class SpringIcon extends StatelessWidget {
  const SpringIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 380),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: Icon(icon, key: ValueKey(icon.codePoint), color: color, size: size),
    );
  }
}
