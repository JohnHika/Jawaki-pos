import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_system.dart';
import 'desktop_layout.dart';

/// The title row at the top of a desktop page: the page name on the left,
/// the page's main actions on the right. Replaces the phone app bar inside
/// the desktop shell.
class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(
      DesktopTokens.gutter,
      20,
      DesktopTokens.gutter,
      14,
    ),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// A back button or icon before the title.
  final Widget? leading;

  /// Tabs or filters that belong to the header, drawn under the title.
  final Widget? bottom;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
            ],
          ),
          if (bottom != null) ...[const SizedBox(height: 14), bottom!],
        ],
      ),
    );
  }
}

/// A bordered surface that groups related content on a page. One level only:
/// never nest panels inside panels.
class DesktopPanel extends StatelessWidget {
  const DesktopPanel({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.clip = false,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// A small action or filter at the right of the title row.
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// Clip children to the rounded corners (tables, charts that bleed).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: GoogleFonts.sora(
                            color: p.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// One figure in a [DesktopMetricStrip].
class DesktopMetric {
  const DesktopMetric({
    required this.label,
    required this.value,
    this.hint,
    this.hintColor,
    this.onTap,
  });

  final String label;

  /// Already formatted ("KES 12,400").
  final String value;
  final String? hint;
  final Color? hintColor;
  final VoidCallback? onTap;
}

/// A single bordered strip of key figures separated by hairlines. Reads as a
/// table header of the day, not a row of identical cards.
class DesktopMetricStrip extends StatelessWidget {
  const DesktopMetricStrip({super.key, required this.metrics});

  final List<DesktopMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: p.border),
              Expanded(child: _MetricCell(metric: metrics[i], palette: p)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, required this.palette});

  final DesktopMetric metric;
  final DesktopPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      onTap: metric.onTap,
      hoverColor: p.hover,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                metric.value,
                style: DesignType.numeric(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
            ),
            if (metric.hint != null) ...[
              const SizedBox(height: 4),
              Text(
                metric.hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: metric.hintColor ?? p.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact search box for toolbars above tables and lists.
class DesktopSearchField extends StatelessWidget {
  const DesktopSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.width,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return SizedBox(
      width: width,
      height: DesktopTokens.controlHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        cursorColor: p.accent,
        style: GoogleFonts.plusJakartaSans(
          color: p.text,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(
            color: p.textFaint,
            fontSize: 13.5,
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.textMuted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          filled: true,
          fillColor: p.dark ? p.panelAlt : Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
            borderSide: BorderSide(color: p.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
            borderSide: BorderSide(color: p.accent, width: 1.4),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
            borderSide: BorderSide(color: p.border),
          ),
        ),
      ),
    );
  }
}

/// A pill filter (All / Low stock / Out of stock). Selected pills fill with
/// the accent tint; the rest stay outlined.
class DesktopFilterChip extends StatelessWidget {
  const DesktopFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Material(
      color: selected ? p.selected : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Colors.transparent : p.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        hoverColor: p.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: selected ? p.text : p.textMuted,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The "nothing here yet" view: says what the page is for and what to do.
class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.selected,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: p.dark ? DesignColors.accent : p.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: p.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}
