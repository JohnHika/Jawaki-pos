import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/desktop_update_service.dart';
import '../../theme/design_system.dart';
import '../release_notes.dart';

// The computer's update window. Its form and style follow the Hermes desktop
// app's updater: one flat card with the app mark on top, a plain title and
// sentence, a short grouped list of what changed, one big "Update now" and a
// quiet "Maybe later". Installing swaps it for a stage line and a progress
// bar; a failure says nothing was lost and offers "Try again".
//
// Colours come from the Counterbase palette, so the orange accent and the
// app icon stay Counterbase's own.

/// The colours the update surfaces use, picked once per theme.
class UpdatePalette {
  const UpdatePalette(this.isDark);

  factory UpdatePalette.of(BuildContext context) =>
      UpdatePalette(Theme.of(context).brightness == Brightness.dark);

  final bool isDark;

  Color get surface => isDark ? DesignColors.darkSurface : Colors.white;
  Color get text => isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
  Color get muted => isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
  Color get faint => isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
  Color get hairline => text.withValues(alpha: isDark ? 0.10 : 0.08);
  Color get track => text.withValues(alpha: isDark ? 0.12 : 0.08);
  Color get softFill => text.withValues(alpha: isDark ? 0.05 : 0.035);
  Color get accent => DesignColors.accent;
  Color get danger => DesignColors.error;
  Color get good => DesignColors.success;
  Color get onAccent => accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  /// Hermes' floating-panel shadow: layered, cast straight down, pulled in
  /// at the sides so it pools under the card instead of haloing it.
  List<BoxShadow> get floating {
    final k = isDark ? 4.5 : 1.0;
    Color black(double a) => Colors.black.withValues(alpha: (a * k).clamp(0, 1));
    return [
      BoxShadow(color: black(0.07), offset: const Offset(0, 2), blurRadius: 4, spreadRadius: -2),
      BoxShadow(color: black(0.06), offset: const Offset(0, 8), blurRadius: 12, spreadRadius: -6),
      BoxShadow(color: black(0.06), offset: const Offset(0, 20), blurRadius: 28, spreadRadius: -14),
    ];
  }
}

TextStyle updateTitleStyle(UpdatePalette c, {double size = 20}) =>
    GoogleFonts.sora(
      color: c.text,
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      height: 1.25,
    );

TextStyle updateBodyStyle(
  UpdatePalette c, {
  double size = 14,
  Color? color,
  FontWeight? weight,
  double? height,
}) =>
    GoogleFonts.plusJakartaSans(
      color: color ?? c.muted,
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      height: height ?? 1.45,
    );

String formatUpdateBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// "just now", "5 min ago", "3 hours ago" for the last-checked line.
String updateRelativeTime(DateTime? at, DateTime now) {
  if (at == null) return 'never';
  final diff = now.difference(at);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  final d = diff.inDays;
  return '$d ${d == 1 ? 'day' : 'days'} ago';
}

/// A heading and its short list of changes.
class UpdateChangeGroup {
  const UpdateChangeGroup(this.label, this.items);
  final String label;
  final List<String> items;
}

/// Sorts a release body into New / Fixed / Improved lists. Notes with no
/// human-readable change left in them still get one honest line.
List<UpdateChangeGroup> groupUpdateNotes(String rawNotes) {
  final notes = parseReleaseNotes(rawNotes);
  if (notes.isEmpty) {
    return const [
      UpdateChangeGroup('Improved', ['Fixes and improvements for a smoother counter.']),
    ];
  }
  List<String> pick(ReleaseCategory c) =>
      [for (final n in notes) if (n.category == c) n.text];
  final features = pick(ReleaseCategory.feature);
  final fixes = pick(ReleaseCategory.fix);
  final improved = pick(ReleaseCategory.improvement);
  final other = pick(ReleaseCategory.general);
  final onlyOther = features.isEmpty && fixes.isEmpty && improved.isEmpty;
  return [
    if (features.isNotEmpty) UpdateChangeGroup('New', features),
    if (fixes.isNotEmpty) UpdateChangeGroup('Fixed', fixes),
    if (improved.isNotEmpty) UpdateChangeGroup('Improved', improved),
    if (other.isNotEmpty) UpdateChangeGroup(onlyOther ? 'What’s new' : 'Also', other),
  ];
}

// ─────────────────────────────────────────────────────────────────────────
// The card

class DesktopUpdateCard extends StatelessWidget {
  const DesktopUpdateCard({
    super.key,
    required this.service,
    required this.onClose,
    this.now,
  });

  final DesktopUpdateService service;
  final VoidCallback onClose;

  /// Only for tests that need a fixed "last checked" line.
  final DateTime Function()? now;

  static const double width = 384;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: width),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.hairline),
          boxShadow: c.floating,
        ),
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            return Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 640),
                  child: SingleChildScrollView(child: _phase(context)),
                ),
                if (!service.applying)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: UpdateCloseButton(onPressed: onClose),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _phase(BuildContext context) {
    if (service.applying) return _ApplyingView(service: service);
    if (service.stage == DesktopUpdateStage.error) {
      return _ErrorView(
        message: service.applyError,
        onRetry: () {
          service.resetApplyState();
          service.startUpdate();
        },
        onDismiss: onClose,
      );
    }
    if (!service.hasChecked) {
      return const _CenteredStatus(
        loading: true,
        title: 'Looking for updates…',
      );
    }
    final update = service.available;
    if (update != null && service.checkError == null) {
      return _AvailableView(
        service: service,
        update: update,
        onLater: () {
          service.snooze();
          onClose();
        },
      );
    }
    return _CurrentView(service: service, now: now ?? DateTime.now);
  }
}

const EdgeInsets _bodyPadding = EdgeInsets.fromLTRB(24, 28, 32, 24);

// ─────────────────────────────────────────────────────────────────────────
// Update available

class _AvailableView extends StatelessWidget {
  const _AvailableView({
    required this.service,
    required this.update,
    required this.onLater,
  });

  final DesktopUpdateService service;
  final DesktopUpdateInfo update;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    final groups = groupUpdateNotes(update.notes);
    final from = service.currentVersion;
    final size = update.sizeBytes;
    final caption = [
      if (from != null) 'Version $from → ${update.version}' else 'Version ${update.version}',
      if (size != null) formatUpdateBytes(size),
    ].join('  ·  ');

    return Padding(
      padding: _bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UpdateBrandMark(size: 64),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text('New update available',
                textAlign: TextAlign.center, style: updateTitleStyle(c)),
          ),
          const SizedBox(height: 12),
          Text(
            'Counterbase will close, update and reopen on its own. Your shop’s data stays safe.',
            textAlign: TextAlign.center,
            style: updateBodyStyle(c),
          ),
          const SizedBox(height: 6),
          Text(caption,
              textAlign: TextAlign.center,
              style: updateBodyStyle(c, size: 11, color: c.faint)),
          const SizedBox(height: 20),
          // A long list scrolls inside itself, so "Update now" never leaves
          // the screen.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _ChangeGroup(group: groups[i]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          UpdateButton(
            label: 'Update now',
            kind: UpdateButtonKind.primary,
            onPressed: service.startUpdate,
          ),
          const SizedBox(height: 8),
          Center(
            child: UpdateButton(
              label: 'Maybe later',
              kind: UpdateButtonKind.text,
              onPressed: onLater,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeGroup extends StatelessWidget {
  const _ChangeGroup({required this.group});
  final UpdateChangeGroup group;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.label, style: updateBodyStyle(c, size: 10, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final item in group.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: updateBodyStyle(c, size: 12, color: c.text, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Nothing to install: the version and the "am I up to date" card

class _CurrentView extends StatelessWidget {
  const _CurrentView({required this.service, required this.now});
  final DesktopUpdateService service;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    final version = service.currentVersion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 32, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: UpdateBrandMark(size: 64)),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text('Counterbase',
                textAlign: TextAlign.center, style: updateTitleStyle(c, size: 18)),
          ),
          const SizedBox(height: 4),
          Text(
            version == null ? 'Version unavailable' : 'Version $version',
            textAlign: TextAlign.center,
            style: updateBodyStyle(c, size: 12, color: c.muted),
          ),
          const SizedBox(height: 20),
          DesktopUpdateStatusCard(service: service, now: now),
        ],
      ),
    );
  }
}

/// The bordered "you're up to date / couldn't check" card with its
/// "Check now" action, as on Hermes' About page.
class DesktopUpdateStatusCard extends StatelessWidget {
  const DesktopUpdateStatusCard({super.key, required this.service, this.now});
  final DesktopUpdateService service;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final failed = service.checkError != null;
        final checking = service.checking;
        final line = failed
            ? 'Couldn’t reach the update server'
            : service.updateAvailable
                ? 'An update is ready to install.'
                : 'You’re running the latest version.';
        final tint = failed ? c.danger : c.text;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: failed ? c.danger.withValues(alpha: 0.06) : c.softFill,
            border: Border.all(
                color: failed ? c.danger.withValues(alpha: 0.35) : c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!failed) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(Icons.check_circle_outline_rounded,
                          size: 16, color: c.good),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line,
                            style: updateBodyStyle(c,
                                size: 14,
                                color: tint,
                                weight: FontWeight.w600,
                                height: 1.3)),
                        if (failed) ...[
                          const SizedBox(height: 4),
                          Text(service.checkError!, style: updateBodyStyle(c, size: 12)),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Last checked ${updateRelativeTime(service.lastCheckedAt, (now ?? DateTime.now)())}',
                          style: updateBodyStyle(c, size: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              UpdateButton(
                label: checking ? 'Checking…' : 'Check now',
                kind: UpdateButtonKind.textStrong,
                icon: checking ? null : Icons.refresh_rounded,
                busy: checking,
                onPressed: checking ? null : () => service.checkForUpdates(force: true),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Installing

class _ApplyingView extends StatelessWidget {
  const _ApplyingView({required this.service});
  final DesktopUpdateService service;

  static String label(DesktopUpdateStage s) {
    switch (s) {
      case DesktopUpdateStage.download:
        return 'Downloading…';
      case DesktopUpdateStage.verify:
        return 'Almost there…';
      case DesktopUpdateStage.install:
        return 'Getting ready…';
      case DesktopUpdateStage.restart:
        return 'Restarting Counterbase…';
      case DesktopUpdateStage.idle:
      case DesktopUpdateStage.error:
        return 'Getting ready…';
    }
  }

  String? _detail() {
    switch (service.stage) {
      case DesktopUpdateStage.download:
        final total = service.totalBytes;
        final got = service.receivedBytes;
        if (total != null && total > 0) {
          return '${formatUpdateBytes(got)} of ${formatUpdateBytes(total)}';
        }
        return got > 0 ? formatUpdateBytes(got) : null;
      case DesktopUpdateStage.verify:
        return 'Making sure the download is complete';
      case DesktopUpdateStage.install:
        return 'Handing over to the installer';
      case DesktopUpdateStage.restart:
        return 'Closing Counterbase to finish the update';
      case DesktopUpdateStage.idle:
      case DesktopUpdateStage.error:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    final text = label(service.stage);
    final detail = _detail();
    final progress = service.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: UpdateLoader(size: 64, color: c.accent)),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(text, textAlign: TextAlign.center, style: updateTitleStyle(c)),
          ),
          const SizedBox(height: 12),
          Text(
            'Counterbase closes while the update installs, then reopens on its own. Please don’t reopen it yourself while it’s updating.',
            textAlign: TextAlign.center,
            style: updateBodyStyle(c),
          ),
          if (detail != null) ...[
            const SizedBox(height: 12),
            Text(detail,
                textAlign: TextAlign.center,
                style: updateBodyStyle(c, size: 12, height: 1.4)),
          ],
          const SizedBox(height: 20),
          UpdateProgressBar(value: progress, semanticLabel: text),
          const SizedBox(height: 20),
          Text(
            'This window will close while the update runs, then Counterbase reopens on its own.',
            textAlign: TextAlign.center,
            style: updateBodyStyle(c, size: 12),
          ),
          if (service.stage == DesktopUpdateStage.download) ...[
            const SizedBox(height: 8),
            Center(
              child: UpdateButton(
                label: 'Cancel',
                kind: UpdateButtonKind.text,
                onPressed: service.cancelDownload,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Something went wrong

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    return Padding(
      padding: _bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Icon(Icons.error_rounded, size: 28, color: c.danger)),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text('Update didn’t finish',
                textAlign: TextAlign.center,
                style: updateTitleStyle(c).copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          Text(
            message?.isNotEmpty == true
                ? message!
                : 'No worries — nothing was lost. You can try again now.',
            textAlign: TextAlign.center,
            style: updateBodyStyle(c, height: 1.4),
          ),
          const SizedBox(height: 20),
          UpdateButton(
              label: 'Try again',
              kind: UpdateButtonKind.primary,
              onPressed: onRetry),
          const SizedBox(height: 8),
          Center(
            child: UpdateButton(
                label: 'Not now', kind: UpdateButtonKind.text, onPressed: onDismiss),
          ),
        ],
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.title, this.loading = false});
  final String title;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 32, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) UpdateLoader(size: 48, color: c.accent),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(title, textAlign: TextAlign.center, style: updateTitleStyle(c, size: 18)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Pieces shared by the card and the corner notice

/// The Counterbase icon, the same squircle the app and its installer use.
class UpdateBrandMark extends StatelessWidget {
  const UpdateBrandMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ExcludeSemantics(
        child: Image.asset(
          'assets/images/axon_app_icon_512.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded,
              size: size * 0.6, color: DesignColors.accent),
        ),
      ),
    );
  }
}

enum UpdateButtonKind { primary, text, textStrong }

/// Hermes' three button looks: a flat full-width primary, a quiet text
/// action that underlines on hover, and a bold underlined inline action.
class UpdateButton extends StatefulWidget {
  const UpdateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = UpdateButtonKind.primary,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final UpdateButtonKind kind;
  final IconData? icon;
  final bool busy;

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    final enabled = widget.onPressed != null;
    final primary = widget.kind == UpdateButtonKind.primary;

    final Color fg = primary
        ? c.onAccent
        : (_hover || _focus) && enabled
            ? c.text
            : c.muted;
    final style = updateBodyStyle(
      c,
      size: primary ? 14 : 13,
      color: fg,
      weight: primary || widget.kind == UpdateButtonKind.textStrong
          ? FontWeight.w600
          : FontWeight.w500,
      height: 1.3,
    ).copyWith(
      decoration: widget.kind == UpdateButtonKind.textStrong ||
              (widget.kind == UpdateButtonKind.text && _hover && enabled)
          ? TextDecoration.underline
          : TextDecoration.none,
      decorationColor: fg.withValues(alpha: 0.6),
    );

    final Widget label = Row(
      mainAxisSize: primary ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy) ...[
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: fg),
          ),
          const SizedBox(width: 6),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 13, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(widget.label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: primary
              ? AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    color: !enabled
                        ? c.accent.withValues(alpha: 0.5)
                        : _hover
                            ? c.accent.withValues(alpha: 0.9)
                            : c.accent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _focus ? c.text.withValues(alpha: 0.55) : Colors.transparent,
                        width: 2),
                  ),
                  child: label,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: label,
                ),
        ),
      ),
    );
  }
}

class UpdateCloseButton extends StatefulWidget {
  const UpdateCloseButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<UpdateCloseButton> createState() => UpdateCloseButtonState();
}

class UpdateCloseButtonState extends State<UpdateCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    return Semantics(
      button: true,
      label: 'Close',
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hover ? c.text.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.close_rounded,
                size: 16, color: _hover ? c.text : c.faint),
          ),
        ),
      ),
    );
  }
}

/// A thin rounded bar. With no [value] it slides, like Hermes' unknown-size
/// state; with one it fills smoothly.
class UpdateProgressBar extends StatefulWidget {
  const UpdateProgressBar({super.key, this.value, this.semanticLabel, this.height = 8});
  final double? value;
  final String? semanticLabel;
  final double height;

  @override
  State<UpdateProgressBar> createState() => _UpdateProgressBarState();
}

class _UpdateProgressBarState extends State<UpdateProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.value == null) _slide.repeat();
  }

  @override
  void didUpdateWidget(covariant UpdateProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.value == null && !_slide.isAnimating) {
      _slide.repeat();
    } else if (widget.value != null && _slide.isAnimating) {
      _slide.stop();
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);
    final value = widget.value;
    // Never show an empty bar once work has begun: 2% is Hermes' floor.
    final shown = value?.clamp(0.02, 1.0).toDouble();
    return Semantics(
      label: widget.semanticLabel,
      value: value == null ? null : '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height),
        child: SizedBox(
          height: widget.height,
          child: ColoredBox(
            color: c.track,
            child: LayoutBuilder(
              builder: (context, box) {
                if (shown != null) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      width: box.maxWidth * shown,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(widget.height),
                      ),
                    ),
                  );
                }
                final bar = box.maxWidth / 3;
                return AnimatedBuilder(
                  animation: _slide,
                  builder: (context, _) => Stack(
                    children: [
                      Positioned(
                        left: -bar + (box.maxWidth + bar) * _slide.value,
                        width: bar,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(widget.height),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Hermes' "lemniscate bloom" loader: dots chasing each other round a
/// figure of eight, brightest at the head.
class UpdateLoader extends StatefulWidget {
  const UpdateLoader({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<UpdateLoader> createState() => _UpdateLoaderState();
}

class _UpdateLoaderState extends State<UpdateLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Working',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, _) => CustomPaint(
            painter: _LemniscatePainter(_spin.value, widget.color),
          ),
        ),
      ),
    );
  }
}

class _LemniscatePainter extends CustomPainter {
  _LemniscatePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dots = 30;
    final a = size.width * 0.42;
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var i = 0; i < dots; i++) {
      // 0 at the head, 1 at the tail of the comet.
      final age = i / dots;
      final phase = (t - age * 0.62) * 2 * math.pi;
      final d = 1 + math.sin(phase) * math.sin(phase);
      final x = cx + a * math.cos(phase) / d;
      final y = cy + a * math.sin(phase) * math.cos(phase) / d * 1.25;
      final radius = size.width * 0.045 * (1 - age * 0.7);
      final paint = Paint()
        ..color = color.withValues(alpha: (1 - age) * (1 - age));
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LemniscatePainter old) =>
      old.t != t || old.color != color;
}
