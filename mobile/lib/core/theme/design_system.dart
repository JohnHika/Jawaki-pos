import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════
/// LEVISA ADVENTURES — PREMIUM DESIGN SYSTEM
/// A sophisticated, visually rich design language for the POS app
/// ═══════════════════════════════════════════════════════════════

// ─── Premium Color Palette ─────────────────────────────────────
class DesignColors {
  // Brand - Levisa forest green with warm travel accents.
  static const Color brand = Color(0xFF1F7A4D);
  static const Color brandLight = Color(0xFF4CAF7B);
  static const Color brandDark = Color(0xFF0B3D2E);
  static const Color brandSubtle = Color(0xFFEAF6EF);

  // Accent — Warm Amber/Gold for highlights
  static const Color accent = Color(0xFFD99A2B);
  static const Color accentLight = Color(0xFFF2C45B);
  static const Color accentSubtle = Color(0xFFFFF6DD);

  // Secondary — Teal for positive actions
  static const Color teal = Color(0xFF148C88);
  static const Color tealLight = Color(0xFF63C6BE);
  static const Color tealSubtle = Color(0xFFE6F7F5);
  static const Color terracotta = Color(0xFFC65F3A);
  static const Color terracottaSubtle = Color(0xFFFFECE5);

  // Surface tones - warm, clean, and less clinical.
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF7F6F1);
  static const Color surfaceSubtle = Color(0xFFF0EFE7);
  static const Color surfaceBorder = Color(0xFFE1DED2);
  static const Color surfaceBorderLight = Color(0xFFF0EFE7);

  // Text — Excellent hierarchy
  static const Color textPrimary = Color(0xFF14231C);
  static const Color textSecondary = Color(0xFF4E5D55);
  static const Color textTertiary = Color(0xFF8E9891);
  static const Color textInverse = Color(0xFFFFFFFF);
  static const Color textOnBrand = Color(0xFFFFFFFF);

  // Status — Vibrant but not harsh
  static const Color success = Color(0xFF198754);
  static const Color successSubtle = Color(0xFFDFF3E8);
  static const Color warning = Color(0xFFD99A2B);
  static const Color warningSubtle = Color(0xFFFFF0C2);
  static const Color error = Color(0xFFD94435);
  static const Color errorSubtle = Color(0xFFFFE3DF);
  static const Color info = Color(0xFF2F80A7);
  static const Color infoSubtle = Color(0xFFE2F1F7);

  // Payment method colors
  static const Color mpesa = Color(0xFF4CAF50);
  static const Color pesapal = Color(0xFF2196F3);
  static const Color touristtap = Color(0xFFC65F3A);
  static const Color cash = Color(0xFF607D8B);
  static const Color credit = Color(0xFFF97316);

  // Dark mode
  static const Color darkBg = Color(0xFF08140F);
  static const Color darkSurface = Color(0xFF10221A);
  static const Color darkSurfaceElevated = Color(0xFF173126);
  static const Color darkBorder = Color(0xFF254A3A);
  static const Color darkTextPrimary = Color(0xFFF4F7F2);
  static const Color darkTextSecondary = Color(0xFFBBC8BE);
  static const Color darkTextTertiary = Color(0xFF7E9288);

  // Glass (using hex alpha = 0x2E for 18%, 0x40 for 25%, 0x14 for 8%)
  static const Color glassWhite = Color(0x2EFFFFFF);
  static const Color glassBorder = Color(0x40FFFFFF);
  static const Color glassDark = Color(0x2A131C31);
  static const Color glassDarkBorder = Color(0x14FFFFFF);
}

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

// ─── Spacing & Sizing Scale ────────────────────────────────────
class LevisaLogoTitle extends StatelessWidget {
  final double logoSize;
  final bool showText;

  const LevisaLogoTitle({
    super.key,
    this.logoSize = 34,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
            border: Border.all(
              color:
                  isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/levisa_adventures_logo.png',
              fit: BoxFit.cover,
              semanticLabel: 'Levisa Adventures logo',
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          Text(
            'Levisa Adventures',
            style: TextStyle(
              color: isDark
                  ? DesignColors.darkTextPrimary
                  : DesignColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class BrandedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showLogo;

  const BrandedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showLogo = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      automaticallyImplyLeading: leading == null,
      leading: leading,
      centerTitle: false,
      titleSpacing: leading == null ? 16 : 0,
      toolbarHeight: preferredSize.height,
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      foregroundColor:
          isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogo) ...[
            const LevisaLogoTitle(logoSize: 32),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      actions: actions,
      shape: Border(
        bottom: BorderSide(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          width: 0.75,
        ),
      ),
    );
  }
}

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

// ─── Animations ────────────────────────────────────────────────
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
    this.borderRadius = 20,
    this.blur = 15,
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
    this.borderRadius = 16,
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
    this.borderRadius = 16,
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
    final gradient = widget.gradient ??
        [DesignColors.brandDark, DesignColors.brand, DesignColors.accent];

    final btn = AnimatedContainer(
      duration: DesignAnimation.fast,
      height: widget.height,
      width: widget.expanded ? double.infinity : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: _isPressed ? 0.2 : 0.4),
            blurRadius: _isPressed ? 8 : 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: gradient.first.withValues(alpha: _isPressed ? 0.1 : 0.2),
            blurRadius: _isPressed ? 4 : 8,
            offset: const Offset(0, 8),
          ),
        ],
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
                ? _LoadingDots(color: widget.textColor ?? Colors.white)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon,
                            color: widget.textColor ?? Colors.white, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.textColor ?? Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
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
    final trendColor = trendValue != null
        ? (trendValue! >= 0 ? DesignColors.success : DesignColors.error)
        : DesignColors.textTertiary;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      blur: 8,
      tint: color.withValues(alpha: 0.12),
      borderColor: color.withValues(alpha: 0.28),
      gradient: LinearGradient(
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.05),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendValue != null && trendValue! >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: trendColor,
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        trend!,
                        style: TextStyle(
                          color: trendColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w500,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.brandSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: DesignColors.brand, size: 18),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DesignColors.textTertiary,
                    ),
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
    final color = iconColor ?? DesignColors.textTertiary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.12)),
              ),
              child: Icon(icon, size: 48, color: color.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: DesignColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 14,
                  color: DesignColors.textTertiary,
                ),
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
    final gradient =
        isDark ? DesignGradients.darkSurface : DesignGradients.surface;

    if (withScroll) {
      return Container(
        color: backgroundColor != null ? bg : null,
        decoration:
            BoxDecoration(gradient: backgroundColor == null ? gradient : null),
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
      color: backgroundColor != null ? bg : null,
      decoration:
          BoxDecoration(gradient: backgroundColor == null ? gradient : null),
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
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      blur: 10,
      tint: color.withValues(alpha: 0.06),
      borderColor: color.withValues(alpha: 0.12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DesignColors.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 12,
      blur: 8,
      tint: Colors.transparent,
      borderColor: DesignColors.surfaceBorder,
      margin: const EdgeInsets.only(bottom: 8),
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DesignColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DesignColors.textSecondary,
                    ),
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
                color: DesignColors.textTertiary, size: 20),
        ],
      ),
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
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.surfaceBorder,
                    DesignColors.surfaceBorder.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DesignColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.surfaceBorder.withValues(alpha: 0.2),
                    DesignColors.surfaceBorder,
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
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: Theme.of(ctx).brightness == Brightness.dark
          ? DesignColors.darkSurface
          : Colors.white,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  (confirmColor ?? DesignColors.error).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: confirmColor ?? DesignColors.error,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DesignColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: DesignColors.textSecondary,
              height: 1.4,
            ),
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
    ),
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
              style: const TextStyle(
                color: DesignColors.textPrimary,
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
  static void show(
    BuildContext context, {
    required Widget child,
    double initialSize = 0.5,
    double maxSize = 0.9,
    String title = 'Details',
    bool scrollable = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
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
