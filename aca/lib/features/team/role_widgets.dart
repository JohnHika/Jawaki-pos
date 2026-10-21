import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../account/sheet_kit.dart';
import 'team_logic.dart';

/// One selectable role with its one-line description: used when adding staff and
/// when changing a role. [note] replaces the check mark with a small caption
/// ("Current role") for options that can't be picked.
class RoleOptionTile extends StatelessWidget {
  const RoleOptionTile({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final RoleInfo role;
  final bool selected;
  final VoidCallback? onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final tone = StatusTone.role(role.role);
    final radius = BorderRadius.circular(14);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.brand.withValues(alpha: 0.10) : p.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: selected ? p.brand : p.border, width: selected ? 1.6 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? p.brand : p.textFaint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(Fmt.label(role.role),
                              style: TextStyle(fontWeight: FontWeight.w800, color: p.toneColor(tone))),
                          if (note != null) Text(note!, style: TextStyle(color: p.textFaint, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(role.description, style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.35)),
                    ],
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

/// Bottom sheet that lets the signed-in person pick a new role for [name].
/// Only roles they may hand out are listed; the current one is shown but not selectable.
/// Resolves to the chosen role key, or null.
Future<String?> showRolePicker(
  BuildContext context, {
  required String name,
  required String currentRole,
  required List<RoleInfo> roles,
}) {
  final options = assignableRoles(roles);
  return showFormSheet<String>(
    context,
    builder: (ctx) => SheetBody(
      title: 'Change role',
      message: 'Pick the access level $name should have. You can only hand out roles your own role allows.',
      children: [
        for (final r in options) ...[
          RoleOptionTile(
            role: r,
            selected: r.role == currentRole,
            note: r.role == currentRole ? 'Current role' : null,
            onTap: r.role == currentRole ? null : () => Navigator.pop(ctx, r.role),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ],
    ),
  );
}
