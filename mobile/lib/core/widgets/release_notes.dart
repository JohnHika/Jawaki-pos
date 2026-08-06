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
              style: TextStyle(
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
