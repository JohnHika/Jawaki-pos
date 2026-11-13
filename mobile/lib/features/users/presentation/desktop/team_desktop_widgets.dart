import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';

/// The three pages of the Team area, shown as tabs under the page title.
enum DesktopTeamTab { users, roles, invitations }

/// The Team page title with its tabs (Users, Roles, Invitations). Each tab is a
/// route of its own, so [onTab] navigates.
class DesktopTeamHeader extends StatelessWidget {
  const DesktopTeamHeader({
    super.key,
    required this.current,
    required this.onTab,
    this.showRoles = true,
    this.showInvitations = true,
    this.subtitle,
    this.actions = const [],
  });

  final DesktopTeamTab current;
  final ValueChanged<DesktopTeamTab> onTab;
  final bool showRoles;
  final bool showInvitations;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tabs = <(DesktopTeamTab, String)>[
      (DesktopTeamTab.users, 'Users'),
      if (showRoles) (DesktopTeamTab.roles, 'Roles'),
      if (showInvitations) (DesktopTeamTab.invitations, 'Invitations'),
    ];
    return DesktopPageHeader(
      title: 'Team',
      subtitle: subtitle,
      actions: actions,
      padding: const EdgeInsets.fromLTRB(
        DesktopTokens.gutter,
        16,
        DesktopTokens.gutter,
        8,
      ),
      bottom: tabs.length < 2
          ? null
          : Row(
              children: [
                for (final tab in tabs) ...[
                  DesktopFilterChip(
                    key: ValueKey('team-tab-${tab.$1.name}'),
                    label: tab.$2,
                    selected: tab.$1 == current,
                    onTap: () => onTab(tab.$1),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
    );
  }
}

/// One person on the Users table, read from the `/users` response.
class DesktopTeamUser {
  const DesktopTeamUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.roles,
    required this.branches,
    required this.isActive,
    required this.lastLoginAt,
  });

  factory DesktopTeamUser.fromJson(Map<String, dynamic> json) {
    final first = json['firstName']?.toString().trim() ?? '';
    final last = json['lastName']?.toString().trim() ?? '';
    final email = json['email']?.toString() ?? '';
    final name = '$first $last'.trim();
    return DesktopTeamUser(
      id: json['id']?.toString() ?? email,
      name: name.isEmpty ? email : name,
      email: email,
      phone: json['phone']?.toString() ?? '',
      roles: [
        for (final r in (json['roles'] as List<dynamic>? ?? const []))
          if (r is Map && r['name'] != null) r['name'].toString(),
      ],
      branches: [
        for (final b in (json['branches'] as List<dynamic>? ?? const []))
          if (b is Map && b['name'] != null) b['name'].toString(),
      ],
      isActive: json['isActive'] as bool? ?? true,
      lastLoginAt:
          DateTime.tryParse(json['lastLoginAt']?.toString() ?? '')?.toLocal(),
    );
  }

  final String id;
  final String name;
  final String email;
  final String phone;
  final List<String> roles;
  final List<String> branches;
  final bool isActive;
  final DateTime? lastLoginAt;

  String get roleLabel => roles.isEmpty ? 'No role' : roles.join(', ');
}

/// "Just now", "12 min ago", "3 days ago", "4 Oct 2026" or "Never signed in".
String lastActiveLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Never signed in';
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) {
    return diff.inDays == 1 ? 'Yesterday' : '${diff.inDays} days ago';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}

/// A label and its value on one line, for inspectors.
class DesktopFact extends StatelessWidget {
  const DesktopFact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
