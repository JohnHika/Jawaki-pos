import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../providers/catalog_provider.dart';

class CategoryChips extends ConsumerWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedId = ref.watch(selectedCategoryProvider);

    return SizedBox(
      height: 58,
      child: categoriesAsync.when(
        data: (categories) => ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
              // The categories table has no color column; the old
              // category['color'] parse was dead code that always
              // returned null and fell through to brand anyway.
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
        error: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.category_outlined,
                  size: 18, color: DesignColors.error),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Categories unavailable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(categoriesProvider),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: DesignColors.accent,
                  minimumSize: const Size(72, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final IconData? icon;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const chipColor = DesignColors.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TapScale(
        scale: 0.94,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? chipColor.withValues(alpha: 0.18)
                      : DesignColors.peach)
                  : (isDark ? DesignColors.glassDark : Colors.white),
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
                        color: chipColor.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
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
    return const Padding(
      padding: EdgeInsets.only(right: 8),
      child: ShimmerWidget(width: 80, height: 36, borderRadius: 18),
    );
  }
}
