import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_table_frame.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// One staff profile kept on this computer.
class DesktopLocalStaff {
  const DesktopLocalStaff({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
  });

  final String id;
  final String name;
  final String role;
  final bool active;
}

/// A role and what it allows, for the guide beside the table.
class DesktopStaffRole {
  const DesktopStaffRole({required this.name, required this.description});

  final String name;
  final String description;
}

/// Staff on this device, on a computer: a table of profiles and, on the right,
/// either the open profile or the guide to what each role can do.
///
/// Plain data in, callbacks out. The routed screen owns the account service
/// and the add / edit form.
class DesktopLocalStaffView extends StatefulWidget {
  const DesktopLocalStaffView({
    super.key,
    required this.isOwner,
    required this.staff,
    required this.roles,
    required this.saving,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
  });

  final bool isOwner;
  final List<DesktopLocalStaff> staff;
  final List<DesktopStaffRole> roles;
  final bool saving;
  final VoidCallback onAdd;
  final ValueChanged<DesktopLocalStaff> onEdit;
  final ValueChanged<DesktopLocalStaff> onToggle;

  @override
  State<DesktopLocalStaffView> createState() => _DesktopLocalStaffViewState();
}

class _DesktopLocalStaffViewState extends State<DesktopLocalStaffView> {
  String? _selectedId;

  DesktopLocalStaff? get _selected {
    for (final s in widget.staff) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;

    if (!widget.isOwner) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageHeader(title: 'Staff on this device'),
          Expanded(
            child: DesktopEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Owner access required',
              message: 'Only this device\'s workspace owner can manage staff.',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'Staff on this device',
          subtitle: 'Each person signs in with their own PIN and role. '
              'Profiles and permissions stay on this computer; they are not '
              'cloud accounts. Set up staff separately on every device that '
              'needs its own team.',
          actions: [
            FilledButton.icon(
              key: const ValueKey('local-staff-add'),
              style: desktopPrimaryButton(context),
              onPressed: widget.saving ? null : widget.onAdd,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              label: const Text('Add staff'),
            ),
          ],
        ),
        Expanded(
          child: DesktopInspectorLayout(
            onClose: () => setState(() => _selectedId = null),
            inspector: _selected == null ? _guide(p) : _profile(_selected!, p),
            main: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesktopTokens.gutter,
                0,
                DesktopTokens.gutter,
                DesktopTokens.gutter,
              ),
              child: DesktopTableFrame(
      child: _table(p),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _table(DesktopPalette p) {
    return DesktopDataTable<DesktopLocalStaff>(
      key: const ValueKey('local-staff-table'),
      rows: widget.staff,
      rowId: (s) => s.id,
      selectedId: _selectedId,
      minWidth: 420,
      initialSortColumn: 0,
      onRowSelected: (s) => setState(() => _selectedId = s.id),
      onRowActivated: widget.saving ? null : widget.onEdit,
      columns: [
        DesktopColumn<DesktopLocalStaff>(
          label: 'Name',
          flex: 3,
          minWidth: 160,
          sortBy: (s) => s.name.toLowerCase(),
          cell: (context, s) => DesktopCellText(s.name, strong: true),
        ),
        DesktopColumn<DesktopLocalStaff>(
          label: 'Role',
          flex: 2,
          minWidth: 120,
          sortBy: (s) => s.role.toLowerCase(),
          cell: (context, s) => DesktopCellText(s.role, muted: true),
        ),
        DesktopColumn<DesktopLocalStaff>(
          label: 'Access',
          width: 110,
          sortBy: (s) => s.active ? 0 : 1,
          cell: (context, s) => DesktopStatusChip(
            label: s.active ? 'Active' : 'Paused',
            color: s.active ? DesignColors.success : DesignColors.warning,
          ),
        ),
      ],
      empty: DesktopEmptyState(
        icon: Icons.groups_2_outlined,
        title: 'No staff profiles yet',
        message: 'Create one profile for each person who uses this register.',
        action: FilledButton(
          style: desktopPrimaryButton(context),
          onPressed: widget.saving ? null : widget.onAdd,
          child: const Text('Add first staff member'),
        ),
      ),
    );
  }

  Widget _profile(DesktopLocalStaff s, DesktopPalette p) {
    final description = [
      for (final r in widget.roles)
        if (r.name == s.role) r.description,
    ];
    return DesktopInspector(
      key: const ValueKey('local-staff-inspector'),
      title: s.name,
      subtitle: s.role,
      onClose: () => setState(() => _selectedId = null),
      footer: Row(
        children: [
          Expanded(
            child: FilledButton(
              key: const ValueKey('local-staff-edit'),
              style: desktopPrimaryButton(context),
              onPressed: widget.saving ? null : () => widget.onEdit(s),
              child: const Text('Edit profile'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('local-staff-toggle'),
            style: desktopSecondaryButton(context),
            onPressed: widget.saving ? null : () => widget.onToggle(s),
            child: Text(s.active ? 'Pause access' : 'Enable access'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopStatusChip(
            label: s.active ? 'Active' : 'Paused',
            color: s.active ? DesignColors.success : DesignColors.warning,
          ),
          const SizedBox(height: 14),
          if (description.isNotEmpty)
            Text(
              description.first,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            s.active
                ? 'Signs in with their own PIN. Pausing stops them signing in '
                    'without deleting the profile.'
                : 'Cannot sign in until access is enabled again.',
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guide(DesktopPalette p) {
    return DesktopInspector(
      key: const ValueKey('local-staff-guide'),
      title: 'What each role can do',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final role in widget.roles) ...[
            Text(
              role.name,
              style: GoogleFonts.sora(
                color: p.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              role.description,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
