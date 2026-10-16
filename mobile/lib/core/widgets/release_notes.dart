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
///
/// Release bodies are written for engineers (GitHub release markdown with
/// download links, build metadata, CI notes). [cleanReleaseNoteLines] turns
/// that into plain, user-facing lines and returns nothing when no human-readable
/// change remains, so callers can show a friendly fallback instead.
List<ReleaseNote> parseReleaseNotes(String raw) {
  final cleaned = cleanReleaseNoteLines(raw);
  if (cleaned.isEmpty) return const [];

  final source = cleaned.length == 1 && cleaned.first.length > 60
      ? cleanReleaseNoteLines(_splitLongSentence(cleaned.first).join('\n'))
      : cleaned;

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

/// Sections whose whole body is installation/CI detail, not product changes.
final RegExp _technicalHeading = RegExp(
  r'download|update sources?|\bsources?\b|install|checksum|\bassets?\b|artifacts?|build info|technical|verification|signing',
  caseSensitive: false,
);

/// Individual lines that are build metadata even outside a technical section.
final RegExp _technicalLine = RegExp(
  r'^(release|internal build|build|source|commit|sha|tag|version|package)\s*:'
  r'|github actions|cloudflare|\br2\b|\.apk\b|sha-?256|latest\.json'
  r'|published from [0-9a-f]{7,}',
  caseSensitive: false,
);

/// Strips markdown and engineering-only content from a raw release body.
///
/// Headings are treated as structure (never shown); lists lose their markers;
/// `**bold**`, `` `code` ``, `[links](url)` and bare URLs are flattened to plain
/// text; technical sections/lines are dropped; at most 8 lines are kept.
List<String> cleanReleaseNoteLines(String raw) {
  final out = <String>[];
  var inTechnicalSection = false;
  var afterBlank = false;
  var sectionHasContent = false;
  final listItem = RegExp(r'^(?:[-*•+]|\d+[.)])\s+');
  for (final original in raw.split('\n')) {
    var line = original.trim();
    if (line.isEmpty) {
      afterBlank = true;
      continue;
    }
    // A technical section is a heading plus its list. Plain prose after a
    // blank line is the change list the release workflow appends, not more
    // installation detail, so it ends the section.
    if (inTechnicalSection &&
        sectionHasContent &&
        afterBlank &&
        !line.startsWith('#') &&
        !listItem.hasMatch(line)) {
      inTechnicalSection = false;
    }
    afterBlank = false;
    if (inTechnicalSection && !line.startsWith('#')) sectionHasContent = true;

    final heading = RegExp(r'^#{1,6}\s*(.*)$').firstMatch(line);
    if (heading != null) {
      inTechnicalSection = _technicalHeading.hasMatch(heading.group(1)!);
      sectionHasContent = false;
      continue;
    }
    if (inTechnicalSection) continue;

    line = line
        .replaceFirst(RegExp(r'^(?:[-*•+]|\d+[.)])\s+'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'[*`]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Judge sentence by sentence so "Faster sync. Build 2093 was published
    // from abc1234." keeps the first half.
    line = line
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((sentence) => sentence.length >= 3 && !_technicalLine.hasMatch(sentence))
        .join(' ');
    if (line.length < 3) continue;
    out.add(line);
    if (out.length >= 8) break;
  }
  return out;
}

/// "Axon POS Android Axon POS 1.0.50" -> "Axon POS 1.0.50".
/// Release names are assembled from a platform label plus the release title, so
/// the product name can appear twice; show it once.
String cleanReleaseName(String? raw, {required String fallback}) {
  var name = raw?.trim() ?? '';
  if (name.isEmpty) return fallback;
  final last = name.toLowerCase().lastIndexOf('axon pos');
  if (last > 0) name = name.substring(last);
  name = name.replaceAll(RegExp(r'\bAndroid\b\s*'), '').trim();
  return name.isEmpty ? fallback : name;
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
    final title = cleanReleaseName(releaseName, fallback: 'Axon POS $version');
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
            child: const Icon(Icons.system_update_rounded,
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
              // The title usually already carries the version; don't repeat it.
              if (!title.contains(version)) ...[
                const SizedBox(height: 3),
                Text(
                  version,
                  style: TextStyle(color: tertiary, fontSize: 11),
                ),
              ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, color) = switch (note.category) {
      ReleaseCategory.feature => (Icons.auto_awesome_rounded, DesignColors.accent),
      ReleaseCategory.fix => (Icons.build_rounded, DesignColors.info),
      ReleaseCategory.improvement => (Icons.speed_rounded, DesignColors.success),
      ReleaseCategory.general => (
          Icons.check_circle_rounded,
          isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary,
        ),
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
              style: TextStyle(
                color: isDark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
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
