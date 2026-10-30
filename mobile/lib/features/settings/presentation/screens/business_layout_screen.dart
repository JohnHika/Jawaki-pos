import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/providers/local_workspace_capabilities.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/business_layout_preview.dart';
import '../../../../core/widgets/business_layout_profile_picker.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class BusinessLayoutScreen extends ConsumerStatefulWidget {
  const BusinessLayoutScreen({super.key});

  @override
  ConsumerState<BusinessLayoutScreen> createState() =>
      _BusinessLayoutScreenState();
}

class _BusinessLayoutScreenState extends ConsumerState<BusinessLayoutScreen> {
  final _profileSearchController = TextEditingController();
  late String _profileId;
  late List<String> _additionalProfileIds;
  String? _startPath;
  late List<String> _priorityPaths;
  late List<String> _hiddenPaths;
  late Map<String, String> _actionLabels;
  late Map<String, String> _terminologyOverrides;
  late String _defaultBaseUnit;
  late bool _allowFractionsForNewProducts;
  late bool _trackInventoryForNewProducts;
  late String _posProductView;
  late bool _showPosCategories;
  late bool _showPosFavorites;
  late bool _showPosCustomer;
  late List<String> _posQuickActions;
  late List<BusinessLayoutProductPage> _posProductPages;
  late List<String> _dashboardMetrics;
  late List<String> _dashboardSections;
  late List<String> _productFieldKeys;
  late List<BusinessLayoutProductField> _customProductFields;
  String _profileSearch = '';
  bool _initialized = false;
  bool _saving = false;

  List<String> _supportedPriorityPaths(Iterable<String> paths) {
    if (!getIt<AuthService>().isLocalWorkspace) return paths.toList();
    return paths
        .where(LocalWorkspaceCapabilities.supportsPath)
        .toList(growable: true);
  }

  bool _supportsPosAction(String id) {
    final action = businessLayoutPosAction(id);
    if (action == null) return false;
    if (!getIt<AuthService>().isLocalWorkspace) return true;
    final path = action.path;
    return path == null || LocalWorkspaceCapabilities.supportsPath(path);
  }

  List<String> _supportedPosQuickActions(Iterable<String> actions) {
    final supported = actions.where(_supportsPosAction).toList(growable: true);
    if (supported.isEmpty) return <String>['cart'];
    if (!supported.contains('cart')) supported.add('cart');
    return supported;
  }

  @override
  void dispose() {
    _profileSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canManageLayout =
        ref.watch(permissionsProvider).has('branches.tenant.update');
    final canEditLayout = canManageLayout && !_saving;
    if (!_initialized) {
      final config = businessLayoutFromUser(user);
      _profileId = config.profileId;
      _additionalProfileIds = [...config.additionalProfileIds];
      _priorityPaths = _supportedPriorityPaths(config.priorityPaths);
      _startPath = _priorityPaths.contains(config.startPath)
          ? config.startPath
          : _priorityPaths.firstOrNull;
      _hiddenPaths = [...config.hiddenPaths];
      _actionLabels = {...config.actionLabels};
      _terminologyOverrides = {...config.terminologyOverrides};
      _defaultBaseUnit = config.defaultBaseUnit;
      _allowFractionsForNewProducts =
          config.effectiveAllowFractionsForNewProducts;
      _trackInventoryForNewProducts =
          config.effectiveTrackInventoryForNewProducts;
      _posProductView = config.effectivePosProductView;
      _showPosCategories = config.effectiveShowPosCategories;
      _showPosFavorites = config.effectiveShowPosFavorites;
      _showPosCustomer = config.effectiveShowPosCustomer;
      _posQuickActions =
          _supportedPosQuickActions(config.effectivePosQuickActions);
      _posProductPages = [...config.posProductPages];
      _dashboardMetrics = [...config.effectiveDashboardMetrics];
      _dashboardSections = [...config.effectiveDashboardSections];
      _productFieldKeys =
          config.effectiveProductFields.map((field) => field.key).toList();
      _customProductFields = [...config.customProductFields];
      _initialized = true;
    }

    final selectedPreset = businessLayoutPreset(_profileId);
    final selectedLayout = BusinessLayoutConfig(
      preset: selectedPreset,
      additionalProfileIds: _additionalProfileIds,
      priorityPaths: _priorityPaths,
      hiddenPaths: _hiddenPaths,
      actionLabels: _actionLabels,
      terminologyOverrides: _terminologyOverrides,
      baseUnitOverride: _defaultBaseUnit,
      allowFractionsForNewProducts: _allowFractionsForNewProducts,
      trackInventoryForNewProducts: _trackInventoryForNewProducts,
      startPath: _startPath,
      posProductView: _posProductView,
      showPosCategories: _showPosCategories,
      showPosFavorites: _showPosFavorites,
      showPosCustomer: _showPosCustomer,
      posQuickActions: _posQuickActions,
      posProductPages: _posProductPages,
      dashboardMetrics: _dashboardMetrics,
      dashboardSections: _dashboardSections,
      productFieldKeys: _productFieldKeys,
      customProductFields: _customProductFields,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurface : Colors.white;
    final text =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final availableActions = businessLayoutActions
        .where((action) =>
            (!isLocalWorkspace ||
                LocalWorkspaceCapabilities.supportsPath(action.path)) &&
            selectedLayout.isActionVisible(action.path) &&
            !_priorityPaths.contains(action.path))
        .toList();
    final profileQuery = _profileSearch.trim().toLowerCase();
    final visiblePresets = businessLayoutPresets.where((preset) {
      return businessLayoutProfileMatchesSearch(preset, profileQuery);
    }).toList(growable: false);

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Layout actions'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  Text(
                    'Make Counterbase fit the way your shop works.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: text,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a shop profile, shape checkout, rename and show the work areas you use, set the opening screen, and arrange shortcuts. This layout is saved on this device; other installations keep their own layout.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: secondary,
                          height: 1.45,
                        ),
                  ),
                  if (!canManageLayout) ...[
                    const SizedBox(height: 14),
                    const _PermissionNotice(),
                  ],
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Shop profile',
                    subtitle:
                        'Choose a ready-made setup, then tune it below. The profile refreshes its recommended layout; your custom wording stays in place.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _profileSearchController,
                    onChanged: (value) =>
                        setState(() => _profileSearch = value),
                    decoration: InputDecoration(
                      hintText: 'Find a shop type',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _profileSearch.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear shop type search',
                              onPressed: () {
                                _profileSearchController.clear();
                                setState(() => _profileSearch = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 980
                        ? 3
                        : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                    const spacing = 12.0;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    if (visiblePresets.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No shop profiles match that search.'),
                      );
                    }
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: visiblePresets.map((preset) {
                        final selected = preset.id == _profileId;
                        return SizedBox(
                          width: width,
                          child: _ProfileCard(
                            preset: preset,
                            selected: selected,
                            onTap: !canEditLayout
                                ? null
                                : () => setState(() {
                                      if (_profileId != preset.id) {
                                        _profileId = preset.id;
                                        _additionalProfileIds.remove(preset.id);
                                        _hiddenPaths =
                                            businessLayoutDefaultHiddenPaths(
                                          _profileId,
                                          _additionalProfileIds,
                                        );
                                        _priorityPaths =
                                            _supportedPriorityPaths(
                                          businessLayoutDefaultPriorityPaths(
                                            _profileId,
                                            _additionalProfileIds,
                                          ),
                                        );
                                        _startPath = _priorityPaths.isEmpty
                                            ? null
                                            : _priorityPaths.first;
                                        _defaultBaseUnit =
                                            preset.defaultBaseUnit;
                                        _allowFractionsForNewProducts =
                                            preset.defaultAllowFractions;
                                        _trackInventoryForNewProducts = preset
                                            .defaultTrackInventoryForNewProducts;
                                        _posProductView =
                                            preset.defaultPosProductView;
                                        _showPosCategories =
                                            preset.defaultShowPosCategories;
                                        _showPosFavorites =
                                            preset.defaultShowPosFavorites;
                                        _showPosCustomer =
                                            preset.defaultShowPosCustomer;
                                        _posQuickActions =
                                            _supportedPosQuickActions(
                                          businessLayoutDefaultPosQuickActions(
                                            _profileId,
                                            _additionalProfileIds,
                                          ),
                                        );
                                        _dashboardMetrics = [
                                          ...businessLayoutDefaultDashboardMetrics(
                                            _profileId,
                                            _additionalProfileIds,
                                          )
                                        ];
                                        _dashboardSections = [
                                          ...businessLayoutDefaultDashboardSections(
                                            _profileId,
                                            _additionalProfileIds,
                                          )
                                        ];
                                        _productFieldKeys = [
                                          ...businessLayoutDefaultProductFieldKeys(
                                            _profileId,
                                            _additionalProfileIds,
                                            customFields: _customProductFields,
                                          ),
                                        ];
                                      }
                                    }),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 12),
                  BusinessLayoutPreview(layout: selectedLayout),
                  const SizedBox(height: 16),
                  const _SectionHeading(
                    title: 'Additional shop profiles',
                    subtitle:
                        'Combine up to three trades. The main profile keeps its wording and checkout defaults; additional profiles add relevant product details and useful work areas.',
                  ),
                  const SizedBox(height: 8),
                  if (_additionalProfileIds.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedLayout.additionalPresets.map((profile) {
                        return InputChip(
                          avatar: Icon(profile.icon, size: 18),
                          label: Text(profile.name),
                          onDeleted: !canEditLayout
                              ? null
                              : () => _applyAdditionalProfiles(
                                    _additionalProfileIds
                                        .where((id) => id != profile.id)
                                        .toList(),
                                  ),
                        );
                      }).toList(growable: false),
                    ),
                  if (_additionalProfileIds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'For example, combine a bookshop with stationery or a grocery with a bakery counter.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: secondary, height: 1.35),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed:
                          !canEditLayout ? null : _chooseAdditionalProfiles,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(_additionalProfileIds.isEmpty
                          ? 'Add another shop profile'
                          : 'Edit additional profiles'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: !canEditLayout ? null : _editProductWording,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Customize shop wording'),
                  ),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'New product defaults',
                    subtitle:
                        'Set the starting unit and quantity behavior for new items. Existing items keep their saved settings.',
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('layout-unit-$_defaultBaseUnit'),
                    initialValue: _defaultBaseUnit,
                    decoration: const InputDecoration(
                      labelText: 'Default selling unit',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.straighten_rounded),
                    ),
                    items: businessLayoutUnits
                        .map((unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(_unitLabel(unit)),
                            ))
                        .toList(),
                    onChanged: !canEditLayout
                        ? null
                        : (unit) {
                            if (unit != null) {
                              setState(() => _defaultBaseUnit = unit);
                            }
                          },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('Allow fractional quantities by default'),
                    subtitle: const Text(
                      'Useful for goods sold by weight or measure. Existing items are unchanged.',
                    ),
                    value: _allowFractionsForNewProducts,
                    activeTrackColor: DesignColors.accent,
                    onChanged: !canEditLayout
                        ? null
                        : (value) => setState(
                              () => _allowFractionsForNewProducts = value,
                            ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('Track stock for new items'),
                    subtitle: const Text(
                      'Turn this off for services or other non-stock items. You can still choose stock tracking for each item; existing items are unchanged.',
                    ),
                    value: _trackInventoryForNewProducts,
                    activeTrackColor: DesignColors.accent,
                    onChanged: !canEditLayout
                        ? null
                        : (value) => setState(
                              () => _trackInventoryForNewProducts = value,
                            ),
                  ),
                  const SizedBox(height: 22),
                  _SectionHeading(
                    title: 'Product details',
                    subtitle: isLocalWorkspace
                        ? 'Choose the extra details each product form should collect for this trade. These layout choices are saved on this device.'
                        : 'Choose the extra details each product form should collect for this trade. These details sync with the shop and stay available offline.',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorderLight,
                      ),
                    ),
                    child: Column(
                      children: [
                        if (selectedPreset.productFields.isEmpty &&
                            _customProductFields.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Add details such as size, author, model or pack quantity.',
                              style: TextStyle(color: secondary),
                            ),
                          ),
                        for (final field in [
                          ...selectedPreset.productFields,
                          ..._customProductFields,
                        ])
                          CheckboxListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _productFieldKeys.contains(field.key),
                            activeColor: DesignColors.accent,
                            title: Text(field.label),
                            subtitle: Text(field.hint),
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: _customProductFields
                                    .any((custom) => custom.key == field.key)
                                ? IconButton(
                                    tooltip: 'Remove custom detail',
                                    onPressed: !canEditLayout
                                        ? null
                                        : () =>
                                            _removeCustomProductField(field),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded),
                                  )
                                : null,
                            onChanged: !canEditLayout
                                ? null
                                : (enabled) => setState(() {
                                      if (enabled == true) {
                                        if (!_productFieldKeys
                                            .contains(field.key)) {
                                          _productFieldKeys.add(field.key);
                                        }
                                      } else {
                                        _productFieldKeys.remove(field.key);
                                      }
                                    }),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed:
                                !canEditLayout ? null : _addCustomProductField,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add a custom detail'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Checkout layout',
                    subtitle:
                        'Shape the product browser and keep the shortcuts your team uses.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Start from a selling style',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700, color: text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Each style sets a starting point. You can still adjust every control below.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: secondary, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 980
                        ? 3
                        : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                    const spacing = 10.0;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: businessLayoutCheckoutStyles.map((style) {
                        final selected = style.matches(selectedLayout);
                        return SizedBox(
                          width: width,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: !canEditLayout
                                ? null
                                : () => setState(() {
                                      _posProductView = style.productView;
                                      _showPosCategories = style.showCategories;
                                      _showPosFavorites = style.showFavorites;
                                      _showPosCustomer = style.showCustomer;
                                      if (style.showFavorites &&
                                          !_posQuickActions
                                              .contains('favorites')) {
                                        _posQuickActions.add('favorites');
                                      } else if (!style.showFavorites) {
                                        _posQuickActions.remove('favorites');
                                      }
                                      if (style.showCustomer &&
                                          !_posQuickActions
                                              .contains('customer')) {
                                        _posQuickActions.add('customer');
                                      } else if (!style.showCustomer) {
                                        _posQuickActions.remove('customer');
                                      }
                                    }),
                            child: AnimatedContainer(
                              duration: DesignAnimation.fast,
                              constraints: const BoxConstraints(minHeight: 112),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? DesignColors.accent
                                        .withValues(alpha: isDark ? .18 : .10)
                                    : surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? DesignColors.accent
                                      : isDark
                                          ? DesignColors.darkBorder
                                          : DesignColors.surfaceBorderLight,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(style.icon,
                                          color: DesignColors.accent, size: 20),
                                      const Spacer(),
                                      if (selected)
                                        const Icon(Icons.check_circle_rounded,
                                            color: DesignColors.accent,
                                            size: 18),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(style.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: text,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(style.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: secondary,
                                          fontSize: 12,
                                          height: 1.3)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    );
                  }),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorderLight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Product browser',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'Choose a visual grid for image-led selling or a compact list for titles and codes.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: secondary, height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'grid',
                                icon: Icon(Icons.grid_view_rounded),
                                label: Text('Grid'),
                              ),
                              ButtonSegment(
                                value: 'list',
                                icon: Icon(Icons.view_list_rounded),
                                label: Text('Compact list'),
                              ),
                            ],
                            selected: {_posProductView},
                            onSelectionChanged: !canEditLayout
                                ? null
                                : (selection) => setState(() {
                                      _posProductView = selection.first;
                                    }),
                          ),
                        ),
                        const Divider(height: 22),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Category filters'),
                          subtitle: const Text(
                              'Show categories above the product browser.'),
                          value: _showPosCategories,
                          activeTrackColor: DesignColors.accent,
                          onChanged: !canEditLayout
                              ? null
                              : (value) => setState(
                                    () => _showPosCategories = value,
                                  ),
                        ),
                        const Divider(height: 20),
                        Text(
                          'POS toolbar order',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose the shortcuts at this till and move the most-used ones first. Staff access rules still apply.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: secondary, height: 1.35),
                        ),
                        const SizedBox(height: 6),
                        ..._posQuickActions.asMap().entries.map((entry) {
                          final option = businessLayoutPosActions.firstWhere(
                            (action) => action.id == entry.value,
                          );
                          return Padding(
                            key: ValueKey('pos-action-${option.id}'),
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  Icon(option.icon, color: DesignColors.accent),
                              title: Text(option.label),
                              subtitle: Text(option.description),
                              trailing: SizedBox(
                                width: 136,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Switch.adaptive(
                                      value: true,
                                      activeTrackColor: DesignColors.accent,
                                      onChanged: !canEditLayout ||
                                              option.id == 'cart'
                                          ? null
                                          : (_) =>
                                              _togglePosQuickAction(option.id),
                                    ),
                                    IconButton(
                                      tooltip: 'Move ${option.label} up',
                                      visualDensity: VisualDensity.compact,
                                      onPressed:
                                          !canEditLayout || entry.key == 0
                                              ? null
                                              : () => _movePosQuickAction(
                                                  entry.key, -1),
                                      icon: const Icon(
                                          Icons.arrow_upward_rounded),
                                    ),
                                    IconButton(
                                      tooltip: 'Move ${option.label} down',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: !canEditLayout ||
                                              entry.key ==
                                                  _posQuickActions.length - 1
                                          ? null
                                          : () =>
                                              _movePosQuickAction(entry.key, 1),
                                      icon: const Icon(
                                          Icons.arrow_downward_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        ...businessLayoutPosActions
                            .where((action) =>
                                _supportsPosAction(action.id) &&
                                !_posQuickActions.contains(action.id))
                            .map((action) => CheckboxListTile.adaptive(
                                  key: ValueKey('pos-action-add-${action.id}'),
                                  contentPadding: EdgeInsets.zero,
                                  value: false,
                                  activeColor: DesignColors.accent,
                                  secondary:
                                      Icon(action.icon, color: secondary),
                                  title: Text(action.label),
                                  subtitle: Text(action.description),
                                  onChanged: !canEditLayout
                                      ? null
                                      : (enabled) {
                                          if (enabled != true) return;
                                          setState(() {
                                            _posQuickActions.add(action.id);
                                            final path = action.path;
                                            if (path != null) {
                                              _hiddenPaths.remove(path);
                                            }
                                            if (action.id == 'customer') {
                                              _showPosCustomer = true;
                                            } else if (action.id ==
                                                'favorites') {
                                              _showPosFavorites = true;
                                            }
                                          });
                                        },
                                )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorderLight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick product pages',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isLocalWorkspace
                              ? 'Build named till pages from products you sell often, such as Textbooks, Stationery, or Fast movers. They use the same stock and price checks as your full catalog and stay on this device.'
                              : 'Build named till pages from products you sell often, such as Textbooks, Stationery, or Fast movers. Pages sync with this shop and use the same stock and price checks as the full catalog.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: secondary, height: 1.35),
                        ),
                        if (_posProductPages.isEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'No quick pages yet. Your regular product catalog stays available on the POS.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: secondary),
                          ),
                        ],
                        const SizedBox(height: 6),
                        ..._posProductPages.asMap().entries.map((entry) {
                          final page = entry.value;
                          return ListTile(
                            key: ValueKey('pos-product-page-${page.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.grid_view_rounded,
                                color: DesignColors.accent),
                            title: Text(page.name),
                            subtitle: Text(
                              '${page.productIds.length} products · shown as a POS page',
                            ),
                            onTap: !canEditLayout
                                ? null
                                : () => _editPosProductPage(page),
                            trailing: SizedBox(
                              width: 144,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: 'Move ${page.name} up',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: !canEditLayout || entry.key == 0
                                        ? null
                                        : () =>
                                            _movePosProductPage(entry.key, -1),
                                    icon:
                                        const Icon(Icons.arrow_upward_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Move ${page.name} down',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: !canEditLayout ||
                                            entry.key ==
                                                _posProductPages.length - 1
                                        ? null
                                        : () =>
                                            _movePosProductPage(entry.key, 1),
                                    icon: const Icon(
                                        Icons.arrow_downward_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove ${page.name}',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: !canEditLayout
                                        ? null
                                        : () => setState(() => _posProductPages
                                            .removeAt(entry.key)),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed:
                              !canEditLayout || _posProductPages.length >= 12
                                  ? null
                                  : () => _editPosProductPage(),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(_posProductPages.length >= 12
                              ? 'Page limit reached'
                              : 'Create a product page'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Dashboard layout',
                    subtitle:
                        'Choose the dashboard sections your team needs. Your reports and records remain available if a section is hidden.',
                  ),
                  const SizedBox(height: 8),
                  ...businessLayoutDashboardSections.map((section) {
                    final selected = _dashboardSections.contains(section.id);
                    return CheckboxListTile.adaptive(
                      key: ValueKey('dashboard-section-${section.id}'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      value: selected,
                      activeColor: DesignColors.accent,
                      secondary: Icon(section.icon, color: DesignColors.accent),
                      title: Text(section.label),
                      subtitle: Text(section.description),
                      onChanged: !canEditLayout ||
                              (selected && _dashboardSections.length == 1)
                          ? null
                          : (enabled) => setState(() {
                                if (enabled == true && !selected) {
                                  _dashboardSections.add(section.id);
                                } else if (enabled == false && selected) {
                                  _dashboardSections.remove(section.id);
                                }
                              }),
                    );
                  }),
                  const SizedBox(height: 12),
                  const _SectionHeading(
                    title: 'Dashboard figures',
                    subtitle:
                        'Choose the figures your team needs first and arrange them in order.',
                  ),
                  const SizedBox(height: 10),
                  ...businessLayoutDashboardMetrics.map((metric) {
                    final index = _dashboardMetrics.indexOf(metric.id);
                    final selected = index >= 0;
                    final rowColor = isDark
                        ? DesignColors.darkSurfaceElevated
                        : Colors.white;
                    return Padding(
                      key: ValueKey('dashboard-metric-${metric.id}'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: rowColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? DesignColors.darkBorder
                                : DesignColors.surfaceBorderLight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox.adaptive(
                              value: selected,
                              activeColor: DesignColors.accent,
                              onChanged: !canEditLayout ||
                                      (selected &&
                                          _dashboardMetrics.length == 1)
                                  ? null
                                  : (value) => setState(() {
                                        if (value == true && !selected) {
                                          _dashboardMetrics.add(metric.id);
                                        } else if (value == false &&
                                            selected &&
                                            _dashboardMetrics.length > 1) {
                                          _dashboardMetrics.remove(metric.id);
                                        }
                                      }),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(metric.label,
                                      style: TextStyle(
                                          color: text,
                                          fontWeight: FontWeight.w700)),
                                  Text(metric.description,
                                      style: TextStyle(
                                          color: secondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            if (selected) ...[
                              IconButton(
                                tooltip: 'Move ${metric.label} earlier',
                                visualDensity: VisualDensity.compact,
                                onPressed: !canEditLayout || index == 0
                                    ? null
                                    : () => _moveDashboardMetric(index, -1),
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                              IconButton(
                                tooltip: 'Move ${metric.label} later',
                                visualDensity: VisualDensity.compact,
                                onPressed: !canEditLayout ||
                                        index == _dashboardMetrics.length - 1
                                    ? null
                                    : () => _moveDashboardMetric(index, 1),
                                icon: const Icon(Icons.arrow_downward_rounded),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'What appears in the app',
                    subtitle:
                        'Show the work areas this shop uses. Hidden areas keep their data and permissions, and can be turned back on here.',
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 980
                        ? 3
                        : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                    const spacing = 10.0;
                    final cardWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    final availableActions = businessLayoutActions
                        .where((action) =>
                            !getIt<AuthService>().isLocalWorkspace ||
                            LocalWorkspaceCapabilities.supportsPath(
                                action.path))
                        .toList();
                    final visibleCount = availableActions
                        .where((action) =>
                            selectedLayout.isActionVisible(action.path))
                        .length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$visibleCount of ${availableActions.length} work areas shown',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: DesignColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: availableActions.map((action) {
                            final visible =
                                selectedLayout.isActionVisible(action.path);
                            final canHide =
                                businessLayoutCanHideAction(action.path);
                            final actionLabel = selectedLayout.actionLabel(
                              action.path,
                              action.path == '/products'
                                  ? selectedLayout.productsLabel
                                  : action.label,
                            );
                            return SizedBox(
                              width: cardWidth,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: !canEditLayout || !canHide
                                    ? null
                                    : () => _toggleActionVisibility(
                                          action.path,
                                        ),
                                child: AnimatedContainer(
                                  duration: DesignAnimation.fast,
                                  constraints:
                                      const BoxConstraints(minHeight: 82),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: visible
                                        ? DesignColors.accent.withValues(
                                            alpha: isDark ? .16 : .08)
                                        : isDark
                                            ? DesignColors.darkSurfaceElevated
                                            : DesignColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: visible
                                          ? DesignColors.accent
                                              .withValues(alpha: .55)
                                          : isDark
                                              ? DesignColors.darkBorder
                                              : DesignColors.surfaceBorderLight,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        action.icon,
                                        size: 20,
                                        color: visible
                                            ? DesignColors.accent
                                            : secondary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              actionLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: text,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              canHide
                                                  ? visible
                                                      ? 'Shown in app'
                                                      : 'Hidden from app'
                                                  : 'Always available',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: secondary,
                                                fontSize: 10.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        canHide
                                            ? visible
                                                ? Icons.visibility_rounded
                                                : Icons.visibility_off_rounded
                                            : Icons.lock_outline_rounded,
                                        size: 17,
                                        color: visible
                                            ? DesignColors.accent
                                            : secondary,
                                      ),
                                      IconButton(
                                        tooltip: 'Rename $actionLabel',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 40,
                                        ),
                                        padding: EdgeInsets.zero,
                                        onPressed: !canEditLayout
                                            ? null
                                            : () => _renameAction(
                                                  action.path,
                                                  actionLabel,
                                                ),
                                        icon: const Icon(
                                          Icons.edit_rounded,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Opening screen',
                    subtitle:
                        'Choose the first work area after sign-in. Staff still need permission to open it.',
                  ),
                  const SizedBox(height: 10),
                  if (_priorityPaths.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? DesignColors.darkSurfaceElevated
                            : DesignColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                          'Add a work area below before choosing a start screen.'),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                          'layout-start-$_startPath-${_priorityPaths.join('|')}'),
                      initialValue: _priorityPaths.contains(_startPath)
                          ? _startPath
                          : _priorityPaths.first,
                      decoration: const InputDecoration(
                        labelText: 'Open Counterbase at',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.login_rounded),
                      ),
                      items: _priorityPaths.map((path) {
                        final action = businessLayoutActions.firstWhere(
                          (item) => item.path == path,
                          orElse: () => businessLayoutActions.first,
                        );
                        final label = _actionLabels[path] ??
                            selectedLayout.actionLabel(path, action.label);
                        return DropdownMenuItem<String>(
                          value: path,
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: !canEditLayout
                          ? null
                          : (path) => setState(() => _startPath = path),
                    ),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Work areas and actions',
                    subtitle:
                        'Pin the screens your team uses most, arrange them, and give shortcuts familiar names.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Suggested for ${selectedPreset.name}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: DesignColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (_priorityPaths.isEmpty)
                    _EmptyActionsCard(isDark: isDark)
                  else
                    ..._priorityPaths.asMap().entries.map((entry) {
                      final action = businessLayoutActions.firstWhere(
                        (item) => item.path == entry.value,
                        orElse: () => businessLayoutActions.first,
                      );
                      final actionLabel = _actionLabels[action.path] ??
                          selectedLayout.actionLabel(action.path, action.label);
                      return Padding(
                        key: ValueKey(action.path),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isDark
                                    ? DesignColors.darkBorder
                                    : DesignColors.surfaceBorderLight,
                              ),
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  DesignColors.accent.withValues(alpha: .12),
                              child: Icon(action.icon,
                                  size: 20, color: DesignColors.accent),
                            ),
                            title: Text(actionLabel,
                                style: TextStyle(
                                    color: text, fontWeight: FontWeight.w600)),
                            subtitle: Text('Pinned ${entry.key + 1}',
                                style: TextStyle(color: secondary)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Move up',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: !canEditLayout || entry.key == 0
                                      ? null
                                      : () => _moveAction(entry.key, -1),
                                  icon: const Icon(Icons.arrow_upward_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Move down',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: !canEditLayout ||
                                          entry.key == _priorityPaths.length - 1
                                      ? null
                                      : () => _moveAction(entry.key, 1),
                                  icon:
                                      const Icon(Icons.arrow_downward_rounded),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Shortcut options',
                                  enabled: canEditLayout,
                                  onSelected: (value) {
                                    if (value == 'rename') {
                                      _renameAction(action.path, actionLabel);
                                    } else if (value == 'remove') {
                                      _removeAction(entry.key);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename shortcut'),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Unpin from quick access'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: !canEditLayout || availableActions.isEmpty
                            ? null
                            : () => _addActions(availableActions),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Pin work area'),
                      ),
                      TextButton.icon(
                        onPressed: !canEditLayout
                            ? null
                            : () => setState(() {
                                  _hiddenPaths =
                                      businessLayoutDefaultHiddenPaths(
                                    _profileId,
                                    _additionalProfileIds,
                                  );
                                  _priorityPaths = _supportedPriorityPaths(
                                    businessLayoutDefaultPriorityPaths(
                                      _profileId,
                                      _additionalProfileIds,
                                    ),
                                  );
                                  _actionLabels.clear();
                                  _startPath = _priorityPaths.isEmpty
                                      ? null
                                      : _priorityPaths.first;
                                  _terminologyOverrides.clear();
                                  _defaultBaseUnit =
                                      selectedPreset.defaultBaseUnit;
                                  _allowFractionsForNewProducts =
                                      selectedPreset.defaultAllowFractions;
                                  _trackInventoryForNewProducts = selectedPreset
                                      .defaultTrackInventoryForNewProducts;
                                  _posProductView =
                                      selectedPreset.defaultPosProductView;
                                  _showPosCategories =
                                      selectedPreset.defaultShowPosCategories;
                                  _showPosFavorites =
                                      selectedPreset.defaultShowPosFavorites;
                                  _showPosCustomer =
                                      selectedPreset.defaultShowPosCustomer;
                                  _posQuickActions = _supportedPosQuickActions(
                                    businessLayoutDefaultPosQuickActions(
                                      _profileId,
                                      _additionalProfileIds,
                                    ),
                                  );
                                  _posProductPages.clear();
                                  _dashboardMetrics = [
                                    ...businessLayoutDefaultDashboardMetrics(
                                      _profileId,
                                      _additionalProfileIds,
                                    )
                                  ];
                                  _dashboardSections = [
                                    ...businessLayoutDefaultDashboardSections(
                                      _profileId,
                                      _additionalProfileIds,
                                    )
                                  ];
                                  _productFieldKeys = [
                                    ...businessLayoutDefaultProductFieldKeys(
                                      _profileId,
                                      _additionalProfileIds,
                                      customFields: _customProductFields,
                                    ),
                                  ];
                                }),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Reset to profile defaults'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            color: DesignColors.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Pinned work areas move earlier in navigation. Hidden areas disappear from the menu but keep their data and permissions. Profiles change wording and product browsing defaults; payment, stock, and staff permissions keep their existing rules.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: secondary, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? DesignColors.darkBorder
                        : DesignColors.surfaceBorderLight,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: !canEditLayout ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Saving layout…' : 'Save shop layout'),
                  style: FilledButton.styleFrom(
                    backgroundColor: DesignColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleActionVisibility(String path) {
    if (!businessLayoutCanHideAction(path)) return;
    setState(() {
      if (_hiddenPaths.contains(path)) {
        _hiddenPaths.remove(path);
      } else {
        _hiddenPaths.add(path);
        _priorityPaths.remove(path);
        _posQuickActions.removeWhere(
          (id) => businessLayoutPosAction(id)?.path == path,
        );
        if (_startPath == path) {
          _startPath = _priorityPaths.isEmpty ? null : _priorityPaths.first;
        }
      }
    });
  }

  void _moveAction(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _priorityPaths.length) return;
    setState(() {
      final item = _priorityPaths.removeAt(index);
      _priorityPaths.insert(target, item);
    });
  }

  void _togglePosQuickAction(String id) {
    setState(() {
      if (_posQuickActions.contains(id)) {
        _posQuickActions.remove(id);
        if (id == 'customer') _showPosCustomer = false;
        if (id == 'favorites') _showPosFavorites = false;
      } else {
        _posQuickActions.add(id);
        if (id == 'customer') _showPosCustomer = true;
        if (id == 'favorites') _showPosFavorites = true;
      }
    });
  }

  void _movePosQuickAction(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _posQuickActions.length) return;
    setState(() {
      final action = _posQuickActions.removeAt(index);
      _posQuickActions.insert(target, action);
    });
  }

  void _moveDashboardMetric(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _dashboardMetrics.length) return;
    setState(() {
      final metric = _dashboardMetrics.removeAt(index);
      _dashboardMetrics.insert(target, metric);
    });
  }

  Future<void> _addCustomProductField() async {
    if (_customProductFields.length >= 20) {
      showGlassSnackBar(
        context,
        'You can add up to 20 custom product details.',
        icon: Icons.info_outline_rounded,
        color: DesignColors.error,
      );
      return;
    }
    final labelController = TextEditingController();
    final hintController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add product detail'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Field name',
                hintText: 'e.g. Shelf location',
              ),
            ),
            TextField(
              controller: hintController,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Entry hint (optional)',
                hintText: 'e.g. Aisle and shelf',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final label = labelController.text.trim();
              if (label.isNotEmpty) {
                Navigator.of(dialogContext).pop({
                  'label': label,
                  'hint': hintController.text.trim(),
                });
              }
            },
            child: const Text('Add field'),
          ),
        ],
      ),
    );
    labelController.dispose();
    hintController.dispose();
    if (result == null || !mounted) return;

    final label = result['label']!.trim();
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) {
      showGlassSnackBar(
        context,
        'Use a field name with letters or numbers.',
        icon: Icons.info_outline_rounded,
        color: DesignColors.error,
      );
      return;
    }
    final occupied = {
      ...businessLayoutPreset(_profileId)
          .productFields
          .map((field) => field.key),
      ..._customProductFields.map((field) => field.key),
    };
    final base = 'custom_${slug.length > 28 ? slug.substring(0, 28) : slug}';
    var key = base;
    var suffix = 2;
    while (occupied.contains(key)) {
      final suffixText = '_$suffix';
      final keep = 40 - suffixText.length;
      key = '${base.length > keep ? base.substring(0, keep) : base}$suffixText';
      suffix++;
    }
    final field = BusinessLayoutProductField(
      key: key,
      label: label.length > 40 ? label.substring(0, 40) : label,
      hint: result['hint'] ?? '',
    );
    setState(() {
      _customProductFields.add(field);
      _productFieldKeys.add(field.key);
    });
  }

  Future<void> _removeCustomProductField(
    BusinessLayoutProductField field,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove custom detail?'),
        content: Text(
          '“${field.label}” will disappear from product forms. Saved product values are retained in the catalog.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep field'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() {
      _customProductFields.removeWhere((item) => item.key == field.key);
      _productFieldKeys.remove(field.key);
    });
  }

  void _removeAction(int index) {
    setState(() {
      final removedPath = _priorityPaths.removeAt(index);
      if (_startPath == removedPath) {
        _startPath = _priorityPaths.isEmpty ? null : _priorityPaths.first;
      }
    });
  }

  Future<void> _renameAction(String path, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename shortcut'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Shortcut name',
            hintText: 'For example, Stock or Till',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save name'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final label = result.trim();
    setState(() {
      if (label.isEmpty) {
        _actionLabels.remove(path);
      } else {
        _actionLabels[path] = label;
      }
    });
  }

  Future<void> _addActions(List<BusinessLayoutAction> actions) async {
    final selectableActions = actions
        .where((action) =>
            !_priorityPaths.contains(action.path) &&
            !_hiddenPaths.contains(action.path))
        .toList(growable: false);
    if (selectableActions.isEmpty) return;

    final selected = <String>{};
    final selectedPreset = businessLayoutPreset(_profileId);
    final selectedLayout = BusinessLayoutConfig(
      preset: selectedPreset,
      additionalProfileIds: _additionalProfileIds,
      priorityPaths: _priorityPaths,
    );
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? DesignColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SectionHeading(
                title: 'Pin work areas',
                subtitle: 'Choose screens to bring forward in navigation.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: selectableActions
                      .map((action) => CheckboxListTile(
                            value: selected.contains(action.path),
                            activeColor: DesignColors.accent,
                            secondary:
                                Icon(action.icon, color: DesignColors.accent),
                            title: Text(_actionLabels[action.path] ??
                                selectedLayout.actionLabel(
                                    action.path, action.label)),
                            onChanged: (checked) => setSheetState(() {
                              if (checked == true) {
                                selected.add(action.path);
                              } else {
                                selected.remove(action.path);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(sheetContext).pop(selected.toList()),
                  child: Text(selected.isEmpty
                      ? 'Select at least one'
                      : 'Add ${selected.length} ${selected.length == 1 ? 'area' : 'areas'}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final additions = result
        .where((path) =>
            !_priorityPaths.contains(path) && !_hiddenPaths.contains(path))
        .toSet()
        .toList(growable: false);
    if (additions.isEmpty) return;
    setState(() {
      _priorityPaths.addAll(additions);
      _startPath ??= _priorityPaths.isEmpty ? null : _priorityPaths.first;
    });
  }

  Future<void> _editProductWording() async {
    final preset = businessLayoutPreset(_profileId);
    final current = BusinessLayoutConfig(
      preset: preset,
      additionalProfileIds: _additionalProfileIds,
      priorityPaths: _priorityPaths,
      terminologyOverrides: _terminologyOverrides,
      baseUnitOverride: _defaultBaseUnit,
      posProductView: _posProductView,
      showPosCategories: _showPosCategories,
      showPosFavorites: _showPosFavorites,
      showPosCustomer: _showPosCustomer,
      posQuickActions: _posQuickActions,
      dashboardMetrics: _dashboardMetrics,
      dashboardSections: _dashboardSections,
    );
    final fields = <_LayoutTermField>[
      _LayoutTermField(
          'productSingular', 'Single item name', current.productSingular),
      _LayoutTermField(
          'productsLabel', 'Items section name', current.productsLabel),
      _LayoutTermField(
          'customerSingular', 'Single customer name', current.customerSingular),
      _LayoutTermField(
          'customersLabel', 'Customer section name', current.customersLabel),
      _LayoutTermField(
          'productCodeLabel', 'Item code label', current.productCodeLabel),
      _LayoutTermField(
          'productCodeHint', 'Item code prompt', current.productCodeHint, 2),
      _LayoutTermField(
          'productNameHint', 'Item name prompt', current.productNameHint, 2),
      _LayoutTermField('catalogSearchHint', 'Catalogue search prompt',
          current.catalogSearchHint),
      _LayoutTermField(
          'posSearchHint', 'POS search prompt', current.posSearchHint),
    ];
    final controllers = {
      for (final field in fields)
        field.key: TextEditingController(text: field.value),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shop wording'),
        content: SizedBox(
          width: 480,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .65,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields
                    .map((field) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: controllers[field.key],
                            maxLength: 80,
                            maxLines: field.maxLines,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: field.label,
                              helperText: 'Clear to use the profile suggestion',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop({
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: const Text('Use wording'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (result == null || !mounted) return;
    final defaults = {
      'productSingular': preset.productSingular,
      'productsLabel': preset.productsLabel,
      'productCodeLabel': preset.productCodeLabel,
      'productCodeHint': preset.productCodeHint,
      'productNameHint': preset.productNameHint,
      'catalogSearchHint': preset.catalogSearchHint,
      'posSearchHint': preset.posSearchHint,
      'customerSingular': preset.customerSingular,
      'customersLabel': preset.customersLabel,
    };
    setState(() {
      _terminologyOverrides = {
        for (final entry in result.entries)
          if (entry.value.isNotEmpty && entry.value != defaults[entry.key])
            entry.key: entry.value,
      };
    });
  }

  Future<void> _chooseAdditionalProfiles() async {
    final selected = await showBusinessLayoutProfilePicker(
      context,
      primaryProfileId: _profileId,
      selectedProfileIds: _additionalProfileIds,
    );
    if (selected == null || !mounted) return;
    _applyAdditionalProfiles(selected);
  }

  void _applyAdditionalProfiles(List<String> profileIds) {
    final previousProfileIds = [..._additionalProfileIds];
    final normalized = businessLayoutAdditionalPresets(_profileId, profileIds)
        .map((profile) => profile.id)
        .toList(growable: false);
    final previousVisibleRecommendations = businessLayoutDefaultVisiblePaths(
      _profileId,
      previousProfileIds,
    ).toSet();
    final nextVisibleRecommendations = businessLayoutDefaultVisiblePaths(
      _profileId,
      normalized,
    ).toSet();
    setState(() {
      for (final path in previousVisibleRecommendations.difference(
        nextVisibleRecommendations,
      )) {
        if (!_hiddenPaths.contains(path)) _hiddenPaths.add(path);
      }
      for (final path in nextVisibleRecommendations.difference(
        previousVisibleRecommendations,
      )) {
        _hiddenPaths.remove(path);
      }

      final previousPriorityRecommendations =
          businessLayoutDefaultPriorityPaths(_profileId, previousProfileIds);
      final nextPriorityRecommendations =
          businessLayoutDefaultPriorityPaths(_profileId, normalized)
              .where((path) => !_hiddenPaths.contains(path));
      _priorityPaths = businessLayoutReconcileRecommendations(
        current: _priorityPaths,
        previousRecommendations: previousPriorityRecommendations,
        nextRecommendations: nextPriorityRecommendations,
      );
      _priorityPaths = _supportedPriorityPaths(_priorityPaths);

      _dashboardMetrics = businessLayoutReconcileRecommendations(
        current: _dashboardMetrics,
        previousRecommendations: businessLayoutDefaultDashboardMetrics(
          _profileId,
          previousProfileIds,
        ),
        nextRecommendations: businessLayoutDefaultDashboardMetrics(
          _profileId,
          normalized,
        ),
      );
      _dashboardSections = businessLayoutReconcileRecommendations(
        current: _dashboardSections,
        previousRecommendations: businessLayoutDefaultDashboardSections(
          _profileId,
          previousProfileIds,
        ),
        nextRecommendations: businessLayoutDefaultDashboardSections(
          _profileId,
          normalized,
        ),
      );
      _posQuickActions = _supportedPosQuickActions(
        businessLayoutReconcileRecommendations(
          current: _posQuickActions,
          previousRecommendations: businessLayoutDefaultPosQuickActions(
            _profileId,
            previousProfileIds,
          ),
          nextRecommendations: businessLayoutDefaultPosQuickActions(
            _profileId,
            normalized,
          ),
        ),
      );
      _showPosFavorites = _posQuickActions.contains('favorites');
      _showPosCustomer = _posQuickActions.contains('customer');

      final previousProductFieldRecommendations =
          businessLayoutDefaultProductFieldKeys(
        _profileId,
        previousProfileIds,
      );
      final nextProductFieldRecommendations =
          businessLayoutDefaultProductFieldKeys(_profileId, normalized);
      _productFieldKeys = businessLayoutReconcileRecommendations(
        current: _productFieldKeys,
        previousRecommendations: previousProductFieldRecommendations,
        nextRecommendations: nextProductFieldRecommendations,
      );

      _additionalProfileIds = normalized;
      final validPriorityPaths = _priorityPaths.toSet();
      if (_startPath != null && !validPriorityPaths.contains(_startPath)) {
        _startPath = _priorityPaths.firstOrNull;
      }
      _startPath ??= _priorityPaths.firstOrNull;
    });
  }

  Future<void> _editPosProductPage([
    BusinessLayoutProductPage? existing,
  ]) async {
    List<Map<String, dynamic>> products;
    try {
      final cachedProducts = await getIt<AppDatabase>().getAllProducts();
      products = cachedProducts
          .where((product) => product.isActive)
          .map((product) => {
                'id': product.id,
                'name': product.name,
                'sku': product.sku,
              })
          .toList(growable: false);
    } catch (_) {
      if (mounted) {
        final localWorkspace = getIt<AuthService>().isLocalWorkspace;
        showGlassSnackBar(
          context,
          localWorkspace
              ? 'Could not read the product catalog on this device. Your layout was not changed.'
              : 'Could not load the saved product catalog. Refresh the shop catalog and try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
      return;
    }
    if (!mounted) return;
    if (products.isEmpty) {
      showGlassSnackBar(
        context,
        getIt<AuthService>().isLocalWorkspace
            ? 'Add at least one product on this device before creating a product page.'
            : 'Sync this shop’s catalog on the POS first, then create a product page.',
        icon: Icons.inventory_2_outlined,
        color: DesignColors.warning,
      );
      return;
    }

    final page = await showDialog<BusinessLayoutProductPage>(
      context: context,
      builder: (context) => _PosProductPageEditor(
        products: products,
        existing: existing,
      ),
    );
    if (!mounted || page == null) return;
    final duplicateName = _posProductPages.any((item) =>
        item.id != page.id &&
        item.name.toLowerCase() == page.name.toLowerCase());
    if (duplicateName) {
      showGlassSnackBar(
        context,
        'Each quick page needs a different name.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    setState(() {
      final index = _posProductPages.indexWhere((item) => item.id == page.id);
      if (index < 0) {
        if (_posProductPages.length < 12) _posProductPages.add(page);
      } else {
        _posProductPages[index] = page;
      }
    });
  }

  void _movePosProductPage(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _posProductPages.length) return;
    setState(() {
      final page = _posProductPages.removeAt(index);
      _posProductPages.insert(target, page);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final layout = BusinessLayoutConfig(
        preset: businessLayoutPreset(_profileId),
        additionalProfileIds: [..._additionalProfileIds],
        priorityPaths: [..._priorityPaths],
        hiddenPaths: [..._hiddenPaths],
        actionLabels: {..._actionLabels},
        terminologyOverrides: {..._terminologyOverrides},
        baseUnitOverride: _defaultBaseUnit,
        allowFractionsForNewProducts: _allowFractionsForNewProducts,
        trackInventoryForNewProducts: _trackInventoryForNewProducts,
        startPath: _startPath,
        posProductView: _posProductView,
        showPosCategories: _showPosCategories,
        showPosFavorites: _showPosFavorites,
        showPosCustomer: _showPosCustomer,
        posQuickActions: [..._posQuickActions],
        posProductPages: [..._posProductPages],
        dashboardMetrics: [..._dashboardMetrics],
        dashboardSections: [..._dashboardSections],
        productFieldKeys: [..._productFieldKeys],
        customProductFields: [..._customProductFields],
      );
      final authService = getIt<AuthService>();
      final tenant = authService.currentUser?['tenant'];
      final currentSettings = tenant is Map && tenant['settings'] is Map
          ? Map<String, dynamic>.from(tenant['settings'] as Map)
          : <String, dynamic>{};
      await authService.updateTenantSession({
        'settings': {
          ...currentSettings,
          'businessLayout': layout.toJson(),
        },
      });
      ref.read(authControllerProvider.notifier).refreshFromService();
      if (mounted) {
        showGlassSnackBar(
          context,
          'Layout saved on this device',
          icon: Icons.check_circle_rounded,
          color: DesignColors.success,
        );
      }
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Could not save the layout on this device. Please try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LayoutTermField {
  const _LayoutTermField(
    this.key,
    this.label,
    this.value, [
    this.maxLines = 1,
  ]);

  final String key;
  final String label;
  final String value;
  final int maxLines;
}

String _unitLabel(String unit) =>
    unit.isEmpty ? unit : '${unit[0].toUpperCase()}${unit.substring(1)}';

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final BusinessLayoutPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? DesignColors.accent.withValues(alpha: isDark ? .17 : .08)
          : (isDark ? DesignColors.darkSurface : Colors.white),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? DesignColors.accent
                  : (isDark
                      ? DesignColors.darkBorder
                      : DesignColors.surfaceBorderLight),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(preset.icon, color: DesignColors.accent, size: 21),
                const Spacer(),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: DesignColors.accent, size: 19),
              ]),
              const SizedBox(height: 11),
              Text(
                preset.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                preset.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.3,
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
              )),
    ]);
  }
}

class _EmptyActionsCard extends StatelessWidget {
  const _EmptyActionsCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? DesignColors.darkBorder
                : DesignColors.surfaceBorderLight,
          ),
        ),
        child: const Text(
          'No shortcuts selected. Add work areas to bring them to the front.',
        ),
      );
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DesignColors.warning.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Only team members with permission to manage shop settings can change this shared layout.',
        ),
      );
}

class _PosProductPageEditor extends StatefulWidget {
  const _PosProductPageEditor({
    required this.products,
    this.existing,
  });

  final List<Map<String, dynamic>> products;
  final BusinessLayoutProductPage? existing;

  @override
  State<_PosProductPageEditor> createState() => _PosProductPageEditorState();
}

class _PosProductPageEditorState extends State<_PosProductPageEditor> {
  late final TextEditingController _nameController;
  final Set<String> _selectedProductIds = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    final availableIds = widget.products
        .map((product) => product['id']?.toString())
        .whereType<String>()
        .toSet();
    _selectedProductIds.addAll(
      (widget.existing?.productIds ?? const <String>[])
          .where(availableIds.contains)
          .take(32),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedProductIds.isEmpty) return;
    final existing = widget.existing;
    Navigator.of(context).pop(BusinessLayoutProductPage(
      id: existing?.id ??
          'page_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name,
      productIds: _selectedProductIds.toList(growable: false),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        220;
    final visibleProducts = widget.products.where((product) {
      if (query.isEmpty) return true;
      final name = product['name']?.toString().toLowerCase() ?? '';
      final code = product['sku']?.toString().toLowerCase() ?? '';
      return name.contains(query) || code.contains(query);
    }).toList(growable: false);

    return AlertDialog(
      title:
          Text(widget.existing == null ? 'Create POS page' : 'Edit POS page'),
      content: SizedBox(
        width: 520,
        height: availableHeight.clamp(180.0, 520.0).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              maxLength: 28,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Page name',
                hintText: 'e.g. Textbooks or Fast movers',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                labelText: 'Find products',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_selectedProductIds.length} of 32 products selected',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: visibleProducts.isEmpty
                  ? const Center(child: Text('No products match that search.'))
                  : ListView.builder(
                      itemCount: visibleProducts.length,
                      itemBuilder: (context, index) {
                        final product = visibleProducts[index];
                        final id = product['id']?.toString() ?? '';
                        final selected = _selectedProductIds.contains(id);
                        final canSelect =
                            selected || _selectedProductIds.length < 32;
                        return CheckboxListTile(
                          value: selected,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            product['name']?.toString() ?? 'Unnamed product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(product['sku']?.toString() ?? ''),
                          onChanged: !canSelect || id.isEmpty
                              ? null
                              : (checked) => setState(() {
                                    if (checked == true) {
                                      _selectedProductIds.add(id);
                                    } else {
                                      _selectedProductIds.remove(id);
                                    }
                                  }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _nameController.text.trim().isEmpty || _selectedProductIds.isEmpty
                  ? null
                  : _save,
          child: const Text('Save page'),
        ),
      ],
    );
  }
}
