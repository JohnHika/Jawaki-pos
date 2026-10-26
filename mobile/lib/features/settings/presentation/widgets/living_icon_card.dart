import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/app_icon_service.dart';
import '../../../../core/theme/design_system.dart';

/// Settings control for the living app icon: it lets the launcher icon reflect
/// how the shop is doing (a streak, products out of stock, a record day).
///
/// It follows shop activity automatically. Everything it reads stays on this
/// phone. Android can only swap between icons bundled in the app, and some
/// launchers drop the home-screen shortcut when the icon is swapped; "Add to
/// home screen" puts it back with one tap. The swap itself waits until the app
/// is in the background, because doing it while the app is open closes the app.
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
  String? _notice;
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

  Future<void> _pin() async {
    final ok = await _service.pinCurrentIcon();
    if (!mounted) return;
    setState(() {
      _notice = ok
          ? 'Check the prompt to add Counterbase to your home screen.'
          : "Your phone can't add it from here. Press and hold Counterbase in your app list to place it on the home screen.";
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only Android can swap launcher icons.
    if (!_isAndroid) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      key: const ValueKey('living-icon-card'),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
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
                      'Counterbase adapts its icon',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _loaded
                          ? 'Now showing: ${_current.title}'
                          : 'Checking your shop activity…',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.sm),
          Text(
            _current.blurb,
            key: const ValueKey('living-icon-reason'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: DesignSpacing.md),
          Row(
            children: [
              Text(
                'Adaptive icon library',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${AppIconVariant.values.length} looks',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.sm),
          SizedBox(
            height: 50,
            child: ListView.separated(
              key: const ValueKey('living-icon-gallery'),
              scrollDirection: Axis.horizontal,
              itemCount: AppIconVariant.values.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: DesignSpacing.xs),
              itemBuilder: (context, index) {
                final variant = AppIconVariant.values[index];
                final isCurrent = variant == _current;
                return Tooltip(
                  message: variant.title,
                  child: Semantics(
                    label: isCurrent
                        ? '${variant.title}, current automatic icon'
                        : '${variant.title}, automatic icon preview',
                    child: Container(
                      width: 50,
                      height: 50,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          variant.previewAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: DesignSpacing.sm),
            Text(
              _notice!,
              key: const ValueKey('living-icon-notice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: DesignSpacing.sm),
          Text(
            '${AppIconVariant.values.length} built-in looks keep the Axon cube '
            'consistent while Counterbase chooses a matching icon from your '
            'shop activity. It changes '
            'automatically and explains each change in a notification when '
            'app notifications are allowed. '
            'The decision stays on this phone, and the icon changes at most '
            'once every 20 hours. '
            'On some phones the home-screen shortcut disappears when it '
            'changes, so use Add to home screen to put it back.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
          ),
          if (_loaded)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('living-icon-pin'),
                onPressed: _pin,
                icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                label: const Text('Add to home screen'),
              ),
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
