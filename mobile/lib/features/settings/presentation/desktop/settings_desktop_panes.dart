import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/services/desktop_update_service.dart';
import '../../../../core/theme/theme_provider.dart';
import '../widgets/settings_layout.dart';
import 'settings_desktop_page.dart';
import 'settings_desktop_widgets.dart';

/// The installed version, as plain strings.
@immutable
class DesktopAppVersion {
  const DesktopAppVersion(this.version, this.build);

  final String version;
  final String build;

  String get label => build.isEmpty ? version : '$version (build $build)';
}

/// The SharedPreferences keys of the three alert switches, handed in by the
/// Settings screen so this file does not own them.
@immutable
class DesktopNotifyKeys {
  const DesktopNotifyKeys({
    required this.sales,
    required this.inventory,
    required this.sync,
  });

  final String sales;
  final String inventory;
  final String sync;
}

/// Everything the computer version of Settings needs from the phone screen:
/// the same entries (already filtered by role and workspace) and a few
/// callbacks. Nothing here reads a provider, so a test can build it by hand.
class DesktopSettingsDeps {
  const DesktopSettingsDeps({
    required this.sections,
    this.isLocalWorkspace = false,
    this.version,
    this.updates,
    this.notifyKeys,
    this.osNotificationsGranted,
    this.requestOsNotifications,
    this.openUserGuide,
    this.openWebsite,
    this.profile,
  });

  final List<SettingsSection> sections;
  final bool isLocalWorkspace;
  final DesktopAppVersion? version;

  /// The Windows updater. Null hides the Updates pane.
  final DesktopUpdateService? updates;
  final DesktopNotifyKeys? notifyKeys;
  final Future<bool> Function()? osNotificationsGranted;
  final Future<bool> Function()? requestOsNotifications;
  final VoidCallback? openUserGuide;
  final VoidCallback? openWebsite;

  /// The signed-in person and shop card at the top of the Business pane.
  final Widget? profile;
}

/// Which pane shows the entry with this id, so a link such as
/// `/settings?open=logo` lands on the right pane.
String desktopSettingsPaneFor(String entryId) =>
    _paneOfEntry[entryId] ?? 'business';

const _paneOfEntry = <String, String>{
  'business-layout': 'business',
  'workspace-setup': 'business',
  'setup-checklist': 'business',
  'welcome-tour': 'business',
  'logo': 'business',
  'branches': 'business',
  'hours': 'business',
  'tax': 'receipts',
  'receipt-details': 'receipts',
  'printers': 'receipts',
  'recorded-payments': 'payments',
  'merchant-payouts': 'payments',
  'staff': 'users',
  'pin': 'security',
  'device-security': 'security',
  'offline-pin': 'security',
  'desktop-approvals': 'security',
  'axon-gateway-key': 'security',
  'notification-centre': 'notifications',
  'notifications': 'notifications',
  'appearance': 'appearance',
  'local-data': 'data',
  'export': 'data',
  'activity': 'data',
  'plan-licence': 'plan',
  'billing': 'plan',
  'updates': 'updates',
  'help': 'about',
  'report': 'about',
  'legal': 'about',
  'about': 'about',
  'logout': 'signout',
  'logout-all': 'signout',
};

/// The phone wording, said for a computer.
String desktopCopy(String text) => text
    .replaceAll('this phone', 'this computer')
    .replaceAll('every phone and browser', 'every phone, computer and browser');

/// [text] as written for the phone, or said for a computer inside the desktop
/// layout.
String settingsDeviceCopy(BuildContext context, String text) =>
    DesktopLayout.wantsShell(context) ? desktopCopy(text) : text;

/// Builds the navigation panes from the phone screen's entries. Entries that
/// the person may not use are not in [DesktopSettingsDeps.sections] and so are
/// not shown; a pane with nothing in it is left out.
List<DesktopSettingsPaneData> buildDesktopSettingsPanes(
  DesktopSettingsDeps deps,
) {
  final entries = <String, SettingsEntry>{
    for (final section in deps.sections)
      for (final entry in section.entries) entry.id: entry,
  };

  DesktopSettingItem? link(
    String id, {
    String? title,
    String? helper,
    IconData? icon,
    List<String> extraKeywords = const [],
  }) {
    final entry = entries[id];
    if (entry == null) return null;
    final shownTitle = title ?? desktopCopy(entry.title);
    final shownHelper = helper ??
        (entry.subtitle == null ? null : desktopCopy(entry.subtitle!));
    return DesktopSettingItem(
      id: id,
      title: shownTitle,
      helper: shownHelper,
      keywords: [...entry.keywords, ...extraKeywords],
      builder: (context) => DesktopSettingRow(
        key: ValueKey('desktop-setting-$id'),
        icon: icon ?? entry.icon,
        title: shownTitle,
        helper: shownHelper,
        onTap: entry.onTap,
        destructive: entry.destructive,
      ),
    );
  }

  List<DesktopSettingItem> links(List<String> ids) => [
        for (final id in ids)
          if (link(id) != null) link(id)!,
      ];

  DesktopSettingGroupData? group(
    List<DesktopSettingItem> items, {
    String? title,
    String? note,
  }) =>
      items.isEmpty
          ? null
          : DesktopSettingGroupData(title: title, note: note, items: items);

  List<DesktopSettingGroupData> compact(
    List<DesktopSettingGroupData?> groups,
  ) =>
      [
        for (final g in groups)
          if (g != null) g,
      ];

  final panes = <DesktopSettingsPaneData>[];

  void add(
    String id,
    String label,
    IconData icon,
    DesktopSettingsNavGroup navGroup,
    List<DesktopSettingGroupData?> groups, {
    String? heading,
    WidgetBuilder? leading,
  }) {
    final real = compact(groups);
    if (real.isEmpty && leading == null) return;
    panes.add(
      DesktopSettingsPaneData(
        id: id,
        label: label,
        icon: icon,
        group: navGroup,
        groups: real,
        heading: heading,
        leading: leading,
      ),
    );
  }

  // ── Shop ──────────────────────────────────────────────────────────────
  final stray = [
    for (final entry in entries.values)
      if (!_paneOfEntry.containsKey(entry.id)) entry.id,
  ];

  add(
    'business',
    'Business',
    Icons.storefront_outlined,
    DesktopSettingsNavGroup.shop,
    [
      group(
        links(['logo', 'branches', 'hours', 'business-layout']),
        title: 'Your shop',
      ),
      group(
        links(['workspace-setup', 'setup-checklist', 'welcome-tour']),
        title: 'Setup',
      ),
      group(links(stray), title: 'More'),
    ],
    leading: deps.profile == null ? null : (context) => deps.profile!,
  );

  add(
    'receipts',
    'Receipts and printing',
    Icons.receipt_long_outlined,
    DesktopSettingsNavGroup.shop,
    [
      group(links(['tax', 'receipt-details', 'printers']))
    ],
  );

  add(
    'payments',
    'Payments',
    Icons.payments_outlined,
    DesktopSettingsNavGroup.shop,
    [
      group(links(['recorded-payments', 'merchant-payouts']))
    ],
  );

  final staff = entries['staff'];
  if (staff != null && staff.onTap != null) {
    panes.add(
      DesktopSettingsPaneData(
        id: 'users',
        label: 'Users and roles',
        icon: Icons.people_outline_rounded,
        group: DesktopSettingsNavGroup.shop,
        onOpen: staff.onTap,
      ),
    );
  }

  // ── This computer ─────────────────────────────────────────────────────
  final approveComputer = link(
    'desktop-approvals',
    title: 'Sign in another computer',
    helper: 'Type the 6-digit code another computer shows to open your shop '
        'there',
    icon: Icons.laptop_windows_rounded,
  );
  add(
    'security',
    'Security and devices',
    Icons.shield_outlined,
    DesktopSettingsNavGroup.thisComputer,
    [
      group(
        links(['pin', 'device-security', 'offline-pin']),
        title: 'Sign-in and lock',
      ),
      group(
        [
          if (approveComputer != null) approveComputer,
          ...links(['axon-gateway-key']),
        ],
        title: 'Other computers and services',
      ),
    ],
  );

  final notifyKeys = deps.notifyKeys;
  final hasAlerts = entries.containsKey('notifications');
  final inbox = link('notification-centre');
  add(
    'notifications',
    'Notifications',
    Icons.notifications_none_rounded,
    DesktopSettingsNavGroup.thisComputer,
    [
      if (hasAlerts && deps.osNotificationsGranted != null)
        group(
          [
            DesktopSettingItem(
              id: 'os-notifications',
              title: 'Windows notifications',
              helper: 'Whether Counterbase may show alerts on this computer',
              keywords: const ['permission', 'allow', 'blocked'],
              builder: (_) => DesktopOsNotificationsRow(
                isGranted: deps.osNotificationsGranted!,
                request: deps.requestOsNotifications,
              ),
            ),
          ],
          title: 'This computer',
        ),
      if (hasAlerts && notifyKeys != null && !deps.isLocalWorkspace)
        group(
          [
            _alertSwitch(
              id: 'alerts-sales',
              prefKey: notifyKeys.sales,
              icon: Icons.point_of_sale_rounded,
              title: 'Sales alerts',
              helper: 'Know when a sale is completed',
              deps: deps,
            ),
            _alertSwitch(
              id: 'alerts-stock',
              prefKey: notifyKeys.inventory,
              icon: Icons.inventory_2_outlined,
              title: 'Stock alerts',
              helper: 'Low stock and reorder reminders',
              deps: deps,
            ),
            _alertSwitch(
              id: 'alerts-backup',
              prefKey: notifyKeys.sync,
              icon: Icons.sync_rounded,
              title: 'Backup alerts',
              helper: 'Know when a backup finishes or fails',
              deps: deps,
            ),
          ],
          title: 'Shop alerts',
          note: 'These apply as soon as you change them.',
        )
      else if (hasAlerts && deps.isLocalWorkspace)
        group(
          [
            DesktopSettingItem(
              id: 'alerts-local',
              title: 'Device-only notifications',
              helper: 'This edition can show local app notices. Sales, '
                  'low-stock and backup alerts are not active in a '
                  'device-only workspace.',
              builder: (_) => const DesktopSettingRow(
                key: ValueKey('desktop-setting-alerts-local'),
                icon: Icons.laptop_windows_rounded,
                title: 'Device-only notifications',
                helper: 'This edition can show local app notices. Sales, '
                    'low-stock and backup alerts are not active in a '
                    'device-only workspace.',
              ),
            ),
          ],
          title: 'Shop alerts',
        ),
      group([if (inbox != null) inbox], title: 'Inbox'),
    ],
  );

  if (entries.containsKey('appearance')) {
    add(
      'appearance',
      'Appearance',
      Icons.palette_outlined,
      DesktopSettingsNavGroup.thisComputer,
      [
        DesktopSettingGroupData(
          items: [
            DesktopSettingItem(
              id: 'theme',
              title: 'App theme',
              helper: 'Light, dark, or the same as Windows',
              keywords: const ['dark mode', 'light mode', 'colour', 'color'],
              builder: (_) => const DesktopThemeRow(),
            ),
          ],
        ),
      ],
    );
  }

  add(
    'data',
    'Data and backup',
    Icons.storage_rounded,
    DesktopSettingsNavGroup.thisComputer,
    [
      group(links(['local-data', 'export', 'activity']))
    ],
  );

  final updates = deps.updates;
  if (updates != null) {
    add(
      'updates',
      'Updates',
      Icons.system_update_alt_rounded,
      DesktopSettingsNavGroup.thisComputer,
      [
        DesktopSettingGroupData(
          items: [
            DesktopSettingItem(
              id: 'updates',
              title: 'Check for updates',
              helper: 'Counterbase version and the latest release',
              keywords: const ['upgrade', 'version', 'new', 'install'],
              builder: (_) =>
                  DesktopUpdatesRows(service: updates, version: deps.version),
            ),
          ],
        ),
      ],
    );
  }

  // ── Account ───────────────────────────────────────────────────────────
  add(
    'plan',
    'Plan and billing',
    Icons.workspace_premium_outlined,
    DesktopSettingsNavGroup.account,
    [
      group(links(['plan-licence', 'billing']))
    ],
  );

  final userGuide = deps.openUserGuide;
  final website = deps.openWebsite;
  add(
    'about',
    'About and help',
    Icons.info_outline_rounded,
    DesktopSettingsNavGroup.account,
    [
      group(
        [
          DesktopSettingItem(
            id: 'about-version',
            title: 'Counterbase',
            helper: 'A complete point-of-sale system for managing sales, '
                'stock and your shop. Powered by Arche Axon.',
            keywords: const ['version', 'build', 'about', 'arche axon'],
            builder: (_) => DesktopSettingRow(
              key: const ValueKey('desktop-setting-about-version'),
              icon: Icons.storefront_outlined,
              title: 'Counterbase',
              helper: 'A complete point-of-sale system for managing sales, '
                  'stock and your shop. Powered by Arche Axon.',
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DesktopSettingValue(
                    deps.version == null
                        ? 'Version unavailable'
                        : 'Version ${deps.version!.version}',
                  ),
                  if (website != null)
                    TextButton(
                      onPressed: website,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const Text('archeaxon.com'),
                    ),
                ],
              ),
            ),
          ),
        ],
        title: 'About',
      ),
      group(
        [
          if (userGuide != null)
            DesktopSettingItem(
              id: 'user-guide',
              title: 'User guide',
              helper: 'Step-by-step help for the till, stock and reports',
              keywords: const ['help', 'guide', 'how to', 'manual'],
              builder: (_) => DesktopSettingRow(
                key: const ValueKey('desktop-setting-user-guide'),
                icon: Icons.menu_book_outlined,
                title: 'User guide',
                helper: 'Step-by-step help for the till, stock and reports',
                onTap: userGuide,
              ),
            ),
          ...links(['help', 'report', 'legal']),
        ],
        title: 'Help',
      ),
    ],
  );

  final signOut = [
    for (final id in const ['logout', 'logout-all'])
      if (entries[id] != null) entries[id]!,
  ];
  add(
    'signout',
    'Sign out',
    Icons.logout_rounded,
    DesktopSettingsNavGroup.account,
    [
      if (signOut.isNotEmpty)
        DesktopSettingGroupData(
          items: [
            for (final entry in signOut)
              DesktopSettingItem(
                id: entry.id,
                title: desktopCopy(entry.title),
                helper: entry.subtitle == null
                    ? null
                    : desktopCopy(entry.subtitle!),
                keywords: entry.keywords,
                builder: (context) => DesktopSettingRow(
                  key: ValueKey('desktop-setting-${entry.id}'),
                  icon: entry.icon,
                  title: desktopCopy(entry.title),
                  helper: entry.subtitle == null
                      ? null
                      : desktopCopy(entry.subtitle!),
                  destructive: true,
                  trailing: OutlinedButton(
                    style: desktopOutlinedStyle(context, destructive: true),
                    onPressed: entry.onTap,
                    child: Text(
                      entry.id == 'logout-all'
                          ? 'Sign out everywhere'
                          : 'Sign out',
                    ),
                  ),
                ),
              ),
          ],
        ),
    ],
  );

  return panes;
}

DesktopSettingItem _alertSwitch({
  required String id,
  required String prefKey,
  required IconData icon,
  required String title,
  required String helper,
  required DesktopSettingsDeps deps,
}) {
  return DesktopSettingItem(
    id: id,
    title: title,
    helper: helper,
    keywords: const ['alerts', 'notify', 'sound'],
    builder: (_) => DesktopPrefSwitchRow(
      key: ValueKey('desktop-setting-$id'),
      prefKey: prefKey,
      icon: icon,
      title: title,
      helper: helper,
      onEnabled: deps.osNotificationsGranted == null
          ? null
          : () async {
              final granted = await deps.osNotificationsGranted!();
              if (!granted) await deps.requestOsNotifications?.call();
            },
    ),
  );
}

/// The theme choice, applied the moment it is picked.
class DesktopThemeRow extends ConsumerWidget {
  const DesktopThemeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return DesktopSettingRow(
      key: const ValueKey('desktop-setting-theme'),
      icon: Icons.palette_outlined,
      title: 'App theme',
      helper: 'Light, dark, or the same as Windows',
      trailing: DesktopSegmented<ThemeMode>(
        value: mode,
        options: const [
          (ThemeMode.light, 'Light'),
          (ThemeMode.dark, 'Dark'),
          (ThemeMode.system, 'Use system setting'),
        ],
        onChanged: (next) {
          if (next == mode) return;
          ref.read(themeModeProvider.notifier).setThemeMode(next);
          DesktopSavedController.notify(context);
        },
      ),
    );
  }
}

/// A boolean saved in SharedPreferences, switched and stored on the spot.
class DesktopPrefSwitchRow extends StatefulWidget {
  const DesktopPrefSwitchRow({
    super.key,
    required this.prefKey,
    required this.icon,
    required this.title,
    required this.helper,
    this.defaultValue = true,
    this.onEnabled,
  });

  final String prefKey;
  final IconData icon;
  final String title;
  final String helper;
  final bool defaultValue;

  /// Runs after the switch turns on (ask Windows for permission).
  final Future<void> Function()? onEnabled;

  @override
  State<DesktopPrefSwitchRow> createState() => _DesktopPrefSwitchRowState();
}

class _DesktopPrefSwitchRowState extends State<DesktopPrefSwitchRow> {
  late bool _value = widget.defaultValue;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _value = prefs.getBool(widget.prefKey) ?? widget.defaultValue;
      _loaded = true;
    });
  }

  Future<void> _change(bool next) async {
    setState(() => _value = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.prefKey, next);
    if (!mounted) return;
    DesktopSavedController.notify(context);
    if (next) await widget.onEnabled?.call();
  }

  @override
  Widget build(BuildContext context) {
    return DesktopSettingRow(
      icon: widget.icon,
      title: widget.title,
      helper: widget.helper,
      trailing: DesktopSwitch(
        value: _value,
        semanticLabel: widget.title,
        onChanged: _loaded ? _change : null,
      ),
    );
  }
}

/// Whether Windows lets Counterbase show notifications, with a button to ask.
class DesktopOsNotificationsRow extends StatefulWidget {
  const DesktopOsNotificationsRow({
    super.key,
    required this.isGranted,
    this.request,
  });

  final Future<bool> Function() isGranted;
  final Future<bool> Function()? request;

  @override
  State<DesktopOsNotificationsRow> createState() =>
      _DesktopOsNotificationsRowState();
}

class _DesktopOsNotificationsRowState extends State<DesktopOsNotificationsRow> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    bool granted;
    try {
      granted = await widget.isGranted();
    } catch (_) {
      granted = false;
    }
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    final p = context.desktop;
    return DesktopSettingRow(
      key: const ValueKey('desktop-setting-os-notifications'),
      icon: granted == true
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      title: 'Windows notifications',
      helper: granted == null
          ? 'Checking…'
          : granted
              ? 'On. Counterbase can show shop alerts on this computer.'
              : 'Blocked. Turn them on in Windows settings to get shop alerts.',
      trailing: granted == null
          ? null
          : granted
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: p.dark
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF15803D),
                    ),
                    const SizedBox(width: 6),
                    const DesktopSettingValue('On'),
                  ],
                )
              : widget.request == null
                  ? const DesktopSettingValue('Blocked')
                  : OutlinedButton(
                      style: desktopOutlinedStyle(context),
                      onPressed: () async {
                        final next = await widget.request!();
                        if (mounted) setState(() => _granted = next);
                      },
                      child: const Text('Turn on'),
                    ),
    );
  }
}

/// Version, update status and the button that opens the Windows updater.
class DesktopUpdatesRows extends StatelessWidget {
  const DesktopUpdatesRows({super.key, required this.service, this.version});

  final DesktopUpdateService service;
  final DesktopAppVersion? version;

  static String _ago(DateTime then, DateTime now) {
    final diff = now.difference(then);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final installed = service.currentVersion ?? version?.version;
        final build = service.currentBuild?.toString() ?? version?.build;
        final available = service.available;
        final checkedAt = service.lastCheckedAt;

        final String status;
        if (service.applying) {
          status = 'An update is being installed.';
        } else if (service.checking) {
          status = 'Checking for updates…';
        } else if (service.checkError != null) {
          status = service.checkError!;
        } else if (available != null) {
          status = 'Version ${available.version} is ready to install.';
        } else if (service.hasChecked) {
          status = checkedAt == null
              ? 'You are on the latest version.'
              : 'You are on the latest version. Checked '
                  '${_ago(checkedAt, DateTime.now())}.';
        } else {
          status = 'Counterbase looks for updates every few hours while it '
              'is open.';
        }

        final notes = available?.notes.trim() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopSettingRow(
              key: const ValueKey('desktop-setting-version'),
              icon: Icons.info_outline_rounded,
              title: 'Counterbase',
              helper: 'The version installed on this computer',
              trailing: DesktopSettingValue(
                installed == null
                    ? 'Version unavailable'
                    : build == null || build.isEmpty
                        ? installed
                        : '$installed (build $build)',
                tabular: true,
              ),
            ),
            Divider(height: 1, thickness: 1, color: p.border),
            DesktopSettingRow(
              key: const ValueKey('desktop-setting-check-updates'),
              icon: Icons.system_update_alt_rounded,
              title:
                  available == null ? 'Check for updates' : 'Update available',
              helper: status,
              trailing: available == null
                  ? OutlinedButton(
                      style: desktopOutlinedStyle(context),
                      key: const ValueKey('desktop-check-updates-button'),
                      onPressed: service.checking || service.applying
                          ? null
                          : () => service.openOverlay(recheck: true),
                      child: Text(
                        service.checking ? 'Checking…' : 'Check for updates',
                      ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        textStyle: desktopButtonText(),
                      ),
                      key: const ValueKey('desktop-view-update-button'),
                      onPressed: () => service.openOverlay(),
                      child: const Text('View update'),
                    ),
            ),
            if (available != null && notes.isNotEmpty) ...[
              Divider(height: 1, thickness: 1, color: p.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Text(
                  notes,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
