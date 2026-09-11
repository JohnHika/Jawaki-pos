import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// Categorizes a release-note line by its prefix (Fixes:/Adds:/Improves:).
enum ReleaseCategory { feature, fix, improvement, general }

class ReleaseNote {
  const ReleaseNote(this.text, this.category);
  final String text;
  final ReleaseCategory category;
}

/// Parses raw release notes text into categorized lines and renders them
/// with icons. Shared by [UpdateAvailableDialog] and [UpdateSuccessScreen]
/// so both show the same structured format from the same source.
List<ReleaseNote> parseReleaseNotes(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  final lines = trimmed
      .split('\n')
      .map((line) => line.trim().replaceFirst(RegExp(r'^[-*•]\s*'), ''))
      .where((line) => line.isNotEmpty)
      .toList();

  final source = lines.length > 1
      ? lines
      : lines.isEmpty
          ? _splitLongSentence(trimmed)
          : lines.first.length > 60
              ? _splitLongSentence(lines.first)
              : lines;

  return source.map((line) {
    final lower = line.toLowerCase();
    if (lower.startsWith('fix') || lower.contains(' fix')) {
      return ReleaseNote(line, ReleaseCategory.fix);
    }
    if (lower.startsWith('add') || lower.startsWith('new')) {
      return ReleaseNote(line, ReleaseCategory.feature);
    }
    if (lower.startsWith('improve') || lower.startsWith('update')) {
      return ReleaseNote(line, ReleaseCategory.improvement);
    }
    return ReleaseNote(line, ReleaseCategory.general);
  }).toList();
}

List<String> _splitLongSentence(String text) {
  final cleaned = text.replaceFirst(RegExp(r'^[-*•]\s*'), '');
  final parts = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
  if (parts.length > 1) return parts;
  return cleaned.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// Compact release metadata block used by update notices. The build number
/// remains available for support/debugging, but it is secondary to the
/// release name, publication date, and the actual change list.
class UpdateReleaseMeta extends StatelessWidget {
  const UpdateReleaseMeta({
    super.key,
    required this.releaseName,
    required this.version,
    required this.buildNumber,
    required this.publishedAt,
  });

  final String? releaseName;
  final String version;
  final int? buildNumber;
  final DateTime? publishedAt;

  String _publishedLabel() {
    final date = publishedAt;
    if (date == null) return 'Release date not provided';
    final local = date.toLocal();
    return 'Released ${local.day} ${_month(local.month)} ${local.year}';
  }

  String _month(int month) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][month];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = releaseName?.trim().isNotEmpty == true
        ? releaseName!.trim()
        : version;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiary =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DesignColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
            ),
            child: const Icon(Icons.new_releases_rounded,
                color: DesignColors.accent, size: 21),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  _publishedLabel(),
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'BUILD ${buildNumber?.toString() ?? '—'}',
                style: DesignType.numeric(
                  fontSize: 11,
                  color: tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                version,
                style: TextStyle(color: tertiary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders a list of categorized release notes with icons.
class CategorizedNotes extends StatelessWidget {
  const CategorizedNotes({super.key, required this.releaseNotes});

  final String releaseNotes;

  @override
  Widget build(BuildContext context) {
    final notes = parseReleaseNotes(releaseNotes);
    if (notes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in notes) _CategorizedNoteRow(note: note),
      ],
    );
  }
}

class _CategorizedNoteRow extends StatelessWidget {
  const _CategorizedNoteRow({required this.note});

  final ReleaseNote note;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (note.category) {
      ReleaseCategory.feature => (Icons.auto_awesome_rounded, DesignColors.accent),
      ReleaseCategory.fix => (Icons.build_rounded, DesignColors.info),
      ReleaseCategory.improvement => (Icons.speed_rounded, DesignColors.success),
      ReleaseCategory.general => (Icons.check_circle_rounded, DesignColors.darkTextTertiary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note.text,
              style: const TextStyle(
                color: DesignColors.darkTextSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
