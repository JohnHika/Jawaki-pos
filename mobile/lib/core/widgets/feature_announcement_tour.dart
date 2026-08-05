import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/feature_announcement_service.dart';
import '../theme/design_system.dart';

/// A full-screen, animated feature announcement tour that shows a series
/// of feature highlights with motion effects powered by [flutter_animate].
///
/// Each step is a [FeatureAnnouncement] with its own [FeatureAnimationType]
/// for the entrance effect. The tour is shown as an [OverlayEntry] on the
/// root overlay, so it draws above everything including the bottom nav.
///
/// Usage:
/// ```dart
/// final tour = FeatureAnnouncementTour(
///   announcements: service.pending,
///   service: service,
///   onFinished: () => print('done'),
/// );
/// await tour.show(context);
/// ```
class FeatureAnnouncementTour {
  FeatureAnnouncementTour({
    required this.announcements,
    required this.service,
    required this.onFinished,
  });

  final List<FeatureAnnouncement> announcements;
  final FeatureAnnouncementService service;
  final VoidCallback onFinished;

  OverlayEntry? _entry;
  int _stepIndex = 0;
  bool _isAnimating = false;

  Future<void> show(BuildContext context) async {
    if (announcements.isEmpty) {
      onFinished();
      return;
    }
    _stepIndex = 0;
    _entry = OverlayEntry(builder: (_) => _build(context));
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  Future<void> _advance() async {
    if (_isAnimating) return;
    _isAnimating = true;
    try {
      if (_stepIndex >= announcements.length - 1) {
        _finish();
        return;
      }
      _stepIndex++;
      _entry?.markNeedsBuild();
    } finally {
      _isAnimating = false;
    }
  }

  Future<void> _finish() async {
    await service.markAllSeen();
    _entry?.remove();
    _entry = null;
    onFinished();
  }

  Widget _build(BuildContext context) {
    final announcement = announcements[_stepIndex];
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dimmed scrim
          Positioned.fill(
            child: GestureDetector(
              onTap: _advance,
              child: Container(color: Colors.black.withValues(alpha: 0.72)),
            ),
          ),
          // Animated announcement card
          Center(
            child: _AnimatedFeatureCard(
              key: ValueKey('feature_card_$_stepIndex'),
              announcement: announcement,
              stepNumber: _stepIndex + 1,
              totalSteps: announcements.length,
              onNext: _advance,
              onSkip: _finish,
            ),
          ),
        ],
      ),
    );
  }
}

/// The animated feature announcement card with flutter_animate entrance
/// effects, progress dots, and action button.
class _AnimatedFeatureCard extends StatefulWidget {
  const _AnimatedFeatureCard({
    super.key,
    required this.announcement,
    required this.stepNumber,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  final FeatureAnnouncement announcement;
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<_AnimatedFeatureCard> createState() => _AnimatedFeatureCardState();
}

class _AnimatedFeatureCardState extends State<_AnimatedFeatureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final isLast = widget.stepNumber == widget.totalSteps;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon container (pulsing glow) ────────────────
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final glowValue = 0.6 + (_pulseController.value * 0.4);
                  return Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: a.accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: a.accentColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: a.accentColor.withValues(alpha: glowValue * 0.3),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      a.icon,
                      size: 44,
                      color: a.accentColor,
                    ),
                  )
                      .animate()
                      .fadeIn(
                        duration: 400.ms,
                        curve: Curves.easeOut,
                      )
                      .scale(
                        begin: const Offset(0.6, 0.6),
                        end: Offset.zero,
                        duration: 500.ms,
                        curve: Curves.easeOutBack,
                      );
                },
              ),
              const SizedBox(height: 28),

              // ── Card body ─────────────────────────────────────
              _buildAnimatedCard(a, isLast),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCard(FeatureAnnouncement a, bool isLast) {
    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DesignColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: a.accentColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: a.accentColor.withValues(alpha: 0.08),
            blurRadius: 48,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress dots + skip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: List.generate(
                  widget.totalSteps,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < widget.stepNumber
                            ? a.accentColor
                            : DesignColors.darkTextTertiary
                                .withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onSkip,
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
          const SizedBox(height: 20),

          // Title
          Text(
            a.title,
            style: const TextStyle(
              color: DesignColors.darkTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          // Description
          Text(
            a.description,
            style: const TextStyle(
              color: DesignColors.darkTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),

          // Action button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: GradientButton(
              label: a.actionLabel ?? (isLast ? 'Got it' : 'Next'),
              onPressed: widget.onNext,
              height: 48,
              borderRadius: 12,
              gradient: [a.accentColor, a.accentColor.withValues(alpha: 0.8)],
            ),
          ),
        ],
      ),
    );

    // Apply entrance animation based on type
    switch (a.animationType) {
      case FeatureAnimationType.slideUp:
        return card
            .animate()
            .slideY(begin: 0.3, duration: 500.ms, curve: Curves.easeOutCubic)
            .fadeIn(duration: 500.ms);
      case FeatureAnimationType.scaleIn:
        return card
            .animate()
            .scale(
              begin: const Offset(0.85, 0.85),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: 400.ms);
      case FeatureAnimationType.slideFromLeft:
        return card
            .animate()
            .slideX(
              begin: -0.4,
              duration: 500.ms,
              curve: Curves.easeOutCubic,
            )
            .fadeIn(duration: 500.ms);
      case FeatureAnimationType.slideFromRight:
        return card
            .animate()
            .slideX(
              begin: 0.4,
              duration: 500.ms,
              curve: Curves.easeOutCubic,
            )
            .fadeIn(duration: 500.ms);
      case FeatureAnimationType.bounceIn:
        return card
            .animate()
            .scale(
              begin: const Offset(0.5, 0.5),
              duration: 600.ms,
              curve: Curves.elasticOut,
            )
            .fadeIn(duration: 500.ms);
    }
  }
}
