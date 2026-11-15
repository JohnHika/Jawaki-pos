import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart' show reducedMotion;
import '../../../../core/widgets/motion_kit.dart' show BreathingGlow, PopIn;

/// One place the bottom bar (phone) and the side rail (tablet / till terminal)
/// can take the user. Both bars draw the same list, so a shop's layout and
/// order follow it across devices.
class NavDestination {
  const NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    this.badge = 0,
    this.primary = false,
    this.semanticLabel,
    this.iconBuilder,
    this.itemKey,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;

  /// A count shown on the icon (0 shows nothing).
  final int badge;

  /// A raised, solid tile that is found by its shape (the AI assistant).
  final bool primary;
  final String? semanticLabel;

  /// Draws a custom mark instead of [icon] (the AI mark with the shop logo).
  final Widget Function(bool selected)? iconBuilder;
  final Key? itemKey;
}

const double kFloatingNavHeight = 66;
const double _kSlotIconBox = 44;

/// The phone's bottom bar: a floating, softly lifted bar with a light that
/// slides to the chosen tab, an icon that morphs from outline to filled, and a
/// label that warms up. Every tab is at least 48 high and a fifth of the width.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.moreKey,
    this.moreSelected = false,
    this.onMore,
  });

  final List<NavDestination> items;

  /// Index into [items] of the current tab, or -1 when none (or More) is lit.
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// When set, a More tab is added after [items].
  final VoidCallback? onMore;
  final Key? moreKey;
  final bool moreSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasMore = onMore != null;
    final slots = items.length + (hasMore ? 1 : 0);
    final litSlot = selectedIndex >= 0
        ? selectedIndex
        : (moreSelected && hasMore ? items.length : -1);
    final litIsPrimary =
        litSlot >= 0 && litSlot < items.length && items[litSlot].primary;
    final still = reducedMotion(context);

    return Container(
      color: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: kFloatingNavHeight,
          decoration: BoxDecoration(
            color: isDark ? DesignColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorderLight,
            ),
            boxShadow: [
              ...DesignShadows.soft(isDark),
              if (isDark)
                const BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final slotWidth = box.maxWidth / slots;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The light that slides to the chosen tab.
                  AnimatedPositioned(
                    duration: still ? Duration.zero : DesignAnimation.normal,
                    curve: Curves.easeOutCubic,
                    left: (litSlot < 0 ? 0 : litSlot) * slotWidth,
                    top: 0,
                    bottom: 0,
                    width: slotWidth,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: DesignAnimation.fast,
                        opacity: litSlot < 0 || litIsPrimary ? 0 : 1,
                        child: const _SlidingLight(),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        SizedBox(
                          width: slotWidth,
                          child: KeyedSubtree(
                            key: items[i].itemKey,
                            child: _BarSlot(
                              destination: items[i],
                              selected: selectedIndex == i,
                              onTap: () => onSelect(i),
                            ),
                          ),
                        ),
                      if (hasMore)
                        SizedBox(
                          width: slotWidth,
                          child: KeyedSubtree(
                            key: moreKey,
                            child: _BarSlot(
                              destination: const NavDestination(
                                icon: Icons.apps_outlined,
                                activeIcon: Icons.apps_rounded,
                                label: 'More',
                                path: '',
                              ),
                              selected: moreSelected && selectedIndex < 0,
                              onTap: onMore!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A soft accent glow with a short bright edge on top, like a lit tab.
class _SlidingLight extends StatelessWidget {
  const _SlidingLight();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    DesignColors.accent.withValues(alpha: isDark ? 0.26 : 0.18),
                    DesignColors.accent.withValues(alpha: isDark ? 0.06 : 0.03),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: Container(
            width: 22,
            height: 3.5,
            decoration: const BoxDecoration(
              color: DesignColors.accent,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarSlot extends StatelessWidget {
  const _BarSlot({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (destination.primary) {
      return _PrimaryTile(
        destination: destination,
        selected: selected,
        onTap: onTap,
        isDark: isDark,
      );
    }
    final idle =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final color = selected ? DesignColors.accent : idle;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.semanticLabel ?? destination.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NavMorphIcon(
                destination: destination,
                selected: selected,
                color: color,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: DesignAnimation.fast,
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: selected ? 0.1 : 0,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                  child: Text(destination.label, maxLines: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outline → filled icon that springs on selection, with an optional count.
class NavMorphIcon extends StatelessWidget {
  const NavMorphIcon({
    super.key,
    required this.destination,
    required this.selected,
    required this.color,
    this.size = 23,
  });

  final NavDestination destination;
  final bool selected;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    final data = selected ? destination.activeIcon : destination.icon;
    Widget icon = AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 360),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: RotationTransition(
          turns: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: destination.iconBuilder != null
          ? KeyedSubtree(
              key: ValueKey('custom-$selected'),
              child: destination.iconBuilder!(selected))
          : TweenAnimationBuilder<Color?>(
              key: ValueKey(data.codePoint),
              tween: ColorTween(end: color),
              duration: DesignAnimation.fast,
              builder: (_, c, __) => Icon(data, size: size, color: c ?? color),
            ),
    );
    icon = AnimatedScale(
      scale: selected ? 1.12 : 1,
      duration: still ? Duration.zero : DesignAnimation.fast,
      curve: Curves.easeOutBack,
      child: icon,
    );
    return SizedBox(
      width: _kSlotIconBox,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          icon,
          if (destination.badge > 0)
            Positioned(
              top: -3,
              right: 2,
              child: _Badge(count: destination.badge),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopIn(
      beginScale: 0.3,
      child: Container(
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: DesignColors.error,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? DesignColors.darkSurface : Colors.white,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised assistant tile: it breathes, and glows when chosen.
class _PrimaryTile extends StatelessWidget {
  const _PrimaryTile({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: destination.semanticLabel ?? destination.label,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: -14,
                child: BreathingGlow(
                  radius: 18,
                  child: AnimatedContainer(
                    duration: DesignAnimation.fast,
                    curve: DesignAnimation.smooth,
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: selected
                          ? DesignColors.accent
                          : (isDark
                              ? DesignColors.darkSurfaceElevated
                              : Colors.white),
                      borderRadius: BorderRadius.circular(27),
                      border: selected
                          ? null
                          : Border.all(
                              color: isDark
                                  ? DesignColors.darkBorder
                                  : DesignColors.surfaceBorder,
                              width: 1.2,
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: DesignColors.accent
                              .withValues(alpha: selected ? 0.35 : 0.0),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                        if (!isDark && !selected)
                          const BoxShadow(
                            color: Color(0x228A6B45),
                            blurRadius: 14,
                            offset: Offset(0, 5),
                          ),
                      ],
                    ),
                    child: Center(
                      child: destination.iconBuilder?.call(selected) ??
                          Icon(destination.activeIcon,
                              color: selected
                                  ? Colors.white
                                  : DesignColors.accent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double kSideRailWidth = 92;
const double _kRailItemHeight = 66;

/// The tablet / till-terminal navigation: a slim rail down the left edge with
/// every destination (no More sheet), a light that slides between them, and
/// Settings pinned at the bottom. Large touch targets for a counter.
class SideNavRail extends StatelessWidget {
  const SideNavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.settings,
    required this.settingsSelected,
    required this.onSettings,
    this.header,
  });

  final List<NavDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final NavDestination settings;
  final bool settingsSelected;
  final VoidCallback onSettings;

  /// Shown above the destinations (the shop mark).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final still = reducedMotion(context);
    final railBg = isDark ? DesignColors.darkBg : DesignColors.surfaceMuted;

    return Container(
      width: kSideRailWidth,
      decoration: BoxDecoration(
        color: railBg,
        border: Border(
          right: BorderSide(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            if (header != null) ...[
              const SizedBox(height: DesignSpacing.sm),
              header!,
              const SizedBox(height: DesignSpacing.sm),
            ],
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: items.length * _kRailItemHeight,
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration:
                            still ? Duration.zero : DesignAnimation.normal,
                        curve: Curves.easeOutCubic,
                        top: (selectedIndex < 0 ? 0 : selectedIndex) *
                            _kRailItemHeight,
                        left: 8,
                        right: 8,
                        height: _kRailItemHeight,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: DesignAnimation.fast,
                            opacity: selectedIndex < 0 ? 0 : 1,
                            child: const _RailLight(),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            SizedBox(
                              height: _kRailItemHeight,
                              child: KeyedSubtree(
                                key: items[i].itemKey,
                                child: _RailItem(
                                  destination: items[i],
                                  selected: selectedIndex == i,
                                  onTap: () => onSelect(i),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: isDark
                  ? DesignColors.darkBorder
                  : DesignColors.surfaceBorder,
            ),
            SizedBox(
              height: _kRailItemHeight + 6,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: KeyedSubtree(
                  key: settings.itemKey,
                  child: _RailItem(
                    destination: settings,
                    selected: settingsSelected,
                    onTap: onSettings,
                    tintWhenSelected: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailLight extends StatelessWidget {
  const _RailLight();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              DesignColors.accent.withValues(alpha: isDark ? 0.28 : 0.20),
              DesignColors.accent.withValues(alpha: isDark ? 0.07 : 0.04),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 3.5,
            height: 24,
            decoration: const BoxDecoration(
              color: DesignColors.accent,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.tintWhenSelected = false,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final bool tintWhenSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idle =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final color = selected ? DesignColors.accent : idle;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.semanticLabel ?? destination.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: tintWhenSelected && selected
              ? DesignColors.accent.withValues(alpha: isDark ? 0.16 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NavMorphIcon(
                  destination: destination,
                  selected: selected,
                  color: color,
                  size: 24,
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedDefaultTextStyle(
                      duration: DesignAnimation.fast,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: color,
                      ),
                      child: Text(destination.label, maxLines: 1),
                    ),
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
