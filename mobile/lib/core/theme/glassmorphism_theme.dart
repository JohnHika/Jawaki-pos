import 'package:flutter/material.dart';

/// Glassmorphism Theme for Levisa Adventures POS
/// Implements modern frosted glass effects with transparency and blur
class GlassColors {
  // Glass Base Colors (Semi-transparent with blur effect)
  static const Color glassBackground = Color(0xE6FFFFFF);
  static const Color glassBackgroundDark = Color(0xE61E293B);
  static const Color glassSurface = Color(0xE0FFFFFF);
  static const Color glassSurfaceDark = Color(0xE01E293B);

  // Glass Gradient Overlays
  static const LinearGradient glassGradient = LinearGradient(
    colors: [
      Color(0xE6FFFFFF),
      Color(0xE0FFFFFF),
      Color(0xD0FFFFFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradientDark = LinearGradient(
    colors: [
      Color(0xE61E293B),
      Color(0xE01E293B),
      Color(0xD01E293B),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Glass Borders with Subtle Glow
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color glassBorderDark = Color(0x33000000);
  static const Color glassGlow = Color(0x4D6366F1);
  static const Color glassGlowDark = Color(0x33A5B4FC);

  // Glass Text Colors
  static const Color glassTextPrimary = Color(0xE61E293B);
  static const Color glassTextSecondary = Color(0x9964748B);
  static const Color glassTextInverse = Color(0xE0FFFFFF);
  static const Color glassTextInverseSecondary = Color(0x9994A3B8);
}

class GlassTheme {
  /// Modern glass card decoration
  static BoxDecoration glassCard({
    Color? backgroundColor,
    double blur = 20,
    double spread = 2,
    Color? borderColor,
    double borderRadius = 20,
    Color? shadowColor,
  }) {
    final effectiveColor = backgroundColor ?? GlassColors.glassBackground;
    final effectiveBorder = borderColor ?? GlassColors.glassBorder;
    final effectiveShadow = shadowColor ?? GlassColors.glassGlow;

    return BoxDecoration(
      color: effectiveColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: effectiveBorder,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: effectiveShadow.withOpacity(0.15),
          blurRadius: blur,
          spreadRadius: spread,
          offset: const Offset(0, 8),
        ),
      ],
      gradient: LinearGradient(
        colors: [
          effectiveColor.withOpacity(0.4),
          effectiveColor.withOpacity(0.2),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
  }

  /// Dark mode glass card
  static BoxDecoration glassCardDark({
    Color? backgroundColor,
    double blur = 20,
    double spread = 2,
    Color? borderColor,
    double borderRadius = 20,
  }) {
    final effectiveColor = backgroundColor ?? GlassColors.glassBackgroundDark;
    final effectiveBorder = borderColor ?? GlassColors.glassBorderDark;

    return BoxDecoration(
      color: effectiveColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: effectiveBorder,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: blur,
          spreadRadius: spread,
          offset: const Offset(0, 8),
        ),
      ],
      gradient: LinearGradient(
        colors: [
          effectiveColor.withOpacity(0.6),
          effectiveColor.withOpacity(0.3),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
  }

  /// Glass container with backdrop filter
  static Container glassContainer({
    required Widget child,
    double blur = 10,
    Color? backgroundColor,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
  }) {
    return Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: (backgroundColor ?? GlassColors.glassBackground).withOpacity(0.3),
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        border: Border.all(
          color: GlassColors.glassBorder.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.1),
            blurRadius: blur,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }

  /// Glass button style
  static ElevatedButtonThemeData glassButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: GlassColors.glassBackground.withOpacity(0.4),
      foregroundColor: GlassColors.glassTextPrimary,
      elevation: 0,
      shadowColor: GlassColors.glassGlow.withOpacity(0.2),
      minimumSize: const Size(double.infinity, 56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: GlassColors.glassBorder.withOpacity(0.5),
          width: 1,
        ),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      animationDuration: const Duration(milliseconds: 300),
      elevation: 0,
    ),
  );

  /// Glass input decoration
  static InputDecorationTheme glassInputDecoration = InputDecorationTheme(
    filled: true,
    fillColor: GlassColors.glassBackground.withOpacity(0.3),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: GlassColors.glassBorder.withOpacity(0.3),
        width: 1,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: GlassColors.glassBorder.withOpacity(0.3),
        width: 1,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: GlassColors.glassGlow,
        width: 2,
      ),
    ),
    prefixIconColor: GlassColors.glassTextSecondary,
    suffixIconColor: GlassColors.glassTextSecondary,
    labelStyle: TextStyle(
      color: GlassColors.glassTextSecondary,
      fontSize: 15,
    ),
    hintStyle: TextStyle(
      color: GlassColors.glassTextSecondary.withOpacity(0.6),
      fontSize: 15,
    ),
  );

  /// Glass card theme
  static CardThemeData glassCardTheme = CardThemeData(
    color: GlassColors.glassBackground.withOpacity(0.3),
    elevation: 0,
    shadowColor: GlassColors.glassGlow.withOpacity(0.2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: GlassColors.glassBorder.withOpacity(0.3),
        width: 1,
      ),
    ),
  );

  /// Glass chip theme
  static ChipThemeData glassChipTheme = ChipThemeData(
    backgroundColor: GlassColors.glassBackground.withOpacity(0.3),
    selectedColor: GlassColors.glassGlow.withOpacity(0.3),
    deleteIconColor: GlassColors.glassTextSecondary,
    labelStyle: TextStyle(
      color: GlassColors.glassTextPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: GlassColors.glassBorder.withOpacity(0.3),
        width: 1,
      ),
    ),
  );
}

/// Glassmorphism UI Utilities
class GlassUI {
  /// Modern frosted glass container
  static Container glassBox({
    required Widget child,
    double blur = 15,
    Color? backgroundColor,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
    double borderRadiusValue = 20,
  }) {
    return Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: (backgroundColor ?? GlassColors.glassBackground).withOpacity(0.25),
        borderRadius: BorderRadius.circular(borderRadiusValue),
        border: Border.all(
          color: GlassColors.glassBorder.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: blur,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Glass header container
  static Container glassHeader({
    required String title,
    required IconData icon,
    Color? primaryColor,
    double blur = 20,
    EdgeInsetsGeometry? padding,
  }) {
    final effectiveColor = primaryColor ?? const Color(0xFF6366F1);

    return Container(
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: GlassColors.glassBackground.withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: GlassColors.glassBorder.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveColor.withOpacity(0.2),
            blurRadius: blur,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: effectiveColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: effectiveColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: effectiveColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: GlassColors.glassTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Live Data',
                    style: TextStyle(
                      color: GlassColors.glassTextSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: effectiveColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: effectiveColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: effectiveColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Active',
                    style: TextStyle(
                      color: effectiveColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Glass metric card
  static Container glassMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? trend,
    double trendValue = 0,
    double blur = 15,
  }) {
    final trendColor = trendValue > 0
        ? const Color(0xFF22C55E)
        : trendValue < 0
            ? const Color(0xFFEF4444)
            : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GlassColors.glassBackground.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: GlassColors.glassBorder.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: blur,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 22,
                ),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: trendColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: trendColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendValue > 0 ? Icons.trending_up : Icons.trending_down,
                        color: trendColor,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trend,
                        style: TextStyle(
                          color: trendColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: GlassColors.glassTextPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: GlassColors.glassTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Glass chart container
  static Container glassChartContainer({
    required String title,
    required IconData icon,
    required Widget chart,
    Color? primaryColor,
    double blur = 15,
  }) {
    final effectiveColor = primaryColor ?? const Color(0xFF6366F1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GlassColors.glassBackground.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: GlassColors.glassBorder.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveColor.withOpacity(0.15),
            blurRadius: blur,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: effectiveColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: effectiveColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: effectiveColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: GlassColors.glassTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          chart,
        ],
      ),
    );
  }

  /// Glass list item with subtle hover effect
  static Container glassListItem({
    required Widget child,
    bool isSelected = false,
    Color? primaryColor,
    double blur = 10,
    EdgeInsetsGeometry? padding,
  }) {
    final effectiveColor = primaryColor ?? const Color(0xFF6366F1);

    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? effectiveColor.withOpacity(0.15)
            : GlassColors.glassBackground.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? effectiveColor.withOpacity(0.3)
              : GlassColors.glassBorder.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: effectiveColor.withOpacity(0.2),
                  blurRadius: blur,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: blur,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }

  /// Glass badge
  static Container glassBadge({
    required String text,
    required Color color,
    double blur = 8,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: blur,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
