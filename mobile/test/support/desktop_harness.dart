import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shot.dart';

/// The page area inside the desktop shell at the two sizes every desktop page
/// is designed for: a 1366x768 laptop and the same laptop at 125% scaling.
const desktopSizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
};

/// Wraps [body] the way the shell does (desktop theme, page background) so a
/// view can be pumped and photographed on its own.
Widget desktopApp(Widget body, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  final theme = DesktopTheme.of(base);
  final home = Scaffold(backgroundColor: theme.colorScheme.surface, body: body);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home:
        boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
  );
}

/// Pumps [build] at every size in light and dark, asserts nothing overflowed
/// or threw, and writes `build/shots/<name>-<mode>-<size>.png`.
void shotMatrix(
  String name,
  Widget Function() build, {
  Future<void> Function(WidgetTester tester)? beforeShot,
}) {
  for (final dark in [false, true]) {
    for (final entry in desktopSizes.entries) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('$name $mode ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(desktopApp(build(), dark: dark, boundary: key));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (beforeShot != null) {
          await beforeShot(tester);
          expect(tester.takeException(), isNull);
        }
        await saveShot(tester, key, 'build/shots/$name-$mode-${entry.key}.png');
      });
    }
  }
}
