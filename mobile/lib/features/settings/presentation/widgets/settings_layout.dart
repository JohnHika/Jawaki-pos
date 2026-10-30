import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';

// Layout building blocks for the Settings screen: a profile/business header,
// grouped section cards, consistent rows, status chips and a searchable list.
// Everything follows the app's single orange accent and works in both the
// light (default) and dark themes.

/// One tappable setting. [tileBuilder] lets an entry render a live tile
/// (e.g. the backup status) while still being searchable by its static text.
class SettingsEntry {
  const SettingsEntry({
    required this.id,
    required this.icon,
    required this.title,
    this.subtitle,
    this.keywords = const [],
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.tileBuilder,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Extra words that should find this entry in the search box.
  final List<String> keywords;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget Function(BuildContext context, SettingsEntry entry)? tileBuilder;

  bool matches(String sectionTitle, List<String> terms) {
    final haystack = [
      title,
      subtitle ?? '',
      sectionTitle,
      ...keywords,
    ].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }
}

class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.entries,
  });

  final String id;
  final String title;
  final List<SettingsEntry> entries;
}

Color _surfaceFor(bool isDark) =>
    isDark ? DesignColors.darkSurfaceElevated : Colors.white;

Color _borderFor(bool isDark) =>
    isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;

Color _primaryTextFor(bool isDark) =>
    isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;

Color _secondaryTextFor(bool isDark) =>
    isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

Color _tertiaryTextFor(bool isDark) =>
    isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

/// Rounded square holding an icon, tinted with the accent (or red when the
/// action is destructive).
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({
    super.key,
    required this.icon,
    this.destructive = false,
    this.size = 38,
  });

  final IconData icon;
  final bool destructive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = destructive ? DesignColors.error : DesignColors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: context.readable(color), size: size * 0.5),
    );
  }
}

/// Small pill used for network and workspace states.
class SettingsStatusChip extends StatelessWidget {
  const SettingsStatusChip({
    super.key,
    required this.text,
    required this.color,
    this.showDot = true,
    this.pulse = false,
  });

  final String text;
  final Color color;
  final bool showDot;

  /// Ripples the status dot a few times — used for a live "Online" state.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final textColor = context.readable(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            if (pulse)
              SizedBox(
                width: 15,
                height: 15,
                child: PulseDot(color: textColor, size: 5, pulses: 3),
              )
            else ...[
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: textColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row inside a section card.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = destructive
        ? context.readable(DesignColors.error)
        : _primaryTextFor(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SettingsIconTile(icon: icon, destructive: destructive),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: _secondaryTextFor(isDark),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: trailing!,
                  ),
                ],
                if (onTap != null && !destructive) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: _tertiaryTextFor(isDark)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section label plus a single rounded card holding that section's rows.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({super.key, required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = _borderFor(isDark);
    final entries = section.entries;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              section.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: _secondaryTextFor(isDark),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _surfaceFor(isDark),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
              boxShadow: DesignShadows.soft(isDark),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  _buildTile(context, entries[i]),
                  if (i != entries.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 66,
                      color: border.withValues(alpha: 0.7),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, SettingsEntry entry) {
    final custom = entry.tileBuilder;
    if (custom != null) return custom(context, entry);
    return SettingsTile(
      key: ValueKey('settings-tile-${entry.id}'),
      icon: entry.icon,
      title: entry.title,
      subtitle: entry.subtitle,
      trailing: entry.trailing,
      onTap: entry.onTap,
      destructive: entry.destructive,
    );
  }
}

/// Profile + business summary shown at the top of Settings.
class SettingsProfileHeader extends StatelessWidget {
  const SettingsProfileHeader({
    super.key,
    required this.name,
    required this.email,
    required this.roleLabel,
    required this.businessName,
    required this.companyCode,
    this.branchName = '',
    this.isOnline = false,
    this.isLocalWorkspace = false,
  });

  final String name;
  final String email;
  final String roleLabel;
  final String businessName;
  final String companyCode;
  final String branchName;
  final bool isOnline;
  final bool isLocalWorkspace;

  String get _initial {
    final text = name.trim();
    return text.isEmpty ? '?' : text[0].toUpperCase();
  }

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: companyCode));
    if (!context.mounted) return;
    showGlassSnackBar(
      context,
      'Company code copied',
      icon: Icons.copy_rounded,
      color: DesignColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = _borderFor(isDark);
    final primary = _primaryTextFor(isDark);
    final secondary = _secondaryTextFor(isDark);

    return Container(
      decoration: BoxDecoration(
        color: _surfaceFor(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
        boxShadow: DesignShadows.soft(isDark),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: DesignColors.accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initial,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: secondary),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: DesignColors.accent
                                  .withValues(alpha: isDark ? 0.16 : 0.12),
                              borderRadius: BorderRadius.circular(
                                  DesignSpacing.radiusFull),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? DesignColors.accentLight
                                    : DesignColors.accentDark,
                              ),
                            ),
                          ),
                          SettingsStatusChip(
                            // Internet access does not mean a device-local
                            // shop is syncing. Make the storage model clear
                            // instead of showing a misleading live status.
                            text: isLocalWorkspace
                                ? 'Local only'
                                : isOnline
                                    ? 'Network connected'
                                    : 'No network',
                            // Connectivity state only describes the device's
                            // network interface, not whether a server is
                            // reachable, so it should not pulse as a live
                            // service-health indicator.
                            pulse: false,
                            color: isLocalWorkspace
                                ? DesignColors.info
                                : isOnline
                                    ? DesignColors.success
                                    : DesignColors.warning,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1, thickness: 1, color: border.withValues(alpha: 0.7)),
          Container(
            color: isDark
                ? DesignColors.darkSurface.withValues(alpha: 0.5)
                : DesignColors.surface,
            padding: const EdgeInsets.fromLTRB(18, 12, 6, 12),
            child: Row(
              children: [
                const SettingsIconTile(icon: Icons.storefront_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        businessName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      if (branchName.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          branchName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: secondary),
                        ),
                      ],
                      if (companyCode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Company code  ',
                                style: TextStyle(color: secondary),
                              ),
                              TextSpan(
                                text: companyCode,
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (companyCode.isNotEmpty)
                  IconButton(
                    key: const ValueKey('settings-copy-company-code'),
                    tooltip: 'Copy company code',
                    onPressed: () => _copyCode(context),
                    icon: Icon(Icons.copy_rounded,
                        size: 20, color: _secondaryTextFor(isDark)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The scrolling body of the Settings screen: header, search box, sections
/// and footer. Typing in the search box filters rows across all sections.
class SettingsSectionList extends StatefulWidget {
  const SettingsSectionList({
    super.key,
    required this.header,
    required this.sections,
    required this.footer,
  });

  final Widget header;
  final List<SettingsSection> sections;
  final Widget footer;

  @override
  State<SettingsSectionList> createState() => _SettingsSectionListState();
}

class _SettingsSectionListState extends State<SettingsSectionList> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SettingsSection> _visibleSections() {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final result = <SettingsSection>[];
    for (final section in widget.sections) {
      final entries = terms.isEmpty
          ? section.entries
          : section.entries
              .where((e) => e.matches(section.title, terms))
              .toList();
      if (entries.isEmpty) continue;
      result.add(SettingsSection(
        id: section.id,
        title: section.title,
        entries: entries,
      ));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = _borderFor(isDark);
    final visible = _visibleSections();
    final searching = _query.trim().isNotEmpty;

    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
          DesignSpacing.lg, DesignSpacing.xxl + DesignSpacing.sm),
      children: [
        FadeSlideIn(distance: 10, child: widget.header),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('settings-search'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search settings',
            hintStyle: TextStyle(color: _tertiaryTextFor(isDark)),
            prefixIcon:
                Icon(Icons.search_rounded, color: _tertiaryTextFor(isDark)),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: _surfaceFor(isDark),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: outline(border),
            enabledBorder: outline(border),
            focusedBorder: outline(DesignColors.accent, 1.5),
          ),
        ),
        const SizedBox(height: 22),
        if (visible.isEmpty && searching)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded,
                    size: 40, color: _tertiaryTextFor(isDark)),
                const SizedBox(height: 12),
                Text(
                  'No settings found',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _primaryTextFor(isDark),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try a different word, like "printer" or "PIN".',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: _secondaryTextFor(isDark)),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < visible.length; i++)
            FadeSlideIn(
              key: ValueKey('settings-section-${visible[i].id}'),
              distance: 10,
              delay: Duration(milliseconds: 40 * (i < 6 ? i : 6)),
              child: SettingsSectionCard(section: visible[i]),
            ),
        widget.footer,
      ],
    );
  }
}
