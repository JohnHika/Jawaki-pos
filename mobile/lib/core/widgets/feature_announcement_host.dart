import 'package:flutter/material.dart';

import '../services/feature_announcement_service.dart';
import 'feature_announcement_tour.dart';

/// A widget that sits above the app's navigation and automatically shows
/// pending feature announcements as an animated tour when they become
/// available.
///
/// Place this as a wrapper around your app's root widget (e.g. inside
/// MaterialApp.router's builder or as a top-level Stack child) so it can
/// insert overlay entries without needing a Navigator context.
///
/// ```dart
/// MaterialApp(
///   home: FeatureAnnouncementHost(
///     service: getIt<FeatureAnnouncementService>(),
///     child: YourApp(),
///   ),
/// )
/// ```
class FeatureAnnouncementHost extends StatefulWidget {
  const FeatureAnnouncementHost({
    super.key,
    required this.service,
    required this.child,
  });

  final FeatureAnnouncementService service;
  final Widget child;

  @override
  State<FeatureAnnouncementHost> createState() =>
      _FeatureAnnouncementHostState();
}

class _FeatureAnnouncementHostState extends State<FeatureAnnouncementHost> {
  bool _tourVisible = false;
  bool _checkQueued = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_handleServiceChanged);
    _queueMaybeShow();
  }

  @override
  void didUpdateWidget(covariant FeatureAnnouncementHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_handleServiceChanged);
      widget.service.addListener(_handleServiceChanged);
      _queueMaybeShow();
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_handleServiceChanged);
    super.dispose();
  }

  void _handleServiceChanged() {
    _queueMaybeShow();
  }

  void _queueMaybeShow() {
    if (!mounted || _checkQueued || _tourVisible) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _maybeShow();
    });
  }

  void _maybeShow() {
    if (!mounted || _tourVisible) return;
    if (!widget.service.hasPending) return;

    setState(() => _tourVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_tourVisible) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: _TourOverlay(
            service: widget.service,
            onDismiss: () => setState(() => _tourVisible = false),
          ),
        ),
      ],
    );
  }
}

/// Internal widget that creates and manages the [FeatureAnnouncementTour]
/// overlay lifecycle.
class _TourOverlay extends StatefulWidget {
  const _TourOverlay({
    required this.service,
    required this.onDismiss,
  });

  final FeatureAnnouncementService service;
  final VoidCallback onDismiss;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
  }

  Future<void> _startTour() async {
    if (!mounted) return;

    final announcements = widget.service.pending;
    if (announcements.isEmpty) {
      widget.onDismiss();
      return;
    }

    final tour = FeatureAnnouncementTour(
      announcements: announcements,
      service: widget.service,
      onFinished: widget.onDismiss,
    );
    await tour.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
