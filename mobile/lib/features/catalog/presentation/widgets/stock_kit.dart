import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/workspace_image.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/stock_status.dart';

/// The dot and chip colour for each stock level. The same colours are used on
/// Products, the Sell grid and Stock.
Color stockColor(StockLevel level) => switch (level) {
      StockLevel.inStock => MoneyColors.cash,
      StockLevel.low => MoneyColors.recorded,
      StockLevel.out => DesignColors.error,
      StockLevel.notTracked || StockLevel.unknown => DesignColors.textTertiary,
    };

/// Darker text for a chip on its own tinted background, so it stays readable.
Color _stockInk(StockLevel level, bool isDark) {
  if (isDark) return stockColor(level);
  return switch (level) {
    StockLevel.inStock => const Color(0xFF1F6B45),
    StockLevel.low => const Color(0xFF8A4A12),
    StockLevel.out => const Color(0xFF9B2C2C),
    StockLevel.notTracked || StockLevel.unknown => DesignColors.textSecondary,
  };
}

/// "48 in stock", "3 left", "Out" as a small pill.
class StockChip extends StatelessWidget {
  const StockChip({super.key, required this.level, required this.quantity});

  final StockLevel level;
  final double? quantity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = stockColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stockWords(level, quantity),
        style: TextStyle(
          color: _stockInk(level, isDark),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A product's picture, or its initials when it has none.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.tint,
  });

  final String name;
  final String? imageUrl;
  final double size;

  /// Colours the initials, for example red for a product that is out.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint == null ? palette.field : tint!.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initialsFor(name),
        style: DesignType.display.copyWith(
          color: tint ?? palette.soft,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if ((imageUrl ?? '').trim().isEmpty) return initials;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: SizedBox(
        width: size,
        height: size,
        child: WorkspaceImage(
          source: imageUrl,
          width: size,
          height: size,
          placeholder: initials,
        ),
      ),
    );
  }
}

/// The two-way switch under the Products title: Products or Stock.
class ProductsSwitch extends StatelessWidget {
  const ProductsSwitch({
    super.key,
    required this.stockSelected,
    required this.onChanged,
    required this.productsLabel,
  });

  final bool stockSelected;
  final ValueChanged<bool> onChanged;
  final String productsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    Widget segment(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: DesignAnimation.fast,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? (palette.isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? (palette.isDark
                            ? DesignColors.darkBg
                            : Colors.white)
                        : palette.soft,
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          segment(productsLabel, !stockSelected, () => onChanged(false)),
          segment('Stock', stockSelected, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// A bar for how much is left, with a tick where the warning starts.
class StockGauge extends StatelessWidget {
  const StockGauge({
    super.key,
    required this.quantity,
    required this.warnAt,
    required this.level,
  });

  final double quantity;
  final int warnAt;
  final StockLevel level;

  @override
  Widget build(BuildContext context) {
    final top = [quantity, warnAt * 4.0, 1.0].reduce((a, b) => a > b ? a : b);
    final fill = (quantity / top).clamp(0.0, 1.0);
    final tick = (warnAt / top).clamp(0.0, 1.0);
    return SizedBox(
      height: 14,
      child: LayoutBuilder(builder: (context, box) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 3,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF3A322A),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 3,
              height: 8,
              width: box.maxWidth * fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: stockColor(level),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            if (warnAt > 0)
              Positioned(
                left: box.maxWidth * tick - 1,
                top: 0,
                width: 2,
                height: 14,
                child: const ColoredBox(color: Color(0xFFF0B24A)),
              ),
          ],
        );
      }),
    );
  }
}

/// A small orange-tinted action pill used on list rows, such as "Receive".
class MiniAction extends StatelessWidget {
  const MiniAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DesignColors.peach,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA8430F),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The one orange action at the bottom of a screen, sitting above the bottom
/// bar the way the sale total does on Sell.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: DesignColors.accent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: DesignColors.textPrimary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: DesignColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
