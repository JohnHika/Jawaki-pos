import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../providers/catalog_provider.dart';

class CategoryChips extends ConsumerWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedId = ref.watch(selectedCategoryProvider);

    return SizedBox(
      height: 48,
      child: categoriesAsync.when(
        data: (categories) => ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          itemCount: categories.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _CategoryChip(
                label: 'All',
                icon: Icons.grid_view_rounded,
                isSelected: selectedId == null,
                onTap: () =>
                    ref.read(selectedCategoryProvider.notifier).state = null,
              );
            }
            final category = categories[index - 1];
            return _CategoryChip(
              label: category['name'] as String,
              isSelected: selectedId == category['id'],
              icon: null,
              color: category['color'] != null
                  ? Color(int.parse(
                      (category['color'] as String).replaceFirst('#', '0xFF')))
                  : null,
              onTap: () => ref.read(selectedCategoryProvider.notifier).state =
                  category['id'] as String?,
            );
          },
        ),
        loading: () => ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          itemCount: 5,
          itemBuilder: (context, index) => const _CategoryChipSkeleton(),
        ),
        error: (_, __) =>
            const Center(child: Text('Failed to load categories')),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final IconData? icon;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    this.color,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? DesignColors.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        curve: DesignAnimation.smooth,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? chipColor.withValues(alpha: 0.15)
                  : (isDark ? DesignColors.glassDark : DesignColors.glassWhite),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
              border: Border.all(
                color: isSelected
                    ? chipColor.withValues(alpha: 0.4)
                    : (isDark
                        ? DesignColors.glassDarkBorder
                        : DesignColors.surfaceBorder),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: chipColor.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: isSelected
                          ? chipColor
                          : (isDark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary)),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? chipColor
                        : (isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
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

class _CategoryChipSkeleton extends StatelessWidget {
  const _CategoryChipSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: const ShimmerWidget(width: 80, height: 36, borderRadius: 18),
    );
  }
}
