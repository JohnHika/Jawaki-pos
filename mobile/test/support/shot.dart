import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Screenshot helper for reviewing layouts without launching the app.
///
/// Widget tests normally draw every glyph as a solid block (the Ahem test
/// font). [loadShotFonts] makes google_fonts read the Sora / Plus Jakarta Sans
/// / JetBrains Mono files bundled in `assets/google_fonts/` (no network) and
/// registers Material Icons, so a PNG written by [saveShot] looks like the real
/// window.
///
/// Only the bundled weights exist offline: Sora 400/600/700/800, Plus Jakarta
/// Sans 400/500/600/700, JetBrains Mono 700/800. Another weight makes
/// google_fonts try the network, which fails in a test.
Future<void> loadShotFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;

  final icons = File(
    'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

/// Wraps [child] in a repaint boundary [saveShot] can capture.
class ShotFrame extends StatelessWidget {
  const ShotFrame({super.key, required this.boundaryKey, required this.child});

  final GlobalKey boundaryKey;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: boundaryKey, child: child);
}

/// Sizes the test window like a computer screen.
void useWindow(WidgetTester tester, Size size, {double pixelRatio = 1}) {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Writes the boundary to [path] as a PNG.
Future<void> saveShot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) async {
  // Fonts load on real time, which a fake-async pump never advances.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
