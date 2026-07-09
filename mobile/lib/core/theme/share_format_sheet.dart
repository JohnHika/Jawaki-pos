import 'package:flutter/material.dart';

import 'design_system.dart';

enum ShareFormat { pdf, csv, plainText }

class ShareFormatOption {
  final ShareFormat format;
  final String title;
  final String subtitle;
  final IconData icon;

  const ShareFormatOption({
    required this.format,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  static const pdf = ShareFormatOption(
    format: ShareFormat.pdf,
    title: 'PDF document',
    subtitle: 'Branded, print-ready report',
    icon: Icons.picture_as_pdf_rounded,
  );

  static const csv = ShareFormatOption(
    format: ShareFormat.csv,
    title: 'CSV spreadsheet',
    subtitle: 'Open in Excel, Sheets, or Numbers',
    icon: Icons.table_chart_rounded,
  );

  static const plainText = ShareFormatOption(
    format: ShareFormat.plainText,
    title: 'Plain text',
    subtitle: 'Quick share to chat or SMS',
    icon: Icons.short_text_rounded,
  );
}

/// Bottom sheet letting the user choose which format to export/share as,
/// styled with the same grouped-card pattern used across Settings
/// (GroupedCard/SettingsRow/SettingsSheetScaffold) instead of a one-off
/// sheet design. Returns the chosen format, or null if dismissed.
Future<ShareFormat?> showShareFormatSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<ShareFormatOption> formats,
}) {
  return showModalBottomSheet<ShareFormat>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SettingsSheetScaffold(
      title: title,
      subtitle: subtitle,
      child: GroupedCard(
        margin: EdgeInsets.zero,
        children: [
          for (final option in formats)
            SettingsRow(
              icon: option.icon,
              title: option.title,
              subtitle: option.subtitle,
              onTap: () => Navigator.pop(context, option.format),
            ),
        ],
      ),
    ),
  );
}
