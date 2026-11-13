import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_layout.dart';

/// Colours the native Windows title bar and window border to match the app, so
/// the frame reads as part of the window instead of a grey strip above it.
///
/// Only the native frame changes; hit-testing, resizing and Snap Layouts stay
/// the system's. Does nothing off Windows, on an old runner, or when the
/// platform call fails.
class WindowChrome {
  const WindowChrome._();

  static const _channel = MethodChannel('com.archeaxon.counterbase/window');
  static int? _last;

  static Future<void> syncTitleBar(Brightness brightness) async {
    if (kIsWeb || !Platform.isWindows) return;
    final p = brightness == Brightness.dark
        ? DesktopPalette.darkPalette
        : DesktopPalette.light;
    final key = Object.hash(
      brightness,
      p.frame.toARGB32(),
      p.text.toARGB32(),
      p.border.toARGB32(),
    );
    if (_last == key) return;
    _last = key;
    try {
      await _channel.invokeMethod<void>('setTitleBarTheme', {
        'dark': brightness == Brightness.dark,
        'caption': p.frame.toARGB32(),
        'text': p.text.toARGB32(),
        'border': p.border.toARGB32(),
      });
    } on MissingPluginException {
      // An older runner without the channel: cosmetic only.
    } on PlatformException {
      // Cosmetic only.
    }
  }
}

/// Keeps the native title bar in step with the app's theme. Place it once,
/// above the app's pages.
class WindowChromeSync extends StatefulWidget {
  const WindowChromeSync({super.key, required this.child});

  final Widget child;

  @override
  State<WindowChromeSync> createState() => _WindowChromeSyncState();
}

class _WindowChromeSyncState extends State<WindowChromeSync> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DesktopLayout.isDesktopPlatform) {
      WindowChrome.syncTitleBar(Theme.of(context).brightness);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
