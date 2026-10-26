import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/app_icon_service.dart';
import '../../../../core/theme/design_system.dart';

/// Settings control for the living app icon: it lets the launcher icon reflect
/// how the shop is doing (a streak, products out of stock, a record day).
///
/// It is on by default and can be turned off here. Everything it reads stays on
/// this phone. Android can only swap between icons bundled in the app, and some
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

class _LivingIconCardState extends State<LivingIconCard> {
  bool _enabled = false;
  bool _busy = false;
  bool _loaded = false;
  String? _notice;
  AppIconVariant _current = AppIconVariant.standard;

  AppIconService get _service => widget.service ?? getIt<AppIconService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _service.isEnabled();
      final current = await _service.current();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _current = current;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      await _service.setEnabled(on);
      if (!mounted) return;
      setState(() {
        _enabled = on;
        _busy = false;
        _notice = on
            ? 'Done. Your icon updates the next time you leave the app.'
            : 'Done. The everyday icon comes back the next time you leave the app.';
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
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
                  errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44),
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Living app icon',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _enabled
                          ? 'Now showing: ${_current.title}'
                          : 'Let the icon follow how your shop is doing',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('living-icon-switch'),
                value: _enabled,
                onChanged: (!_loaded || _busy) ? null : _toggle,
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          Wrap(
            spacing: DesignSpacing.md,
            runSpacing: DesignSpacing.sm,
            children: [
              for (final v in AppIconVariant.values) _VariantChip(variant: v),
            ],
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
            'This is worked out on your phone from your own sales and stock; '
            'nothing is sent anywhere. The icon changes at most once every '
            '20 hours. '
            'On some phones the home-screen shortcut disappears when it '
            'changes, so use Add to home screen to put it back.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
          ),
          if (_enabled)
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

class _VariantChip extends StatelessWidget {
  const _VariantChip({required this.variant});

  final AppIconVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: variant.blurb,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                variant.previewAsset,
                width: 52,
                height: 52,
                errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              variant.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
