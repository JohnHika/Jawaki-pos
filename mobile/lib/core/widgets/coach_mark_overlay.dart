import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// One step in a coach-mark tour: spotlights the real widget attached to
/// [targetKey] and shows [title]/[description] near it.
///
/// [beforeShow] runs (and is awaited) immediately before this step is
/// displayed — use it for steps whose target isn't normally on screen,
/// e.g. opening the "More" bottom sheet so an item inside it can be
/// spotlighted. [onLeave] runs when moving on to the next step or
/// finishing/skipping the tour, to undo whatever [beforeShow] did (e.g.
/// closing that same sheet) so the tour never leaves stray UI open behind
/// it. [targetKey] must be attached to its real widget and laid out by the
/// time [beforeShow] resolves — a post-frame callback is required after
/// any UI change beforeShow triggers before the overlay reads its position.
class CoachMarkStep {
  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.beforeShow,
    this.onLeave,
  });

  final GlobalKey targetKey;
  final String title;
  final String description;
  final Future<void> Function()? beforeShow;
  final VoidCallback? onLeave;
}

/// Shows an interactive, dimmed spotlight tour over whatever is already on
/// screen. Call [show] once the first step's target widget has been laid
/// out (e.g. from a post-frame callback) — it inserts itself into the
/// app's root [Overlay], so it draws above the bottom nav and any other
/// chrome without the calling screen needing to embed it directly.
class CoachMarkTour {
  CoachMarkTour({required this.steps, required this.onFinished});

  final List<CoachMarkStep> steps;
  final VoidCallback onFinished;

  OverlayEntry? _entry;
  int _stepIndex = 0;
  bool _isTransitioning = false;

  Future<void> show(BuildContext context) async {
    if (steps.isEmpty) {
      onFinished();
      return;
    }
    _stepIndex = 0;
    await steps[0].beforeShow?.call();
    if (!context.mounted) return;
    _entry = OverlayEntry(builder: _build);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  Future<void> _advance() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      steps[_stepIndex].onLeave?.call();
      if (_stepIndex >= steps.length - 1) {
        _finish();
        return;
      }
      _stepIndex++;
      await steps[_stepIndex].beforeShow?.call();
      // Give the newly-revealed target (e.g. inside a just-opened sheet) a
      // frame to lay out before the spotlight reads its position.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _entry?.markNeedsBuild();
    } finally {
      _isTransitioning = false;
    }
  }

  void _finish() {
    steps[_stepIndex].onLeave?.call();
    _entry?.remove();
    _entry = null;
    onFinished();
  }

  Widget _build(BuildContext context) {
    final step = steps[_stepIndex];
    final targetBox =
        step.targetKey.currentContext?.findRenderObject() as RenderBox?;

    // The target may not be mounted (e.g. a nav tab that scrolled out of a
    // narrow screen's visible row) — skip straight to the next step rather
    // than showing a spotlight pointing at nothing.
    if (targetBox == null || !targetBox.attached) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
      return const SizedBox.shrink();
    }

    final targetTopLeft = targetBox.localToGlobal(Offset.zero);
    final targetRect = targetTopLeft & targetBox.size;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _advance,
              child: CustomPaint(
                painter: _SpotlightPainter(targetRect: targetRect),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _TourCard(
            targetRect: targetRect,
            step: step,
            stepNumber: _stepIndex + 1,
            totalSteps: steps.length,
            onNext: _advance,
            onSkip: _finish,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.targetRect});

  final Rect targetRect;
  static const _padding = 8.0;
  static const _radius = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scrimPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        targetRect.inflate(_padding),
        const Radius.circular(_radius),
      ));

    final cutout = Path.combine(PathOperation.difference, scrimPath, holePath);
    canvas.drawPath(cutout, Paint()..color = Colors.black.withValues(alpha: 0.72));
    canvas.drawRRect(
      RRect.fromRectAndRadius(targetRect.inflate(_padding), const Radius.circular(_radius)),
      Paint()
        ..color = DesignColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.targetRect,
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  final Rect targetRect;
  final CoachMarkStep step;
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Prefer placing the card below the spotlighted target; if there isn't
    // room (target is near the bottom of the screen, e.g. the bottom nav),
    // place it above instead.
    final spaceBelow = screenSize.height - targetRect.bottom;
    final placeBelow = spaceBelow > 220;
    final cardTop = placeBelow ? targetRect.bottom + 24 : null;
    final cardBottom = placeBelow ? null : screenSize.height - targetRect.top + 24;

    return Positioned(
      left: 20,
      right: 20,
      top: cardTop,
      bottom: cardBottom,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: DesignColors.darkSurfaceElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DesignColors.brand.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      totalSteps,
                      (i) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < stepNumber
                                ? DesignColors.brand
                                : DesignColors.darkTextTertiary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: DesignColors.darkTextTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                step.title,
                style: const TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.description,
                style: const TextStyle(
                  color: DesignColors.darkTextSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: stepNumber == totalSteps ? 'Got it' : 'Next',
                onPressed: onNext,
                height: 46,
                borderRadius: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
