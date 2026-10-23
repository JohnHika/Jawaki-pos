import 'dart:async';

import 'package:flutter/material.dart';

import '../services/haptic_service.dart';
import '../theme/design_system.dart';
import 'motion.dart' show reducedMotion;
import 'motion_kit.dart';

/// ═══════════════════════════════════════════════════════════════
/// RECEIPT PRINTER — a little thermal-printer machine with a screen that
/// walks through "Processing → Printing → Complete" while the paper feeds
/// out of the slot one line at a time, ending on a torn, zig-zag edge.
///
/// [ReceiptPrinterView] owns the whole receipt body (scroll view, machine,
/// paper, confetti). Feed it the on-screen summary and the paper contents.
/// ═══════════════════════════════════════════════════════════════

enum ReceiptPrinterStage { processing, printing, complete }

// Stepped paper feed: the roll advances in short bursts with a hold between
// them, like a real line printer. Offsets are a fraction of the paper's own
// height (-1 = fully hidden inside the slot, 0 = fully out).
const List<double> _feedOffsets = [
  -1, -0.91, -0.91, -0.81, -0.81, -0.70, -0.70, -0.58, -0.58, -0.45, //
  -0.45, -0.32, -0.32, -0.20, -0.20, -0.10, -0.10, -0.03, -0.03, 0,
];
const List<double> _feedTimes = [
  0, 0.075, 0.105, 0.18, 0.21, 0.285, 0.315, 0.39, 0.42, 0.495, //
  0.525, 0.6, 0.63, 0.705, 0.735, 0.81, 0.84, 0.915, 0.945, 1,
];

double _feedOffsetAt(double t) {
  if (t <= 0) return _feedOffsets.first;
  if (t >= 1) return _feedOffsets.last;
  for (var i = 0; i < _feedTimes.length - 1; i++) {
    final a = _feedTimes[i];
    final b = _feedTimes[i + 1];
    if (t <= b) {
      final k = (t - a) / (b - a);
      return _feedOffsets[i] + (_feedOffsets[i + 1] - _feedOffsets[i]) * k;
    }
  }
  return 0;
}

/// Index of the keyframe segment [t] falls in — used to tick the haptics
/// once per paper advance.
int _feedSegmentAt(double t) {
  for (var i = 0; i < _feedTimes.length - 1; i++) {
    if (t <= _feedTimes[i + 1]) return i;
  }
  return _feedTimes.length - 2;
}

class ReceiptPrinterView extends StatefulWidget {
  const ReceiptPrinterView({
    super.key,
    required this.ready,
    required this.celebrate,
    required this.summaryTitle,
    required this.summarySubtitle,
    required this.summaryTotal,
    required this.paper,
    this.logo,
    this.voided = false,
    this.completeLabel = 'Sale complete',
  });

  /// False while the receipt is still loading — the machine sits on
  /// "Processing" and starts printing the moment this flips true.
  final bool ready;

  /// Right after a sale: slower, haptic, with confetti at the end. Re-opening
  /// an old receipt prints straight away and a bit quicker.
  final bool celebrate;

  final String summaryTitle;
  final String summarySubtitle;
  final String summaryTotal;

  /// Contents of the printed paper (null while loading).
  final Widget? paper;

  /// Optional brand mark shown top-left of the machine.
  final Widget? logo;

  final bool voided;
  final String completeLabel;

  @override
  State<ReceiptPrinterView> createState() => _ReceiptPrinterViewState();
}

class _ReceiptPrinterViewState extends State<ReceiptPrinterView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _feed =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1750));
  Timer? _timer;
  ReceiptPrinterStage _stage = ReceiptPrinterStage.processing;
  bool _started = false;
  int _lastSegment = -1;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_tickHaptics);
    _feed.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _stage = ReceiptPrinterStage.complete);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(ReceiptPrinterView old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.ready || widget.paper == null) return;
    _started = true;

    if (reducedMotion(context)) {
      _feed.value = 1;
      _stage = ReceiptPrinterStage.complete;
      return;
    }

    // Brief "processing" beat so the screen reads as a real step, longer
    // after a fresh sale than when re-opening an old receipt.
    _timer = Timer(Duration(milliseconds: widget.celebrate ? 900 : 250), () {
      if (!mounted) return;
      _feed.duration =
          Duration(milliseconds: widget.celebrate ? 1750 : 1150);
      setState(() => _stage = ReceiptPrinterStage.printing);
      _feed.forward(from: 0);
    });
  }

  void _tickHaptics() {
    if (!widget.celebrate || _stage != ReceiptPrinterStage.printing) return;
    final seg = _feedSegmentAt(_feed.value);
    // Even segments are the moving ones; odd segments are the holds.
    if (seg != _lastSegment && seg.isEven) HapticService().selection();
    _lastSegment = seg;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showConfetti = widget.celebrate &&
        !widget.voided &&
        _stage == ReceiptPrinterStage.complete;

    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                vertical: DesignSpacing.xl, horizontal: DesignSpacing.lg),
            child: Center(
              child: LayoutBuilder(builder: (context, c) {
                final machineWidth = c.maxWidth.clamp(0.0, 336.0).toDouble();
                final paperWidth = machineWidth - 56;
                return SizedBox(
                  width: machineWidth,
                  child: Column(
                    children: [
                      _Machine(
                        isDark: isDark,
                        stage: _stage,
                        logo: widget.logo,
                        title: widget.summaryTitle,
                        subtitle: widget.summarySubtitle,
                        total: widget.summaryTotal,
                        completeLabel: widget.completeLabel,
                      ),
                      // The paper comes out of the slot and sits in front of
                      // the machine's lower lip.
                      Transform.translate(
                        offset: const Offset(0, -16),
                        child: _Output(
                          width: paperWidth,
                          feed: _feed,
                          stage: _stage,
                          voided: widget.voided,
                          paper: widget.paper,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
        if (showConfetti)
          const Positioned.fill(
            child: IgnorePointer(child: ConfettiBurst()),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────
// Machine body: header, dark screen, slot
// ───────────────────────────────────────────────────────────────
class _Machine extends StatelessWidget {
  const _Machine({
    required this.isDark,
    required this.stage,
    required this.logo,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.completeLabel,
  });

  final bool isDark;
  final ReceiptPrinterStage stage;
  final Widget? logo;
  final String title;
  final String subtitle;
  final String total;
  final String completeLabel;

  @override
  Widget build(BuildContext context) {
    final body = isDark ? const Color(0xFF2A2A31) : const Color(0xFF3B3B42);
    final bodyTop = isDark ? const Color(0xFF34343C) : const Color(0xFF4A4A52);
    final edge = isDark ? const Color(0xFF0E0E11) : const Color(0xFF17171A);
    final screenBg = isDark ? const Color(0xFF0C0C0E) : const Color(0xFF121214);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bodyTop, body],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: edge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 18),
            spreadRadius: -14,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    logo ?? const SizedBox(width: 24, height: 24),
                    _Led(stage: stage),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: screenBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: Color(0xFFF2F0EA))),
                              const SizedBox(height: 2),
                              Text(subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Color(0xFF8F8B82))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(total,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF2F0EA))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Status(stage: stage, completeLabel: completeLabel),
                  ],
                ),
              ),
            ],
          ),
          // The paper slot.
          Positioned(
            left: 12,
            right: 12,
            bottom: -20,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny status LED: amber while busy, green once done.
class _Led extends StatelessWidget {
  const _Led({required this.stage});
  final ReceiptPrinterStage stage;

  @override
  Widget build(BuildContext context) {
    final done = stage == ReceiptPrinterStage.complete;
    final color = done ? DesignColors.success : DesignColors.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            done ? 'READY' : 'BUSY',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.stage, required this.completeLabel});
  final ReceiptPrinterStage stage;
  final String completeLabel;

  String get _label => switch (stage) {
        ReceiptPrinterStage.processing => 'Processing your sale',
        ReceiptPrinterStage.printing => 'Printing your receipt',
        ReceiptPrinterStage.complete => completeLabel,
      };

  @override
  Widget build(BuildContext context) {
    final done = stage == ReceiptPrinterStage.complete;
    const dim = Color(0xFF8F8B82);
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                  scale: Tween(begin: 0.9, end: 1.0).animate(anim),
                  child: child),
            ),
            child: done
                ? const Icon(Icons.check_circle_rounded,
                    key: ValueKey('done'),
                    size: 19,
                    color: DesignColors.success)
                : const Center(
                    key: ValueKey('busy'),
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: dim),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.35), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                _label,
                key: ValueKey(stage),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: dim),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────
// Paper output: clipped window below the slot, paper slides down into view
// ───────────────────────────────────────────────────────────────
class _Output extends StatelessWidget {
  const _Output({
    required this.width,
    required this.feed,
    required this.stage,
    required this.voided,
    required this.paper,
  });

  final double width;
  final Animation<double> feed;
  final ReceiptPrinterStage stage;
  final bool voided;
  final Widget? paper;

  static const Color paperColor = Color(0xFFFAFAF7);
  static const Color inkColor = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    final printing = stage != ReceiptPrinterStage.processing;

    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRect(
            child: AnimatedBuilder(
              animation: feed,
              builder: (context, child) => Opacity(
                // Hidden until printing starts so the first 2px of paper
                // never peeks out of the slot while "processing".
                opacity: printing ? 1 : 0,
                child: FractionalTranslation(
                  translation: Offset(0, _feedOffsetAt(feed.value)),
                  child: child,
                ),
              ),
              child: paper == null
                  ? const SizedBox(height: 320)
                  : ClipPath(
                      clipper: const _TornEdgeClipper(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 22, 14, 30),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [paperColor, Color(0xFFF4F3EC)],
                          ),
                          border: voided
                              ? const Border(
                                  top: BorderSide(
                                      color: DesignColors.error, width: 3))
                              : null,
                        ),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(color: inkColor),
                          child: paper!,
                        ),
                      ),
                    ),
            ),
          ),
          // Soft shadow where the paper leaves the slot.
          if (printing)
            Positioned(
              left: 4,
              right: 4,
              top: -2,
              child: IgnorePointer(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Zig-zag torn bottom edge: 40 teeth, 4dp deep.
class _TornEdgeClipper extends CustomClipper<Path> {
  const _TornEdgeClipper();

  static const int _teeth = 40;
  static const double _depth = 4;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - _depth);
    for (var i = 0; i < _teeth * 2; i++) {
      final x = w - (i + 1) * w / (_teeth * 2);
      path.lineTo(x, i.isEven ? h : h - _depth);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
