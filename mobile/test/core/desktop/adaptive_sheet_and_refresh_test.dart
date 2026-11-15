import 'package:axon_pos/core/desktop/adaptive_sheet.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

const _desktopSize = Size(1300, 800);
const _phoneSize = Size(390, 800);

Widget _sheetHost({
  Color? backgroundColor,
  ValueChanged<Object?>? onResult,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final result = await showAdaptiveModalSheet<String>(
              context: context,
              backgroundColor: backgroundColor,
              builder: (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TextField(autofocus: true),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('picked'),
                    child: const Text('pick'),
                  ),
                ],
              ),
            );
            onResult?.call(result);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void _pretendDesktop(WidgetTester tester, {required bool desktop}) {
  DesktopLayout.debugIsDesktopPlatform = desktop;
  addTearDown(() => DesktopLayout.debugIsDesktopPlatform = null);
  useWindow(tester, desktop ? _desktopSize : _phoneSize);
}

void main() {
  group('showAdaptiveModalSheet', () {
    testWidgets('a phone keeps the bottom sheet', (tester) async {
      _pretendDesktop(tester, desktop: false);
      Object? result = 'unset';
      await tester.pumpWidget(_sheetHost(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      expect(result, 'picked');
    });

    testWidgets('a narrow Windows window keeps the bottom sheet',
        (tester) async {
      DesktopLayout.debugIsDesktopPlatform = true;
      addTearDown(() => DesktopLayout.debugIsDesktopPlatform = null);
      useWindow(tester, const Size(700, 800));
      await tester.pumpWidget(_sheetHost());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('the desktop shell shows a 560 wide dialog and returns a value',
        (tester) async {
      _pretendDesktop(tester, desktop: true);
      Object? result = 'unset';
      await tester.pumpWidget(_sheetHost(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester
            .getSize(find
                .descendant(
                    of: find.byType(Dialog), matching: find.byType(Material))
                .first)
            .width,
        560,
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(result, 'picked');
    });

    testWidgets('Esc closes the dialog and only the dialog', (tester) async {
      _pretendDesktop(tester, desktop: true);
      Object? result = 'unset';
      await tester.pumpWidget(_sheetHost(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      // The text field inside the dialog holds focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(result, isNull);
      expect(find.text('open'), findsOneWidget, reason: 'page stays');
    });

    testWidgets('a transparent sheet gets a transparent dialog',
        (tester) async {
      _pretendDesktop(tester, desktop: true);
      await tester.pumpWidget(_sheetHost(backgroundColor: Colors.transparent));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, Colors.transparent);
      expect(dialog.elevation, 0);
    });

    testWidgets('a side panel docks to the right edge', (tester) async {
      _pretendDesktop(tester, desktop: true);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAdaptiveModalSheet<void>(
              context: context,
              desktopStyle: DesktopSheetStyle.sidePanel,
              builder: (_) => const Text('panel body'),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('panel body'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.getTopRight(find.text('panel body')).dx,
          lessThanOrEqualTo(_desktopSize.width));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('panel body'), findsNothing);
    });
  });

  group('DesktopRefresh', () {
    Widget host(Future<void> Function() onRefresh) => MaterialApp(
          home: Scaffold(
            body: DesktopRefresh(
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [Text('row')],
              ),
            ),
          ),
        );

    testWidgets('a phone is a plain pull to refresh, no button',
        (tester) async {
      _pretendDesktop(tester, desktop: false);
      await tester.pumpWidget(host(() async {}));
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byTooltip('Refresh (F5)'), findsNothing);
    });

    testWidgets('the desktop shell adds a Refresh button', (tester) async {
      _pretendDesktop(tester, desktop: true);
      var calls = 0;
      await tester.pumpWidget(host(() async => calls++));
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh (F5)'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('F5 and Ctrl+R refresh the focused page', (tester) async {
      _pretendDesktop(tester, desktop: true);
      var calls = 0;
      await tester.pumpWidget(host(() async => calls++));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(calls, 2);
    });

    testWidgets('a second request while refreshing is ignored',
        (tester) async {
      _pretendDesktop(tester, desktop: true);
      var calls = 0;
      final pending = <void Function()>[];
      await tester.pumpWidget(host(() {
        calls++;
        return Future<void>.delayed(const Duration(seconds: 1))
            .whenComplete(() => pending.clear());
      }));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
