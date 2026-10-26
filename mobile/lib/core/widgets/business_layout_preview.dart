import 'package:flutter/material.dart';

import '../providers/business_layout_provider.dart';
import '../theme/design_system.dart';

/// A compact, shared preview of the shop-wide changes a profile applies.
/// Used during first setup and later in Layout actions so merchants see the
/// same explanation in both places.
class BusinessLayoutPreview extends StatelessWidget {
  const BusinessLayoutPreview({super.key, required this.layout});

  final BusinessLayoutConfig layout;

  @override
  Widget build(BuildContext context) {
    final preset = layout.preset;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final startPath = layout.startPath ??
        (layout.priorityPaths.isEmpty ? null : layout.priorityPaths.first);
    final startAction =
        startPath == null ? null : _layoutActionForPath(startPath);
    final startLabel = startAction == null
        ? 'Choose a start screen in Layout actions'
        : layout.actionLabel(startAction.path, startAction.label);
    final visibleCount = businessLayoutActions
        .where((action) => layout.isActionVisible(action.path))
        .length;
    final shortcuts = layout.priorityPaths
        .where((path) => layout.isActionVisible(path))
        .map(_layoutActionForPath)
        .whereType<BusinessLayoutAction>()
        .take(4)
        .toList(growable: false);
    final posQuickActions = layout.effectivePosQuickActions
        .map((id) => businessLayoutPosActions.firstWhere(
              (action) => action.id == id,
              orElse: () => businessLayoutPosActions.first,
            ))
        .toList(growable: false);
    final fields = layout.effectiveProductFields;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(preset.icon, color: DesignColors.accent, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      layout.profileSummary,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      layout.additionalPresets.isEmpty
                          ? 'Applies across this shop on every device'
                          : 'Main profile sets the wording; added profiles bring in more fields and work areas.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PreviewSectionLabel(label: 'STARTS AT', secondary: secondary),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.play_arrow_rounded,
                  size: 20, color: DesignColors.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(startLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
              ),
              Text('$visibleCount work areas',
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
            ],
          ),
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PreviewSectionLabel(
                label: 'FIRST IN YOUR NAVIGATION', secondary: secondary),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: shortcuts
                  .map((action) => _PreviewChip(
                        icon: action.icon,
                        label: layout.actionLabel(action.path, action.label),
                      ))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 420;
            final cardWidth = wide ? (constraints.maxWidth - 9) / 2 : null;
            return Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _PreviewInfoCard(
                    icon: Icons.inventory_2_outlined,
                    title: layout.productsLabel,
                    detail:
                        'Find by ${layout.productCodeLabel.replaceAll(' (optional)', '')}. New ${layout.productSingular.toLowerCase()}s use ${_unitLabel(layout.defaultBaseUnit)}${layout.effectiveAllowFractionsForNewProducts ? ' · fractional quantities' : ''}${layout.effectiveTrackInventoryForNewProducts ? ' · stock tracked' : ' · stock tracking off by default'}.',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PreviewInfoCard(
                    icon: Icons.people_outline_rounded,
                    title: layout.customersLabel,
                    detail:
                        'Each record is a ${layout.customerSingular.toLowerCase()}.',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PreviewInfoCard(
                    icon: layout.effectivePosProductView == 'list'
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    title: 'Point of sale',
                    detail:
                        '${layout.effectivePosProductView == 'list' ? 'Compact list' : 'Product grid'} · ${layout.effectiveShowPosCategories ? 'categories' : 'no categories'} · ${layout.effectiveShowPosFavorites ? 'favourites' : 'no favourites'} · ${layout.effectiveShowPosCustomer ? 'customer lookup' : 'no customer lookup'}',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PreviewInfoCard(
                    icon: Icons.dashboard_outlined,
                    title: 'Dashboard',
                    detail:
                        '${layout.effectiveDashboardSections.length} sections · '
                        '${layout.effectiveDashboardMetrics.length} figures, in your chosen order.',
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 14),
          _PreviewSectionLabel(label: 'POS TOOLBAR', secondary: secondary),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: posQuickActions
                .map((action) => _PreviewChip(
                      icon: action.icon,
                      label: action.label,
                    ))
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          _PreviewSectionLabel(
              label: 'QUICK PRODUCT PAGES', secondary: secondary),
          const SizedBox(height: 6),
          if (layout.posProductPages.isEmpty)
            Text(
              'Create pages for fast sellers after adding products to the catalog.',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: layout.posProductPages
                  .map((page) => _PreviewChip(
                        icon: Icons.grid_view_rounded,
                        label: '${page.name} · ${page.productIds.length}',
                      ))
                  .toList(growable: false),
            ),
          const SizedBox(height: 14),
          _PreviewSectionLabel(
              label: 'DASHBOARD SECTIONS', secondary: secondary),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: layout.effectiveDashboardSections.map((id) {
              final section = businessLayoutDashboardSections.firstWhere(
                (item) => item.id == id,
                orElse: () => businessLayoutDashboardSections.first,
              );
              return _PreviewChip(icon: section.icon, label: section.label);
            }).toList(growable: false),
          ),
          const SizedBox(height: 14),
          _PreviewSectionLabel(
              label: 'DASHBOARD FIGURES', secondary: secondary),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: layout.effectiveDashboardMetrics.map((id) {
              final metric = businessLayoutDashboardMetrics.firstWhere(
                (item) => item.id == id,
                orElse: () => businessLayoutDashboardMetrics.first,
              );
              return _PreviewChip(icon: metric.icon, label: metric.label);
            }).toList(growable: false),
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 14),
            _PreviewSectionLabel(
                label: 'EXTRA PRODUCT DETAILS', secondary: secondary),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: fields
                  .map((field) => _PreviewChip(
                        icon: Icons.sell_outlined,
                        label: field.label,
                      ))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewSectionLabel extends StatelessWidget {
  const _PreviewSectionLabel({required this.label, required this.secondary});

  final String label;
  final Color secondary;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
      );
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 16, color: DesignColors.accent),
        label: Text(label),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide.none,
      );
}

class _PreviewInfoCard extends StatelessWidget {
  const _PreviewInfoCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? DesignColors.darkTextSecondary
        : DesignColors.textSecondary;
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? DesignColors.darkSurface
            : DesignColors.surfaceMuted,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: DesignColors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: secondary, height: 1.25)),
        ],
      ),
    );
  }
}

String _unitLabel(String unit) =>
    unit.isEmpty ? unit : '${unit[0].toUpperCase()}${unit.substring(1)}';

BusinessLayoutAction? _layoutActionForPath(String path) {
  for (final action in businessLayoutActions) {
    if (action.path == path) return action;
  }
  return null;
}
