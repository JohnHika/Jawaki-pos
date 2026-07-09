import 'package:flutter/material.dart';

import '../services/update_check_service.dart';
import '../theme/design_system.dart';

/// One parsed release-note line, categorized where the text itself
/// signals a category (a "Fixes:"/"Adds:"/"Improves:" style prefix).
/// Falls back to [_ReleaseCategory.general] for anything that doesn't
/// match, so older/free-form release notes never look broken.
enum _ReleaseCategory { feature, fix, improvement, general }

class _ReleaseNote {
  const _ReleaseNote(this.text, this.category);
  final String text;
  final _ReleaseCategory category;
}

/// Full-screen "you're up to date" moment shown once, right after the app
/// relaunches on a version it just installed. Reuses the same
/// `last_seen_update_notice` de-dupe key the previous AlertDialog-based
/// implementation used, so it still only shows once per released version.
class UpdateSuccessScreen extends StatelessWidget {
  const UpdateSuccessScreen({
    super.key,
    required this.update,
    required this.onDismiss,
  });

  final AppUpdateInfo update;

  // Shown as a Stack overlay (see main.dart), not pushed onto a Navigator,
  // so dismissal is a plain callback rather than Navigator.of(context).pop().
  // (This screen previously used Navigator.of(context) here, which threw
  // "Navigator operation requested with a context that does not include a
  // Navigator" every time, because the host widget that built it sits above
  // MaterialApp.router's internal Navigator, not below it.)
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final notes = _parseAndCategorize(update.releaseNotes);

    return Material(
      color: DesignColors.darkBg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.xxl,
                vertical: DesignSpacing.xxxl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SuccessMark(),
                  const SizedBox(height: DesignSpacing.xxl),
                  Text(
                    "You're up to date",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  Center(
                    child: StatusBadge(
                      label: update.displayVersion,
                      color: DesignColors.success,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: DesignSpacing.xxl),
                    Flexible(
                      child: SingleChildScrollView(
                        child: GlassCard(
                          padding: const EdgeInsets.all(DesignSpacing.xl),
                          borderRadius: DesignSpacing.radiusLg,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "What's new",
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: DesignColors.darkTextPrimary,
                                    ),
                              ),
                              const SizedBox(height: DesignSpacing.md),
                              for (final note in notes)
                                _CategorizedNoteRow(note: note),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.xxl),
                  SettingsPrimaryButton(
                    label: 'Continue',
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: DesignColors.successSubtle,
          shape: BoxShape.circle,
          border: Border.all(
            color: DesignColors.success.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: DesignColors.success.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: DesignColors.success,
          size: 38,
        ),
      ),
    );
  }
}

class _CategorizedNoteRow extends StatelessWidget {
  const _CategorizedNoteRow({required this.note});

  final _ReleaseNote note;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (note.category) {
      _ReleaseCategory.feature => (Icons.auto_awesome_rounded, DesignColors.accent),
      _ReleaseCategory.fix => (Icons.build_rounded, DesignColors.info),
      _ReleaseCategory.improvement => (Icons.speed_rounded, DesignColors.success),
      _ReleaseCategory.general => (Icons.check_circle_rounded, DesignColors.darkTextTertiary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              note.text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DesignColors.darkTextSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

List<_ReleaseNote> _parseAndCategorize(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  final lines = trimmed
      .split('\n')
      .map((line) => line.trim().replaceFirst(RegExp(r'^[-*•]\s*'), ''))
      .where((line) => line.isNotEmpty)
      .toList();

  // Release notes are sometimes written as one long sentence with no line
  // breaks (e.g. "Adds X, fixes Y, improves Z.") — split that into
  // comma-separated clauses instead of rendering it as a single wall-of-text
  // paragraph. Only kicks in when there's no real line structure already
  // and the single line is long enough that a reader would actually want
  // it broken up.
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
      return _ReleaseNote(line, _ReleaseCategory.fix);
    }
    if (lower.startsWith('add') || lower.startsWith('new')) {
      return _ReleaseNote(line, _ReleaseCategory.feature);
    }
    if (lower.startsWith('improve') || lower.startsWith('update')) {
      return _ReleaseNote(line, _ReleaseCategory.improvement);
    }
    return _ReleaseNote(line, _ReleaseCategory.general);
  }).toList();
}

/// Splits a single free-form sentence into clause-sized chunks a reader can
/// actually scan, using commas as the natural break point (release notes
/// written this way tend to be lists of "did X, fixed Y, improved Z"
/// clauses joined with commas). Falls back to the original text unsplit if
/// splitting would produce fragments too short to be meaningful on their
/// own.
List<String> _splitLongSentence(String sentence) {
  final parts = sentence
      .split(RegExp(r',\s*(?=[a-z])'))
      .map((part) =>
          part.trim().replaceFirst(RegExp(r'^and\s+', caseSensitive: false), ''))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.length < 2 || parts.any((part) => part.length < 8)) {
    return [sentence];
  }

  return [
    for (var i = 0; i < parts.length; i++)
      i == parts.length - 1
          ? _capitalize(parts[i])
          : '${_capitalize(parts[i])}.',
  ];
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}
