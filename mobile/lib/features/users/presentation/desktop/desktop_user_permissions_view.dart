import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_table_frame.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../data/models/permission_catalog.dart';

/// What one permission is for this person.
enum DesktopPermState { inherited, granted, revoked }

/// A role that can be given or taken away.
class DesktopRoleToggle {
  const DesktopRoleToggle({
    required this.id,
    required this.name,
    required this.assigned,
  });

  final String id;
  final String name;
  final bool assigned;
}

/// One person's roles and permission overrides on a computer.
///
/// Left: the roles to switch on or off. Right: every permission grouped by
/// area, each with Inherit / Grant / Revoke. "Inherit" follows the roles;
/// "Grant" adds one the roles do not give; "Revoke" removes one the roles do
/// give and always wins.
///
/// Plain data in, callbacks out. Nothing is saved here.
class DesktopUserPermissionsView extends StatefulWidget {
  const DesktopUserPermissionsView({
    super.key,
    required this.userLabel,
    required this.roles,
    required this.groups,
    required this.fromRoles,
    required this.granted,
    required this.revoked,
    required this.onToggleRole,
    required this.onSetOverride,
    this.busy = false,
  });

  /// "Name · email", so it is clear whose access is changing.
  final String userLabel;
  final List<DesktopRoleToggle> roles;
  final List<PermissionFeatureGroup> groups;
  final Set<String> fromRoles;
  final Set<String> granted;
  final Set<String> revoked;
  final void Function(DesktopRoleToggle role) onToggleRole;
  final void Function(String key, DesktopPermState target) onSetOverride;
  final bool busy;

  @override
  State<DesktopUserPermissionsView> createState() =>
      _DesktopUserPermissionsViewState();
}

class _DesktopUserPermissionsViewState
    extends State<DesktopUserPermissionsView> {
  final _search = TextEditingController();
  bool _onlyOverrides = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DesktopPermState _stateOf(String key) {
    if (widget.revoked.contains(key)) return DesktopPermState.revoked;
    if (widget.granted.contains(key)) return DesktopPermState.granted;
    return DesktopPermState.inherited;
  }

  int get _overrideCount => widget.granted.length + widget.revoked.length;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'User permissions',
          subtitle: widget.userLabel.isEmpty ? null : widget.userLabel,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesktopTokens.gutter,
              0,
              DesktopTokens.gutter,
              DesktopTokens.gutter,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 820;
                final roles = _rolesPanel(p);
                final perms = _permissions(p);
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      roles,
                      const SizedBox(height: 12),
                      Expanded(child: perms),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 280, child: SingleChildScrollView(child: roles)),
                    const SizedBox(width: 20),
                    Expanded(child: perms),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _rolesPanel(DesktopPalette p) {
    return DesktopPanel(
      title: 'Roles',
      subtitle: 'A person can hold several at once.',
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          for (final role in widget.roles)
            SizedBox(
              width: double.infinity,
              child: InkWell(
                key: ValueKey('perm-role-${role.id}'),
                borderRadius: BorderRadius.circular(8),
                hoverColor: p.hover,
                onTap: widget.busy ? null : () => widget.onToggleRole(role),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          role.name,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: role.assigned,
                        onChanged: widget.busy
                            ? null
                            : (_) => widget.onToggleRole(role),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _permissions(DesktopPalette p) {
    final terms = _search.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    bool matches(PermissionDef d, String groupName) {
      if (_onlyOverrides && _stateOf(d.key) == DesktopPermState.inherited) {
        return false;
      }
      final hay = '${d.label} ${d.key} $groupName'.toLowerCase();
      return terms.every(hay.contains);
    }

    final sections = <(PermissionFeatureGroup, List<PermissionDef>)>[
      for (final g in widget.groups)
        if (g.permissions.any((d) => matches(d, g.displayName)))
          (g, [for (final d in g.permissions) if (matches(d, g.displayName)) d]),
    ];

    return DesktopTableFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: DesktopSearchField(
                    controller: _search,
                    hint: 'Search permissions',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                DesktopFilterChip(
                  key: const ValueKey('perm-only-overrides'),
                  label: 'Overrides only',
                  count: _overrideCount,
                  selected: _onlyOverrides,
                  onTap: () => setState(() => _onlyOverrides = !_onlyOverrides),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: sections.isEmpty
                ? DesktopEmptyState(
                    icon: Icons.tune_rounded,
                    title: _onlyOverrides && terms.isEmpty
                        ? 'No overrides'
                        : 'No permissions match',
                    message: _onlyOverrides && terms.isEmpty
                        ? 'This person gets exactly what their roles give.'
                        : 'Try another word.',
                  )
                : ListView(
                    key: const ValueKey('perm-list'),
                    children: [
                      for (final (group, defs) in sections) ...[
                        _sectionHeader(p, group, defs.length),
                        for (final def in defs) _row(p, def),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    DesktopPalette p,
    PermissionFeatureGroup group,
    int count,
  ) {
    final overridden = group.permissions
        .where((d) => _stateOf(d.key) != DesktopPermState.inherited)
        .length;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: p.dark ? p.panel : p.panelAlt,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            group.displayName,
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            overridden == 0
                ? 'No overrides'
                : '$overridden override${overridden == 1 ? '' : 's'}',
            style: GoogleFonts.plusJakartaSans(
              color: overridden == 0 ? p.textFaint : p.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(DesktopPalette p, PermissionDef def) {
    final state = _stateOf(def.key);
    final fromRole = widget.fromRoles.contains(def.key);
    final effective = switch (state) {
      DesktopPermState.granted => true,
      DesktopPermState.revoked => false,
      DesktopPermState.inherited => fromRole,
    };
    final (chipLabel, chipColor) = switch (state) {
      DesktopPermState.granted => ('Granted', DesignColors.success),
      DesktopPermState.revoked => ('Revoked', DesignColors.error),
      DesktopPermState.inherited => fromRole
          ? ('From role', DesignColors.info)
          : ('None', DesignColors.textTertiary),
    };
    return Container(
      height: DesktopTokens.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Icon(
            effective ? Icons.check_rounded : Icons.remove_rounded,
            size: 16,
            color: effective
                ? (p.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                : p.textFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  def.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DesktopStatusChip(label: chipLabel, color: chipColor),
          const SizedBox(width: 12),
          _Segments(
            keyPrefix: def.key,
            value: state,
            enabled: !widget.busy,
            onChanged: (target) => widget.onSetOverride(def.key, target),
          ),
        ],
      ),
    );
  }
}

/// Inherit / Grant / Revoke as one bordered control, 28px tall.
class _Segments extends StatelessWidget {
  const _Segments({
    required this.keyPrefix,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String keyPrefix;
  final DesktopPermState value;
  final bool enabled;
  final ValueChanged<DesktopPermState> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    const labels = {
      DesktopPermState.inherited: 'Inherit',
      DesktopPermState.granted: 'Grant',
      DesktopPermState.revoked: 'Revoke',
    };
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: p.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in labels.entries)
            InkWell(
              key: ValueKey('perm-$keyPrefix-${entry.key.name}'),
              onTap: !enabled || entry.key == value
                  ? null
                  : () => onChanged(entry.key),
              hoverColor: p.hover,
              child: Container(
                height: 28,
                width: 60,
                alignment: Alignment.center,
                color: entry.key == value ? p.selected : Colors.transparent,
                child: Text(
                  entry.value,
                  style: GoogleFonts.plusJakartaSans(
                    color: entry.key == value ? p.text : p.textMuted,
                    fontSize: 12,
                    fontWeight:
                        entry.key == value ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
