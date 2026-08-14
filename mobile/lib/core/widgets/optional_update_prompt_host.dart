import 'package:flutter/material.dart';

import '../services/update_check_service.dart';
import 'update_available_dialog.dart';
import 'update_success_screen.dart';

// This host builds from a BuildContext that sits above MaterialApp.router's
// internal Navigator (it's constructed inside MaterialApp.router's own
// `builder`), so it can never safely call Navigator.of(context) or
// showDialog(context: context) — both throw "Navigator operation requested
// with a context that does not include a Navigator". Both notices below are
// therefore rendered as plain Stack overlays with local dismiss callbacks,
// not pushed/shown via the Navigator.
class OptionalUpdatePromptHost extends StatefulWidget {
  const OptionalUpdatePromptHost({
    super.key,
    required this.updateService,
    required this.child,
  });

  final UpdateCheckService updateService;
  final Widget child;

  @override
  State<OptionalUpdatePromptHost> createState() =>
      _OptionalUpdatePromptHostState();
}

class _OptionalUpdatePromptHostState extends State<OptionalUpdatePromptHost> {
  String? _shownVersionThisLaunch;
  bool _checkQueued = false;
  String? _shownInstalledNoticeThisLaunch;
  AppUpdateInfo? _visibleOptionalUpdate;
  AppUpdateInfo? _visibleSuccessNotice;

  @override
  void initState() {
    super.initState();
    widget.updateService.addListener(_handleUpdateServiceChanged);
    _queueMaybeShow();
  }

  @override
  void didUpdateWidget(covariant OptionalUpdatePromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updateService != widget.updateService) {
      oldWidget.updateService.removeListener(_handleUpdateServiceChanged);
      widget.updateService.addListener(_handleUpdateServiceChanged);
      _queueMaybeShow();
    }
  }

  @override
  void dispose() {
    widget.updateService.removeListener(_handleUpdateServiceChanged);
    super.dispose();
  }

  void _handleUpdateServiceChanged() {
    _queueMaybeShow();
  }

  void _queueMaybeShow() {
    if (!mounted || _checkQueued) return;

    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _maybeShowOptionalUpdate();
    });
  }

  Future<void> _maybeShowOptionalUpdate() async {
    if (!mounted) return;
    if (widget.updateService.isForceUpdateRequired) return;
    if (_visibleOptionalUpdate != null || _visibleSuccessNotice != null) {
      return;
    }

    final update = widget.updateService.optionalUpdate;
    final installedUpdate = widget.updateService.installedUpdateNotice;
    if (update == null && installedUpdate == null) return;

    if (update != null) {
      final versionKey = update.noticeKey.trim();
      if (versionKey.isEmpty || versionKey == _shownVersionThisLaunch) return;

      _shownVersionThisLaunch = versionKey;
      setState(() => _visibleOptionalUpdate = update);
      return;
    }

    final noticeKey = installedUpdate!.noticeKey.trim();
    if (noticeKey.isEmpty || noticeKey == _shownInstalledNoticeThisLaunch) {
      return;
    }

    _shownInstalledNoticeThisLaunch = noticeKey;

    final due = await widget.updateService.consumeInstalledUpdateNoticeIfDue();
    if (due == null || !mounted) return;
    setState(() => _visibleSuccessNotice = due);
  }

  @override
  Widget build(BuildContext context) {
    final optionalUpdate = _visibleOptionalUpdate;
    final successNotice = _visibleSuccessNotice;
    if (optionalUpdate == null && successNotice == null) return widget.child;

    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Stack(
        children: [
          widget.child,
          if (optionalUpdate != null)
            Positioned.fill(
              child: UpdateAvailableCard(
                update: optionalUpdate,
                onDismiss: () => setState(() => _visibleOptionalUpdate = null),
              ),
            ),
          if (successNotice != null)
            Positioned.fill(
              child: UpdateSuccessScreen(
                update: successNotice,
                onDismiss: () => setState(() => _visibleSuccessNotice = null),
              ),
            ),
        ],
      ),
    );
  }
}
