import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/app_icon_service.dart';
import '../../../../core/theme/design_system.dart';

/// Read-only status for the living app icon. The launcher icon is selected by
/// the app from shop activity; users cannot choose a variant in Settings.
class LivingIconCard extends StatefulWidget {
  const LivingIconCard({super.key, this.service});

  /// Injected in tests; defaults to the app's registered service.
  final AppIconService? service;

  @override
  State<LivingIconCard> createState() => _LivingIconCardState();
}

class _LivingIconCardState extends State<LivingIconCard>
    with WidgetsBindingObserver {
  bool _loaded = false;
  AppIconVariant _current = AppIconVariant.standard;

  AppIconService get _service => widget.service ?? getIt<AppIconService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final current = await _service.current();
      if (!mounted) return;
      setState(() {
        _current = current;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only Android can swap launcher icons.
    if (!_isAndroid) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final reason = _loaded
        ? appIconChangeReason(_current, automaticEnabled: true)
        : 'Checking recent shop activity on this device…';
    return Container(
      key: const ValueKey('living-icon-card'),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  _current.previewAsset,
                  width: 44,
                  height: 44,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox(width: 44, height: 44),
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App icon',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _loaded ? _current.title : 'Checking shop activity…',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.sm,
                  vertical: DesignSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
                ),
                child: Text(
                  'AUTOMATIC',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.sm),
          Text(
            reason,
            key: const ValueKey('living-icon-reason'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: DesignSpacing.sm),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: DesignSpacing.sm),
          Text(
            'Counterbase selects the launcher icon from shop activity. It can '
            'reflect a sales streak, a new record or products that need restocking. '
            'This check stays on your device. Changes happen in the background '
            'and at most once every 20 hours. If notifications are allowed, '
            'each change includes its reason.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  bool get _isAndroid {
    try {
      return Platform.isAndroid || widget.service != null;
    } catch (_) {
      return widget.service != null;
    }
  }
}
