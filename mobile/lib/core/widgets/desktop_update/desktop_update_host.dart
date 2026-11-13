import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/desktop_update_service.dart';
import 'desktop_update_card.dart';

/// Puts the computer's update window and its corner notice over the app.
///
/// It sits in `MaterialApp.builder`, above the router's Navigator, so it never
/// pushes a route: the window and the notice are plain layers in a [Stack],
/// opened and closed by [DesktopUpdateService]. On anything but Windows it
/// returns [child] untouched.
class DesktopUpdateHost extends StatefulWidget {
  const DesktopUpdateHost({
    super.key,
    required this.service,
    required this.child,
  });

  final DesktopUpdateService service;
  final Widget child;

  @override
  State<DesktopUpdateHost> createState() => _DesktopUpdateHostState();
}

class _DesktopUpdateHostState extends State<DesktopUpdateHost> {
  Timer? _noticeTimer;
  DesktopUpdateNotice? _timedNotice;
  bool _listeningForEscape = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onChanged);
    _onChanged();
  }

  @override
  void didUpdateWidget(covariant DesktopUpdateHost old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.removeListener(_onChanged);
      widget.service.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_onChanged);
    _noticeTimer?.cancel();
    if (_listeningForEscape) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // Escape closes the window. A key handler (not a focus widget) so it works
  // wherever keyboard focus happens to be in the app underneath.
  bool _onKey(KeyEvent event) {
    if (!widget.service.overlayOpen) return false;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.service.closeOverlay();
      return true;
    }
    return false;
  }

  // A notice that nobody answers goes away on its own and comes back at the
  // next launch; only "Later" silences it for a day.
  void _onChanged() {
    final notice = widget.service.notice;
    if (!identical(notice, _timedNotice)) {
      _noticeTimer?.cancel();
      _timedNotice = notice;
      if (notice != null) {
        final lifetime = notice.kind == DesktopNoticeKind.updated
            ? const Duration(seconds: 8)
            : const Duration(seconds: 20);
        _noticeTimer = Timer(lifetime, () {
          if (identical(widget.service.notice, notice)) {
            widget.service.dismissNotice();
          }
        });
      }
    }
    final open = widget.service.overlayOpen;
    if (open != _listeningForEscape) {
      _listeningForEscape = open;
      if (open) {
        HardwareKeyboard.instance.addHandler(_onKey);
      } else {
        HardwareKeyboard.instance.removeHandler(_onKey);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    if (!service.supported) return widget.child;

    final dark = Theme.of(context).brightness == Brightness.dark;
    final notice = service.notice;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (notice != null && !service.overlayOpen)
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              type: MaterialType.transparency,
              child: _NoticeToast(
                key: ValueKey(notice),
                notice: notice,
                onOpen: () => service.openOverlay(),
                onTryAgain: () {
                  service.openOverlay(recheck: true);
                },
                onLater: () => service.snooze(),
                onClose: service.dismissNotice,
              ),
            ),
          ),
        if (service.overlayOpen)
          Positioned.fill(
            child: FocusScope(
              autofocus: true,
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: 'Counterbase update',
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Hermes dims and softly blurs what is behind the card.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: service.closeOverlay,
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                          child: ColoredBox(
                            color: Colors.black
                                .withValues(alpha: dark ? 0.55 : 0.22),
                          ),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _Entrance(
                            child: DesktopUpdateCard(
                              service: service,
                              onClose: service.closeOverlay,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fade and settle in from 95%, 200ms, as the Hermes dialog does.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
      ),
      child: child,
    );
  }
}

/// The corner notice: a small flat card with a title, one sentence and at
/// most two quiet actions.
class _NoticeToast extends StatelessWidget {
  const _NoticeToast({
    super.key,
    required this.notice,
    required this.onOpen,
    required this.onTryAgain,
    required this.onLater,
    required this.onClose,
  });

  final DesktopUpdateNotice notice;
  final VoidCallback onOpen;
  final VoidCallback onTryAgain;
  final VoidCallback onLater;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = UpdatePalette.of(context);

    final IconData icon;
    final Color iconColor;
    final String title;
    final String body;
    switch (notice.kind) {
      case DesktopNoticeKind.available:
        icon = Icons.cloud_download_outlined;
        iconColor = c.accent;
        title = 'New update available';
        body = notice.version == null
            ? 'A new version of Counterbase is ready to install.'
            : 'Counterbase ${notice.version} is ready to install.';
      case DesktopNoticeKind.updated:
        icon = Icons.check_circle_outline_rounded;
        iconColor = c.good;
        title = 'Update complete';
        body = notice.version == null
            ? 'Counterbase is up to date.'
            : 'Counterbase is now on version ${notice.version}.';
      case DesktopNoticeKind.failed:
        icon = Icons.error_rounded;
        iconColor = c.danger;
        title = 'Update didn’t finish';
        body = 'No worries — nothing was lost. You can try again now.';
    }

    return _Entrance(
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
          boxShadow: c.floating,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: updateBodyStyle(c,
                          size: 13,
                          weight: FontWeight.w600,
                          color: c.text,
                          height: 1.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: updateBodyStyle(c,
                          size: 12, color: c.muted, height: 1.35),
                    ),
                    if (notice.kind != DesktopNoticeKind.updated) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          UpdateButton(
                            label: notice.kind == DesktopNoticeKind.failed
                                ? 'Try again'
                                : 'See what’s new',
                            kind: UpdateButtonKind.textStrong,
                            onPressed: notice.kind == DesktopNoticeKind.failed
                                ? onTryAgain
                                : onOpen,
                          ),
                          UpdateButton(
                            label: notice.kind == DesktopNoticeKind.failed
                                ? 'Not now'
                                : 'Later',
                            kind: UpdateButtonKind.text,
                            onPressed: notice.kind == DesktopNoticeKind.failed
                                ? onClose
                                : onLater,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            UpdateCloseButton(onPressed: onClose),
          ],
        ),
      ),
    );
  }
}
