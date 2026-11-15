import 'dart:async';

import 'package:flutter/material.dart';

import 'package:axon_pos/core/services/haptic_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/motion.dart' show reducedMotion;
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/features/home/domain/home_quick_actions.dart';

/// Small caps label that heads a group on Home. One style for every group so
/// the page reads as one calm column.
class HomeGroupLabel extends StatelessWidget {
  const HomeGroupLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: DesignSpacing.xs,
        bottom: DesignSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: TextStyle(
                  color: palette.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A row of 3 or 4 shortcuts under Start a sale. Each is a tile with a tinted
/// icon and one short word, at least 48 px tall to tap.
class HomeQuickActionsRow extends StatelessWidget {
  const HomeQuickActionsRow({
    super.key,
    required this.actions,
    required this.accent,
    required this.onOpen,
  });

  final List<HomeQuickAction> actions;
  final Color accent;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    // Equal-height tiles even when one label wraps at a large text size. The
    // page scrolls, so the row needs its own height to stretch to.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: DesignSpacing.sm),
            Expanded(
              child: _QuickTile(
                action: actions[i],
                accent: accent,
                onTap: () {
                  unawaited(HapticService().selection());
                  onOpen(actions[i].path);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.action,
    required this.accent,
    required this.onTap,
  });

  final HomeQuickAction action;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignSpacing.xs,
              vertical: DesignSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: palette.isDark ? 0.2 : 0.14),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: Icon(action.icon, size: 19, color: accent),
                ),
                const SizedBox(height: DesignSpacing.sm),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the hero card looks like before any figure is known: the same card,
/// same height, grey blocks where the numbers go. Replaces a flash of zeros.
class HomeTakingsSkeleton extends StatelessWidget {
  const HomeTakingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      label: 'Loading today\'s sales',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          border: Border.all(color: palette.line),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerWidget(width: 84, height: 12),
            SizedBox(height: 14),
            ShimmerWidget(width: 190, height: 34, borderRadius: 10),
            SizedBox(height: 14),
            ShimmerWidget(width: 230, height: 11),
            SizedBox(height: 18),
            ShimmerWidget(width: double.infinity, height: 6, borderRadius: 6),
          ],
        ),
      ),
    );
  }
}

/// The "More for today" fold. Closed by default so the page opens on the figure,
/// the Start a sale button and what needs doing; one tap opens the rest (profit,
/// the daily brief, news and tips for the shop).
class HomeMoreForToday extends StatefulWidget {
  const HomeMoreForToday({
    super.key,
    required this.children,
    required this.accent,
    this.initiallyExpanded = false,
  });

  final List<Widget> children;
  final Color accent;
  final bool initiallyExpanded;

  @override
  State<HomeMoreForToday> createState() => _HomeMoreForTodayState();
}

class _HomeMoreForTodayState extends State<HomeMoreForToday> {
  late bool _open = widget.initiallyExpanded;

  void _toggle() {
    unawaited(HapticService().selection());
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final palette = SignInPalette.of(context);
    final still = reducedMotion(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: 'More for today',
          excludeSemantics: true,
          onTap: _toggle,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            child: InkWell(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.xs,
                  vertical: DesignSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'More for today',
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _open ? 'Show less' : 'Show',
                        style: TextStyle(
                          color: widget.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration:
                            still ? Duration.zero : const Duration(milliseconds: 220),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: widget.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: still ? Duration.zero : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.children.length; i++) ...[
                      if (i > 0) const SizedBox(height: DesignSpacing.md),
                      widget.children[i],
                    ],
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
