import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/motion.dart';
import '../widgets/motion_kit.dart';

/// ═══════════════════════════════════════════════════════════════
/// AXON POS DESIGN SYSTEM — v2
/// Near-black terminal aesthetic. One accent color used with intent,
/// not painted across every surface. No default gradients — depth
/// comes from elevation, borders and grain, not diagonal color washes.
/// ═══════════════════════════════════════════════════════════════

// ─── Typography ────────────────────────────────────────────────────
// Sora: geometric, confident display face for headings and brand.
// JetBrains Mono: every number in this app (prices, totals, metrics,
// receipts) renders in monospace — tabular figures that align in a
// column and read unambiguously at arm's length on a shop counter.
class DesignType {
  static TextTheme get textTheme => TextTheme(
        displayLarge: GoogleFonts.sora(fontWeight: FontWeight.w800),
        displayMedium: GoogleFonts.sora(fontWeight: FontWeight.w700),
        headlineLarge: GoogleFonts.sora(fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.sora(fontWeight: FontWeight.w700),
        headlineSmall: GoogleFonts.sora(fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.sora(fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.sora(fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.sora(fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
        bodyMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
        bodySmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w400),
        labelLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        labelMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        labelSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
      );

  static TextStyle get display => GoogleFonts.sora();
  static TextStyle get body => GoogleFonts.plusJakartaSans();

  // ── Inline chat type scale ──────────────────────────────────────
  // Chat surfaces (AI assistant, pending-turn cards, todo checklist) render
  // dense inline text; these tokens pin their sizes so screens stop passing
  // raw numbers to TextStyle(fontSize:).
  /// Small metadata/label text (badges, checklist headers).
  static const double chatMeta = 11;

  /// Standard chat body text (bubbles, questions, buttons).
  static const double chatBody = 14;

  /// Secondary chat text (option descriptions, hints).
  static const double chatSecondary = 12;

  /// Every monetary or counted figure in the app uses this.
  static TextStyle numeric({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing ?? -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

// ─── Axon Brand Color Palette ─────────────────────────────────────
// Near-black canvas from the logo's own dark field. Signal orange is
// the single accent — used for the one thing on a screen that should
// pull the eye (a primary action, the active nav tab, a live total).
// Indigo remains as the brand identifier (logo mark, splash) but does
// not carry interactive weight the way orange does.
class DesignColors {
  // Brand tokens now alias the orange accent so every legacy "brand" use matches the one-accent palette
  static const Color brand = Color(0xFFFF7A33);
  static const Color brandLight = Color(0xFFFFA166);
  static const Color brandDark = Color(0xFFE0611E);
  static const Color brandSubtle = Color(0xFF2A1B10);

  // Accent — signal orange, the app's one interactive color
  static const Color accent = Color(0xFFFF7A33);
  static const Color accentLight = Color(0xFFFFA166);
  static const Color accentDark = Color(0xFFE0611E);
  static const Color accentSubtle = Color(0xFF2A1B10);

  // Success
  static const Color success = Color(0xFF3DDC84);
  static const Color successLight = Color(0xFF6BE6A3);
  static const Color successSubtle = Color(0xFF102A1B);

  // Error
  static const Color error = Color(0xFFFF5C5C);
  static const Color errorSubtle = Color(0xFF2E1414);

  // Warning
  static const Color warning = Color(0xFFFFC24B);
  static const Color warningSubtle = Color(0xFF2E2410);

  // Info — kept distinct from both brand and accent
  static const Color info = Color(0xFF4FC3F7);
  static const Color infoSubtle = Color(0xFF102530);

  // Light-mode surfaces (used only where a screen forces light mode,
  // e.g. printable receipts) — warm paper, not cold gray.
  static const Color surface = Color(0xFFFFFDFA);
  static const Color surfaceMuted = Color(0xFFF8F3EC);
  static const Color surfaceSubtle = Color(0xFFF1E9DE);
  static const Color surfaceBorder = Color(0xFFE6DDCF);
  static const Color surfaceBorderLight = Color(0xFFEFE8DC);
  // Peach wash behind hero areas / selected chips in light mode.
  static const Color peach = Color(0xFFFFEFE2);

  // Light-mode text
  static const Color textPrimary = Color(0xFF1A1610);
  static const Color textSecondary = Color(0xFF6B6455);
  static const Color textTertiary = Color(0xFF8C8473);
  static const Color textInverse = Color(0xFF0B0A0F);
  static const Color textOnBrand = Color(0xFFFFFFFF);

  // Payment method colors — kept conventional, meaning must read instantly
  static const Color mpesa = Color(0xFF3DDC84);
  static const Color pesapal = Color(0xFF4FC3F7);
  static const Color touristtap = Color(0xFFFFC24B);
  static const Color cash = Color(0xFFC98A4B);
  static const Color credit = Color(0xFF7C6CFF);

  // Dark mode — true near-black, not navy. Flat, no gradient wash.
  static const Color darkBg = Color(0xFF0B0A0F);
  static const Color darkSurface = Color(0xFF15131C);
  static const Color darkSurfaceElevated = Color(0xFF1F1C29);
  static const Color darkBorder = Color(0xFF2E2A3D);
  static const Color darkTextPrimary = Color(0xFFF5F3ED);
  static const Color darkTextSecondary = Color(0xFFA8A3B8);
  static const Color darkTextTertiary = Color(0xFF6E6A80);

  // Glass — flat translucent fills, no gradient
  static const Color glassWhite = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color glassDark = Color(0x1F15131C);
  static const Color glassDarkBorder = Color(0x1DFF7A33);
}

// ─── Spacing & Sizing Scale ──────────────────────────────────────
class DesignSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
  static const double massive = 64;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 24;
  static const double radiusFull = 1000;

  static const EdgeInsets paddingScreen =
      EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  static const EdgeInsets paddingCard = EdgeInsets.all(16);
  static const EdgeInsets paddingCardLg = EdgeInsets.all(20);
}

// ─── Shadows ──────────────────────────────────────────────────────
class DesignShadows {
  /// Soft, warm lift for white cards on the cream light-mode page. Dark mode
  /// stays flat (borders carry the separation there).
  static List<BoxShadow> soft(bool isDark) => isDark
      ? const []
      : const [
          BoxShadow(
              color: Color(0x178A6B45),
              blurRadius: 22,
              spreadRadius: -2,
              offset: Offset(0, 8)),
          BoxShadow(
              color: Color(0x0D8A6B45), blurRadius: 3, offset: Offset(0, 1)),
        ];
}

// ─── Animations ───────────────────────────────────────────────────
class DesignAnimation {
  static const Duration fastest = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 250);
  static const Duration normal = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration slower = Duration(milliseconds: 700);
  static const Duration slowest = Duration(milliseconds: 1000);

  static const Curve defaultCurve = Curves.easeInOut;
  static const Curve spring = Curves.easeOutBack;
  static const Curve smooth = Curves.easeOutCubic;
  static const Curve bounce = Curves.elasticOut;

  // ── Interaction & entrance micro-motion ─────────────────────────
  // Press-in scale feedback: short and snappy so it reads as physical
  // weight, not as an "animation" (see GradientButton / GlassCard).
  static const Duration pressScale = Duration(milliseconds: 120);
  static const double pressScaleAmount = 0.96;

  // Stagger interval between consecutive first-mount list entrances
  // (see StaggeredItem in core/widgets/motion.dart).
  static const Duration staggerInterval = Duration(milliseconds: 40);

  static const Cubic standardCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Cubic decelerateCurve = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Cubic accelerateCurve = Cubic(0.4, 0.0, 1.0, 1.0);
}

// ═══════════════════════════════════════════════════════════════
//  NAVIGATION TRANSITIONS
//  The app-wide page transition is the Material 3 Expressive
//  "fade forwards" motion (new page fades in and slides up while the
//  previous page recedes), tuned to [DesignAnimation.fast] (250ms) —
//  snappier than the SDK default 450ms so POS taps feel instant.
//  Installed via ThemeData.pageTransitionsTheme (see app_theme.dart).
// ═══════════════════════════════════════════════════════════════

/// [FadeForwardsPageTransitionsBuilder] with the app's 250ms pacing.
/// The SDK builder hardcodes a 450ms duration; the theme duration API is
/// designed to be overridden by subclasses (reverse duration follows
/// [transitionDuration] on the base class automatically).
class _FastFadeForwardsPageTransitionsBuilder
    extends FadeForwardsPageTransitionsBuilder {
  const _FastFadeForwardsPageTransitionsBuilder();

  @override
  Duration get transitionDuration => DesignAnimation.fast;
}

class DesignTransitions {
  /// Page-level transition for every MaterialPageRoute/GoRoute push.
  /// Assign to `ThemeData.pageTransitionsTheme` in both light+dark.
  static const PageTransitionsTheme pageTransitionsTheme =
      PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: _FastFadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: _FastFadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: _FastFadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: _FastFadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: _FastFadeForwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: _FastFadeForwardsPageTransitionsBuilder(),
    },
  );
}

// ═══════════════════════════════════════════════════════════════
//  PREMIUM SHIMMER LOADING EFFECT
// ═══════════════════════════════════════════════════════════════
class ShimmerWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerWidget({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.baseColor,
    this.highlightColor,
  });

  const ShimmerWidget.circular({
    super.key,
    required double size,
    this.baseColor,
    this.highlightColor,
  })  : width = size,
        height = size,
        borderRadius = size / 2;

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion gate: the shimmer is an infinite loop, so it must
    // STOP entirely when the OS "remove animations" setting is on — the
    // placeholder remains as a static highlight (opacity-level motion
    // only, no sweeping gradient). didChangeDependencies re-evaluates
    // when MediaQuery changes, so toggling the setting live also works.
    if (reducedMotion(context)) {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.reset();
      }
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Base colors sit just above the page/surface colors so placeholders
    // read as "skeleton", not as solid accent-colored pills (the old
    // #1A2744 blue read as a filled button against the near-black bg).
    final base = widget.baseColor ??
        (isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceSubtle);
    final highlight = widget.highlightColor ??
        (isDark
            ? DesignColors.darkBorder
            : const Color(0xFFFFFBF5));

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1.0 + _animation.value, 0.0),
              end: Alignment(1.0 + _animation.value, 0.0),
            ),
          ),
        );
      },
    );
  }
}

/// Shimmer loading for product cards
class ProductCardShimmer extends StatelessWidget {
  const ProductCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        side: BorderSide(
            color: DesignColors.surfaceBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                color: Colors.transparent,
              ),
              child: const ShimmerWidget(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 14),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerWidget(width: double.infinity, height: 12),
                  SizedBox(height: 6),
                  ShimmerWidget(width: 80, height: 12),
                  Spacer(),
                  ShimmerWidget(width: 100, height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PRESSABLE CARD — shared press-scale wrapper for tappable cards
//  Wraps a card in a GestureDetector so the surface scales to
//  [DesignAnimation.pressScaleAmount] on press-in and springs back on
//  release. Used by GlassCard (and reusable by other card shells); the
//  card's own tap handling is unchanged.
// ═══════════════════════════════════════════════════════════════
class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale =
        (widget.onTap != null && _pressed && !reducedMotion(context))
            ? DesignAnimation.pressScaleAmount
            : 1.0;

    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _setPressed(true) : null,
      onTapUp: widget.onTap != null ? (_) => _setPressed(false) : null,
      onTapCancel: widget.onTap != null ? () => _setPressed(false) : null,
      child: AnimatedScale(
        duration: DesignAnimation.pressScale,
        curve: DesignAnimation.defaultCurve,
        scale: scale,
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PREMIUM GLASSMORPHISM CARD
// ═══════════════════════════════════════════════════════════════
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final bool animatePress;
  final LinearGradient? gradient;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 12,
    this.blur = 8,
    this.tint,
    this.borderColor,
    this.boxShadow,
    this.onTap,
    this.animatePress = true,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawTint =
        tint ?? (isDark ? DesignColors.glassDark : DesignColors.glassWhite);
    // Light mode has nothing to blur against, and a see-through fill lets the
    // card's own drop shadow show through (muddy grey). Lay it over white.
    final effectiveTint =
        isDark ? rawTint : Color.alphaBlend(rawTint, Colors.white);
    final effectiveBorder = borderColor ??
        (isDark
            ? DesignColors.glassDarkBorder
            : DesignColors.surfaceBorderLight);

    final card = Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        gradient: gradient,
        color: effectiveTint,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: effectiveBorder, width: 1),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : const Color(0xFF8A6B45).withValues(alpha: 0.10),
                blurRadius: isDark ? blur : blur * 2.5,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0xFF8A6B45).withValues(alpha: 0.05),
                blurRadius: blur * 0.5,
                offset: const Offset(0, 2),
              ),
            ],
      ),
      child: child,
    );

    if (onTap != null) {
      final tappableCard = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      );
      return animatePress
          ? PressableCard(onTap: onTap, child: tappableCard)
          : tappableCard;
    }

    return card;
  }
}

// ═══════════════════════════════════════════════════════════════
//  PREMIUM GRADIENT BUTTON
// ═══════════════════════════════════════════════════════════════
class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool expanded;
  final double height;
  final List<Color>? gradient;
  final Color? textColor;
  final double borderRadius;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.expanded = true,
    this.height = 56,
    this.gradient,
    this.textColor,
    this.borderRadius = 12,
  });

  const GradientButton.icon({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    this.expanded = true,
    this.height = 56,
    this.gradient,
    this.textColor,
    this.borderRadius = 12,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = reducedMotion(context);
    final fill = widget.gradient?.first ?? DesignColors.accent;
    final textColor = widget.textColor ??
        (fill.computeLuminance() > 0.5 ? Colors.black : Colors.white);

    // Press-scale: the whole surface compresses to 0.96 on press-in and
    // springs back on release/cancel. 120ms keeps it feeling physical
    // rather than animated; skipped entirely under reduced motion.
    final btn = AnimatedScale(
      duration: DesignAnimation.pressScale,
      curve: DesignAnimation.defaultCurve,
      scale: (_isPressed && !reduced)
          ? DesignAnimation.pressScaleAmount
          : 1.0,
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        height: widget.height,
        width: widget.expanded ? double.infinity : null,
        // A compact (non-expanded) button hugs its content, so without side
        // padding the icon and label sit flush against the button edge.
        padding: widget.expanded
            ? null
            : const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: _isPressed ? _darken(fill, 0.12) : fill,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTapDown: widget.onPressed != null && !widget.isLoading
                ? (_) => setState(() => _isPressed = true)
                : null,
            onTapUp: widget.onPressed != null && !widget.isLoading
                ? (_) => setState(() => _isPressed = false)
                : null,
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: widget.isLoading ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Center(
              child: widget.isLoading
                  ? _LoadingDots(color: textColor)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: textColor, size: 20),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    // Unavailable (no handler, not merely busy): dim it so it never reads as
    // a live call to action.
    final disabled = widget.onPressed == null && !widget.isLoading;
    if (disabled) {
      return Opacity(opacity: 0.45, child: btn);
    }

    // Loading pulse: a soft looping breathe while [isLoading] is true.
    // Reduced-motion gate: when "remove animations" is on the loop never
    // starts — the button shows its final (fully opaque) state and the
    // loading state is communicated by the dots/label alone.
    if (!widget.isLoading || reduced) return btn;

    return btn.animateEntrance(
      context,
      effects: () => [
        const FadeEffect(
          begin: 0.6,
          end: 1.0,
          duration: DesignAnimation.slow,
          curve: Curves.easeInOut,
        ),
      ],
      onPlay: (controller) => controller.repeat(reverse: true),
    );
  }

  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}

// ═══════════════════════════════════════════════════════════════
//  LOADING DOTS
// ═══════════════════════════════════════════════════════════════
class _LoadingDots extends StatefulWidget {
  final Color? color;
  const _LoadingDots({this.color});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.15;
            final value = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final scale =
                0.4 + 0.6 * (1.0 - (value * 4 - 2).abs().clamp(0.0, 1.0));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.color ?? Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  METRIC CARD — Premium Dashboard Stat
// ═══════════════════════════════════════════════════════════════
class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;
  final double? trendValue;
  final bool showChart;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
    this.trendValue,
    this.showChart = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trendColor = context.readable(trendValue != null
        ? (trendValue! >= 0 ? DesignColors.success : DesignColors.error)
        : DesignColors.textTertiary);
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;

    return FadeSlideIn(
        distance: 12,
        child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
            boxShadow: DesignShadows.soft(isDark),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 16),
                    const Spacer(),
                    if (trend != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            trendValue != null && trendValue! >= 0
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: trendColor,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            trend!,
                            style: DesignType.numeric(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: trendColor,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountUpText(
                    value,
                    style: DesignType.numeric(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? DesignColors.darkTextTertiary
                        : DesignColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: color),
          ),
        ],
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
//  STATUS BADGE
// ═══════════════════════════════════════════════════════════════
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final IconData? icon;
  final bool isActive;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.textColor,
    this.icon,
    this.isActive = false,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return PopIn(
        beginScale: 0.85,
        duration: const Duration(milliseconds: 380),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          if (icon != null) ...[
            Icon(icon, color: textColor ?? context.readable(color), size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor ?? context.readable(color),
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
//  SECTION HEADER
// ═══════════════════════════════════════════════════════════════
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final subtitleColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return FadeSlideIn(
        from: SlideFrom.left,
        distance: 10,
        child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            PopIn(
                delay: const Duration(milliseconds: 120),
                child: Icon(icon, color: DesignColors.accent, size: 18)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: subtitleColor),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing!,
              ),
            ),
        ],
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═══════════════════════════════════════════════════════════════
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.refresh_rounded,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = iconColor ??
        (isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary);
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final subtitleColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              child: Floating(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.08 : 0.10),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: color.withValues(alpha: 0.14)),
                  ),
                  child: Icon(icon,
                      size: 34, color: color.withValues(alpha: 0.65)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              FadeSlideIn(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  subtitle!,
                  style: TextStyle(fontSize: 14, color: subtitleColor),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 300),
                child: GradientButton(
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction,
                  height: 44,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact warning for cached content that could not be refreshed.
class InlineRetryNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const InlineRetryNotice({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: DesignColors.warning, size: 18),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: DesignSpacing.xs),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ANIMATED PAGE TRANSITION WRAPPER
// ═══════════════════════════════════════════════════════════════
class PageTransition extends StatelessWidget {
  final Widget child;
  final bool forward;

  const PageTransition({
    super.key,
    required this.child,
    this.forward = true,
  });

  /// Slide-fade motion of [slideIn] expressed as a GoRouter
  /// [CustomTransitionPage], so ShellRoute subroute pushes (detail
  /// screens) get the same reveal without leaving the router's page
  /// model. Usage in app_router.dart:
  ///
  /// ```dart
  /// pageBuilder: (context, state) => PageTransition.slideInPage(
  ///   ProductDetailScreen(productId: id),
  ///   key: state.pageKey,
  /// ),
  /// ```
  static CustomTransitionPage<T> slideInPage<T extends Object?>(
    Widget page, {
    LocalKey? key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: page,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.03, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;

        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var fadeTween =
            Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
    );
  }

  static Route<dynamic> slideIn(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.03, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;

        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var fadeTween =
            Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

// ═══════════════════════════════════════════════════════════════
//  PAGE CONTAINER — Consistent screen layout
// ═══════════════════════════════════════════════════════════════
class PageContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool withScroll;
  final Color? backgroundColor;

  const PageContainer({
    super.key,
    required this.child,
    this.padding,
    this.withScroll = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? DesignColors.darkBg : DesignColors.surfaceMuted);

    if (withScroll) {
      return SafeArea(
        top: false,
        child: Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: padding ?? DesignSpacing.paddingScreen,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: FadeSlideIn(distance: 10, child: child),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        color: bg,
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ANIMATED COUNTER
// ═══════════════════════════════════════════════════════════════
class AnimatedCounter extends ImplicitlyAnimatedWidget {
  final int value;
  final TextStyle? style;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    super.duration = const Duration(milliseconds: 500),
  });

  @override
  ImplicitlyAnimatedWidgetState<AnimatedCounter> createState() =>
      _AnimatedCounterState();
}

class _AnimatedCounterState extends AnimatedWidgetBaseState<AnimatedCounter> {
  IntTween? _valueTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _valueTween = visitor(
      _valueTween,
      widget.value,
      (value) => IntTween(begin: value),
    ) as IntTween?;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_valueTween?.evaluate(animation) ?? widget.value}',
      style: widget.style,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PULSE ANIMATION WRAPPER
// ═══════════════════════════════════════════════════════════════
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final bool active;
  final double scale;

  const PulseAnimation({
    super.key,
    required this.child,
    this.active = true,
    this.scale = 1.05,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) =>
          Transform.scale(scale: _animation.value, child: child),
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  QUICK ACTION TILE (Home screen grid items)
// ═══════════════════════════════════════════════════════════════
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final subtitleColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;

    return PopIn(
        beginScale: 0.9,
        duration: const Duration(milliseconds: 420),
        child: TapScale(
        enabled: onTap != null,
        child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: border),
            boxShadow: DesignShadows.soft(isDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11, color: subtitleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    )));
  }
}

// ═══════════════════════════════════════════════════════════════
//  PAYMENT METHOD CHIP
// ═══════════════════════════════════════════════════════════════
class PaymentChip extends StatelessWidget {
  final String method;
  final bool isSelected;
  final VoidCallback? onTap;

  /// Small read-only tag for list rows: always tinted with the method colour,
  /// tighter padding, no outline fighting the card border.
  final bool compact;

  const PaymentChip({
    super.key,
    required this.method,
    this.isSelected = false,
    this.onTap,
    this.compact = false,
  });

  Color get _color {
    switch (method.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '')) {
      case 'MPESA':
        return DesignColors.mpesa;
      case 'PESAPAL':
        return DesignColors.pesapal;
      case 'TOURISTTAP':
        return DesignColors.touristtap;
      case 'CASH':
        return DesignColors.cash;
      case 'CREDIT':
        return DesignColors.credit;
      default:
        return DesignColors.brand;
    }
  }

  IconData get _icon {
    switch (method.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '')) {
      case 'MPESA':
        return Icons.phone_android_rounded;
      case 'PESAPAL':
        return Icons.payments_rounded;
      case 'TOURISTTAP':
        return Icons.nfc_rounded;
      case 'CASH':
        return Icons.money_rounded;
      case 'CREDIT':
        return Icons.credit_card_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tinted = isSelected || compact;
    // The unselected look used fixed light-theme colours: near-black text on a
    // dark card was unreadable. Pick the text/border for the active theme.
    final idleText =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final idleBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return TapScale(
      enabled: onTap != null,
      scale: 0.95,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: tinted ? _color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 8 : 12),
          border: Border.all(
            color: tinted ? _color.withValues(alpha: 0.4) : idleBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: _color, size: compact ? 13 : 16),
            SizedBox(width: compact ? 4 : 6),
            Text(
              method,
              style: TextStyle(
                color: tinted ? _color : idleText,
                fontWeight: tinted ? FontWeight.w700 : FontWeight.w500,
                fontSize: compact ? 11 : 13,
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
//  LIST CARD — Consistent list item
// ═══════════════════════════════════════════════════════════════
class ListCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accentColor;

  const ListCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final subtitleColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final chevronColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return FadeSlideIn(
        distance: 10,
        child: TapScale(
        enabled: onTap != null,
        child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            boxShadow: DesignShadows.soft(isDark),
            // Every other list row/card in the app is rounded; this one was
            // square, with a ripple that spilled past its corners.
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    color: chevronColor, size: 20),
            ],
          ),
        ),
      ),
    )));
  }
}

// ═══════════════════════════════════════════════════════════════
//  GROUPED SETTINGS CARD
//  A single rounded surface holding several related rows separated by
//  thin dividers, instead of each row being its own separately-boxed
//  card — the pattern modern iOS/Android settings screens use to signal
//  "these options belong together."
// ═══════════════════════════════════════════════════════════════
class GroupedCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  /// Hairline between rows. Turn off when the children are one logical row
  /// split in two (e.g. a person row plus its role badges).
  final bool showDividers;

  /// Left inset of the hairline: 60 aligns under an icon badge's text; use a
  /// small value for rows that start with plain text.
  final double dividerIndent;

  const GroupedCard({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 20),
    this.showDividers = true,
    this.dividerIndent = 60,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return FadeSlideIn(
        distance: 14,
        child: Container(
      margin: margin,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
            boxShadow: DesignShadows.soft(isDark),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (showDividers && i != children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: dividerIndent,
                color: border.withValues(alpha: 0.6),
              ),
          ],
        ],
      ),
    ));
  }
}

/// A single row inside a [GroupedCard]: rounded icon badge, title/subtitle,
/// and a trailing widget or chevron. Distinct from [ListCard] (which is a
/// separately-boxed standalone row used elsewhere in the app) — this one
/// is meant to sit flush against its siblings inside the same card.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;

  /// Lines the subtitle may wrap to before truncating (2 by default; raise it
  /// for rows whose description must be read in full, e.g. option pickers).
  final int subtitleMaxLines;

  /// Show a trailing chevron on tappable rows without a [trailing] widget.
  /// Turn off for choice lists (theme, language) where tapping selects rather
  /// than navigates, so unselected options don't look like links.
  final bool showChevron;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool enabled;

  const SettingsRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.showChevron = true,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedIconColor =
        iconColor ?? (isDestructive ? DesignColors.error : DesignColors.accent);
    final titleColor = isDestructive
        ? DesignColors.error
        : (isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary);
    final subtitleColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final chevronColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                PopIn(
                  beginScale: 0.7,
                  duration: const Duration(milliseconds: 420),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: resolvedIconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: resolvedIconColor, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style:
                              TextStyle(fontSize: 12.5, color: subtitleColor),
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  // Content-sized (capped) so the title/subtitle column keeps
                  // the remaining width instead of splitting the row 50/50 with
                  // a switch or badge.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: trailing!,
                  ),
                ] else if (onTap != null && showChevron)
                  Icon(Icons.chevron_right_rounded,
                      color: chevronColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header used above a [GroupedCard] to label the section it belongs to —
/// smaller and more subdued than a screen title, matching the native
/// settings-app convention of quiet all-caps or semi-bold section labels.
class SettingsGroupLabel extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;

  const SettingsGroupLabel(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 10),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeSlideIn(
      from: SlideFrom.left,
      distance: 8,
      child: Padding(
        padding: padding,
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: isDark
                ? DesignColors.darkTextTertiary
                : DesignColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  MODAL SHEET SCAFFOLD (compact)
//  Drag handle + title + content, for the smaller bottom sheets that
//  don't need GlassBottomSheet's fixed-height/back-button treatment.
// ═══════════════════════════════════════════════════════════════
class SettingsSheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SettingsSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final subtitleColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: subtitleColor)),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SETTINGS-STYLE ALERT DIALOG SHELL
//  A rounded, theme-aware AlertDialog wrapper matching the app's radius
//  scale (16 for the shell, 12 for buttons) instead of the sharp-cornered
//  Material default.
// ═══════════════════════════════════════════════════════════════
class SettingsDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const SettingsDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopIn(
        beginScale: 0.9,
        duration: const Duration(milliseconds: 340),
        child: AlertDialog(
      backgroundColor: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color:
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
        ),
      ),
      content: content,
      actions: actions,
    ));
  }
}

/// A dialog/sheet's primary (filled, accent) action button — matches the
/// rest of the app's single-accent-color convention instead of Material's
/// default `FilledButton` color.
class SettingsPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? color;

  const SettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fill = color ?? DesignColors.accent;
    return TapScale(
        enabled: onPressed != null && !isLoading,
        child: FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor:
            fill.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color:
                    fill.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
//  DIVIDER WITH LABEL
// ═══════════════════════════════════════════════════════════════
class LabelDivider extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry? padding;

  const LabelDivider({
    super.key,
    required this.label,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final textColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: line)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  CONFIRMATION DIALOG (Premium)
// ═══════════════════════════════════════════════════════════════
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final titleColor =
          isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
      final messageColor =
          isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
      return PopIn(
        beginScale: 0.88,
        duration: const Duration(milliseconds: 340),
        child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        ),
        backgroundColor:
            isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              delay: const Duration(milliseconds: 140),
              beginScale: 0.3,
              child: Icon(
                Icons.warning_amber_rounded,
                color: confirmColor ?? DesignColors.error,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: messageColor, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(cancelLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor ?? DesignColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ));
    },
  );

  return result ?? false;
}

// ═══════════════════════════════════════════════════════════════
//  GLASS SNACKBAR
// ═══════════════════════════════════════════════════════════════
void showGlassSnackBar(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? color,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            PopIn(
              beginScale: 0.2,
              child: Icon(icon, color: color ?? DesignColors.success, size: 20),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: const Duration(seconds: 3),
      action: actionLabel != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: color ?? DesignColors.brand,
              onPressed: onAction ?? () {},
            )
          : null,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
//  BOTTOM SHEET WRAPPER
// ═══════════════════════════════════════════════════════════════
class GlassBottomSheet {
  /// Returns the same [Future] `showModalBottomSheet` produces, which
  /// resolves once the sheet is dismissed — callers that need to react
  /// after the sheet closes (e.g. refreshing data) can await this.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    double initialSize = 0.5,
    double maxSize = 0.9,
    String title = 'Details',
    bool scrollable = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<T>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      // Keep the sheet header below the Android status bar. The explicit
      // SafeArea below still handles the bottom gesture/navigation inset.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        duration: DesignAnimation.fast,
        curve: DesignAnimation.smooth,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.sizeOf(ctx).height *
                maxSize.clamp(initialSize.clamp(0.45, 0.98), 0.98),
            decoration: BoxDecoration(
              color: isDark ? DesignColors.darkSurface : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? DesignColors.darkTextPrimary
                                : DesignColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark
                      ? DesignColors.darkBorder
                      : DesignColors.surfaceBorder,
                ),
                Expanded(
                  child: scrollable
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: child,
                        )
                      : child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  GRADIENT DEFINITIONS
// ═══════════════════════════════════════════════════════════════
class DesignGradients {
  static const LinearGradient brand = LinearGradient(
    colors: [DesignColors.brandDark, DesignColors.brand, DesignColors.accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surface = LinearGradient(
    colors: [Color(0xFFFAF9F4), Color(0xFFEAF6EF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient darkSurface = LinearGradient(
    colors: [DesignColors.darkBg, DesignColors.darkSurface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// ═══════════════════════════════════════════════════════════════
//  AXON LOGO MARK
//  Renders the Arche Axon hex/node brand mark from
//  assets/images/axon_logo_mark(.svg|_light.svg).
// ═══════════════════════════════════════════════════════════════
class AxonLogoTitle extends StatelessWidget {
  final double logoSize;
  final bool showText;

  const AxonLogoTitle({
    super.key,
    this.logoSize = 34,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/images/axon_logo_mark.svg'
        : 'assets/images/axon_logo_mark_light.svg';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          asset,
          width: logoSize,
          height: logoSize,
          semanticsLabel: 'Counterbase logo',
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          Text(
            'Counterbase',
            style: TextStyle(
              color: isDark
                  ? DesignColors.darkTextPrimary
                  : DesignColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  TENANT BRAND MARK
//  Renders the logged-in company's own uploaded logo once inside the
//  authenticated app (Axon's mark is otherwise the only thing shown,
//  even on a tenant's own dashboard). Falls back to the generic Axon
//  mark when the tenant hasn't uploaded one yet, so this never shows
//  a broken image.
// ═══════════════════════════════════════════════════════════════
class TenantBrandMark extends StatelessWidget {
  final String? logoUrl;
  final double size;

  const TenantBrandMark({super.key, required this.logoUrl, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty) {
      return AxonLogoTitle(logoSize: size);
    }

    // A subtle corner radius reads as barely-rounded at small badge sizes,
    // especially against a bright logo background on a dark app bar — use
    // a proportionally larger radius so it's unmistakably a rounded badge,
    // not a square swatch. Clamped so it never exceeds a perfect circle.
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).brightness == Brightness.dark
            ? DesignColors.darkSurfaceElevated
            : Colors.white,
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? DesignColors.darkBorder
              : DesignColors.surfaceBorder,
        ),
      ),
      child: ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              AxonLogoTitle(logoSize: size * 0.8),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: size * 0.42,
                height: size * 0.42,
                child: const CircularProgressIndicator(strokeWidth: 1.6),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  BRANDED APP BAR
// ═══════════════════════════════════════════════════════════════
class BrandedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showLogo;

  /// Root/tab screens (Dashboard, POS, AI, Customers, Settings) must pass
  /// `false` explicitly. Leaving this to Flutter's automatic Navigator
  /// detection is what previously caused a stray back arrow to appear on
  /// Dashboard even though it's a bottom-nav root with nowhere to "go
  /// back" to — this flag makes the decision explicit per screen instead.
  final bool showBackButton;

  const BrandedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showLogo = true,
    this.showBackButton = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final hasLeading = leading != null || showBackButton;

    return AppBar(
      automaticallyImplyLeading: false,
      leading: leading ??
          (showBackButton ? AppBackButton(color: fg, isDark: isDark) : null),
      centerTitle: false,
      titleSpacing: hasLeading ? 4 : 20,
      toolbarHeight: preferredSize.height,
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surface,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogo) ...[
            const AxonLogoTitle(logoSize: 28),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignType.display.copyWith(
                color: fg,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
      actions: actions,
      shape: Border(
        bottom: BorderSide(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          width: 1,
        ),
      ),
    );
  }
}

/// The one back button every screen uses: a compact bordered square with a
/// 44dp tap target. [onPressed] defaults to popping the current route.
class AppBackButton extends StatelessWidget {
  final Color color;
  final bool isDark;
  final VoidCallback? onPressed;

  /// Fill behind the arrow. Leave null on an app bar; pass the page colour
  /// when the button floats over scrolling content so text never shows
  /// through it.
  final Color? background;
  const AppBackButton({
    super.key,
    required this.color,
    required this.isDark,
    this.onPressed,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    // Center: the AppBar leading slot passes tight 56x60 constraints, which
    // stretched this button into a tall rectangle. 44dp keeps a comfortable
    // tap target while the bordered square stays compact.
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Material(
          color: background ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color:
                  isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed ?? () => Navigator.of(context).maybePop(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.arrow_back_rounded,
                semanticLabel: 'Back',
                color: color,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// For screens written against the dark palette: returns [darkToken] in dark
/// mode and its light-theme counterpart otherwise, so the screen follows the
/// app's Light/Dark setting without being rewritten token by token.
extension ThemedDarkTokens on BuildContext {
  /// A bright semantic colour (success green, warning amber, info sky…) is
  /// fine on dark surfaces but washes out on white. In light mode this
  /// returns a deeper shade of the same hue so text/icons stay readable.
  Color readable(Color c) {
    if (Theme.of(this).brightness == Brightness.dark) return c;
    final hsl = HSLColor.fromColor(c);
    if (hsl.lightness <= 0.45) return c;
    return hsl.withLightness(0.36).withSaturation((hsl.saturation * 0.95).clamp(0.0, 1.0)).toColor();
  }

  Color themed(Color darkToken) {
    if (Theme.of(this).brightness == Brightness.dark) return darkToken;
    if (darkToken == DesignColors.accentSubtle) return DesignColors.peach;
    if (darkToken == DesignColors.darkBg) return DesignColors.surfaceMuted;
    if (darkToken == DesignColors.darkSurface) return Colors.white;
    if (darkToken == DesignColors.darkSurfaceElevated) {
      return DesignColors.surfaceMuted;
    }
    if (darkToken == DesignColors.darkBorder) return DesignColors.surfaceBorder;
    if (darkToken == DesignColors.darkTextPrimary) {
      return DesignColors.textPrimary;
    }
    if (darkToken == DesignColors.darkTextSecondary) {
      return DesignColors.textSecondary;
    }
    if (darkToken == DesignColors.darkTextTertiary) {
      return DesignColors.textTertiary;
    }
    return darkToken;
  }
}
