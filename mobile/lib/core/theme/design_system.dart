import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

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
  // Brand mark — Axon indigo, identity only (logo, splash, About)
  static const Color brand = Color(0xFF7C6CFF);
  static const Color brandLight = Color(0xFF9C90FF);
  static const Color brandDark = Color(0xFF5B4CD6);
  static const Color brandSubtle = Color(0xFF1A1730);

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
  static const Color surface = Color(0xFFFBF9F4);
  static const Color surfaceMuted = Color(0xFFF3F0E8);
  static const Color surfaceSubtle = Color(0xFFEDEADF);
  static const Color surfaceBorder = Color(0xFFDDD8C8);
  static const Color surfaceBorderLight = Color(0xFFE7E3D5);

  // Light-mode text
  static const Color textPrimary = Color(0xFF1A1610);
  static const Color textSecondary = Color(0xFF6B6455);
  static const Color textTertiary = Color(0xFF9A9280);
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

  static const Cubic standardCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Cubic decelerateCurve = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Cubic accelerateCurve = Cubic(0.4, 0.0, 1.0, 1.0);
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
    )..repeat();
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.baseColor ??
        (isDark ? const Color(0xFF1A2744) : const Color(0xFFE2E8F0));
    final highlight = widget.highlightColor ??
        (isDark ? const Color(0xFF243556) : const Color(0xFFF1F5F9));

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
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                color: Colors.transparent,
              ),
              child: const ShimmerWidget(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 14),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerWidget(width: double.infinity, height: 12),
                  const SizedBox(height: 6),
                  const ShimmerWidget(width: 80, height: 12),
                  const Spacer(),
                  const ShimmerWidget(width: 100, height: 16),
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
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveTint =
        tint ?? (isDark ? DesignColors.glassDark : DesignColors.glassWhite);
    final effectiveBorder = borderColor ??
        (isDark ? DesignColors.glassDarkBorder : DesignColors.glassBorder);

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
                color: (isDark ? Colors.black : Colors.black)
                    .withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: blur,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: (isDark ? Colors.black : Colors.black)
                    .withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: blur * 0.5,
                offset: const Offset(0, 2),
              ),
            ],
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      );
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

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    if (widget.isLoading) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(GradientButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!widget.isLoading && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.gradient?.first ?? DesignColors.accent;
    final textColor = widget.textColor ??
        (fill.computeLuminance() > 0.5 ? Colors.black : Colors.white);

    final btn = AnimatedContainer(
      duration: DesignAnimation.fast,
      height: widget.height,
      width: widget.expanded ? double.infinity : null,
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
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return btn;
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
    final trendColor = trendValue != null
        ? (trendValue! >= 0 ? DesignColors.success : DesignColors.error)
        : DesignColors.textTertiary;
    final surface = isDark
        ? DesignColors.darkSurfaceElevated
        : Colors.white;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(color: border, width: 1),
          right: BorderSide(color: border, width: 1),
          bottom: BorderSide(color: border, width: 1),
        ),
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
            child: Text(
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
    );
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
    return Container(
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
            Icon(icon, color: textColor ?? color, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor ?? color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: DesignColors.accent, size: 18),
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
          if (trailing != null) trailing!,
        ],
      ),
    );
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
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.12)),
              ),
              child: Icon(icon, size: 32, color: color.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 14, color: subtitleColor),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              GradientButton(
                label: actionLabel!,
                icon: Icons.refresh_rounded,
                onPressed: onAction,
                height: 44,
              ),
            ],
          ],
        ),
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
      return Container(
        color: bg,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: padding ?? DesignSpacing.paddingScreen,
          child: child,
        ),
      );
    }

    return Container(
      color: bg,
      padding: padding,
      child: child,
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
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PAYMENT METHOD CHIP
// ═══════════════════════════════════════════════════════════════
class PaymentChip extends StatelessWidget {
  final String method;
  final bool isSelected;
  final VoidCallback? onTap;

  const PaymentChip({
    super.key,
    required this.method,
    this.isSelected = false,
    this.onTap,
  });

  Color get _color {
    switch (method.toUpperCase()) {
      case 'MPESA':
        return DesignColors.mpesa;
      case 'PESAPAL':
        return DesignColors.pesapal;
      case 'TOURISTTAP':
      case 'TOURIST TAP':
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
    switch (method.toUpperCase()) {
      case 'MPESA':
        return Icons.phone_android_rounded;
      case 'PESAPAL':
        return Icons.payments_rounded;
      case 'TOURISTTAP':
      case 'TOURIST TAP':
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? _color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? _color.withValues(alpha: 0.4)
                : DesignColors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: _color, size: 16),
            const SizedBox(width: 6),
            Text(
              method,
              style: TextStyle(
                color: isSelected ? _color : DesignColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
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
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
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
    );
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

  const GroupedCard({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 20),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                color: border.withValues(alpha: 0.6),
              ),
          ],
        ],
      ),
    );
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: resolvedIconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: resolvedIconColor, size: 18),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12.5, color: subtitleColor),
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
                ] else if (onTap != null)
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
    return Padding(
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
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
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
    return AlertDialog(
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
          color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
        ),
      ),
      content: content,
      actions: actions,
    );
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
    return FilledButton(
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
                color: fill.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
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
      return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      backgroundColor: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: confirmColor ?? DesignColors.error,
            size: 36,
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
      );
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
            Icon(icon, color: color ?? DesignColors.success, size: 20),
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
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        duration: DesignAnimation.fast,
        curve: DesignAnimation.smooth,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
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
//  Renders the Arche Axon Intelligence hex/node brand mark from
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
          semanticsLabel: 'Axon POS logo',
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          Text(
            'Axon POS',
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
    final radius = (size * 0.36).clamp(0.0, size / 2);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              AxonLogoTitle(logoSize: size),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: size * 0.5,
                height: size * 0.5,
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
          (showBackButton
              ? _BackButton(color: fg, isDark: isDark)
              : null),
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

class _BackButton extends StatelessWidget {
  final Color color;
  final bool isDark;
  const _BackButton({required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.arrow_back_rounded, color: color, size: 19),
          ),
        ),
      ),
    );
  }
}
