import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class BusinessLayoutScreen extends ConsumerStatefulWidget {
  const BusinessLayoutScreen({super.key});

  @override
  ConsumerState<BusinessLayoutScreen> createState() =>
      _BusinessLayoutScreenState();
}

class _BusinessLayoutScreenState extends ConsumerState<BusinessLayoutScreen> {
  late String _profileId;
  late List<String> _priorityPaths;
  bool _initialized = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?['role']?.toString().toUpperCase() == 'ADMIN';
    if (!_initialized) {
      final config = businessLayoutFromUser(user);
      _profileId = config.profileId;
      _priorityPaths = [...config.priorityPaths];
      _initialized = true;
    }

    final selectedPreset = businessLayoutPreset(_profileId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurface : Colors.white;
    final text =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final availableActions = businessLayoutActions
        .where((action) => !_priorityPaths.contains(action.path))
        .toList();

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Business layout'),
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
                    'Choose a business starting point, then put your team’s most-used areas first. You can change this whenever the shop grows.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: secondary,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Business profile',
                    subtitle: 'This applies to the whole shop on every device.',
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final width = (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: businessLayoutPresets.map((preset) {
                        final selected = preset.id == _profileId;
                        return SizedBox(
                          width: width,
                          child: _ProfileCard(
                            preset: preset,
                            selected: selected,
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      if (_profileId != preset.id) {
                                        _profileId = preset.id;
                                        _priorityPaths = [
                                          ...preset.priorityPaths
                                        ];
                                      }
                                    }),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    title: 'Layout actions',
                    subtitle:
                        'Move your most-used work areas to the front of navigation.',
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
                            title: Text(action.label,
                                style: TextStyle(
                                    color: text, fontWeight: FontWeight.w600)),
                            subtitle: Text('Priority ${entry.key + 1}',
                                style: TextStyle(color: secondary)),
                            trailing: SizedBox(
                              width: 96,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: 'Move up',
                                    onPressed: _saving || entry.key == 0
                                        ? null
                                        : () => _moveAction(entry.key, -1),
                                    icon:
                                        const Icon(Icons.arrow_upward_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove shortcut',
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() =>
                                            _priorityPaths.removeAt(entry.key)),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
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
                        onPressed: _saving || availableActions.isEmpty
                            ? null
                            : () => _addActions(availableActions),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add work area'),
                      ),
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _priorityPaths = [
                                  ...selectedPreset.priorityPaths
                                ]),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Use suggested order'),
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
                            'Shortcuts only change the order of existing screens. Each team member still sees only the areas their role allows.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: secondary, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isAdmin) ...[
                    const SizedBox(height: 16),
                    const _PermissionNotice(),
                  ],
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
                  onPressed: _saving || !isAdmin ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label:
                      Text(_saving ? 'Saving layout…' : 'Save business layout'),
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

  void _moveAction(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _priorityPaths.length) return;
    setState(() {
      final item = _priorityPaths.removeAt(index);
      _priorityPaths.insert(target, item);
    });
  }

  Future<void> _addActions(List<BusinessLayoutAction> actions) async {
    final selected = <String>{};
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
                title: 'Add work areas',
                subtitle: 'Choose screens to bring forward.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: actions
                      .map((action) => CheckboxListTile(
                            value: selected.contains(action.path),
                            activeColor: DesignColors.accent,
                            secondary:
                                Icon(action.icon, color: DesignColors.accent),
                            title: Text(action.label),
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
    setState(() => _priorityPaths.addAll(result));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final layout = BusinessLayoutConfig(
        preset: businessLayoutPreset(_profileId),
        priorityPaths: [..._priorityPaths],
      );
      final updated = await getIt<ApiClient>().updateCurrentTenant(
        settings: {'businessLayout': layout.toJson()},
      );
      await getIt<AuthService>().updateTenantSession({
        'id': updated['id'],
        'name': updated['name'],
        'settings': updated['settings'],
      });
      ref.read(authControllerProvider.notifier).refreshFromService();
      if (mounted) {
        showGlassSnackBar(
          context,
          'Business layout saved for this shop',
          icon: Icons.check_circle_rounded,
          color: DesignColors.success,
        );
      }
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Could not save the layout. Check your connection and try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

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
          'Only a workspace administrator can save a business wide layout.',
        ),
      );
}
