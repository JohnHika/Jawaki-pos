import 'package:flutter/material.dart';

import '../services/update_check_service.dart';

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
  bool _dialogInFlight = false;
  bool _checkQueued = false;

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
    if (!mounted || _dialogInFlight) return;
    if (widget.updateService.isForceUpdateRequired) return;

    final update = widget.updateService.optionalUpdate;
    if (update == null) return;

    final versionKey = update.latestVersion.trim();
    if (versionKey.isEmpty || versionKey == _shownVersionThisLaunch) return;

    _shownVersionThisLaunch = versionKey;
    _dialogInFlight = true;

    try {
      await widget.updateService.showCachedOptionalUpdateDialog(context);
    } finally {
      _dialogInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
