import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/settings/presentation/desktop/desktop_operating_hours_view.dart';
import 'package:axon_pos/features/settings/presentation/desktop/desktop_user_guide_view.dart';
import 'package:axon_pos/features/settings/presentation/screens/axon_gateway_settings_screen.dart';
import 'package:axon_pos/features/settings/presentation/screens/bug_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

class _Storage extends StorageService {
  @override
  Future<bool> hasAxonGatewayApiKey() async => true;
}

Widget _inShell(Widget child) =>
    DesktopScope(sidebarCollapsed: false, child: child);

const _labels = {
  'mon': 'Monday',
  'tue': 'Tuesday',
  'wed': 'Wednesday',
  'thu': 'Thursday',
  'fri': 'Friday',
  'sat': 'Saturday',
  'sun': 'Sunday',
};

DesktopOperatingHoursView _hours({
  bool saving = false,
  VoidCallback? onSave,
  void Function(String, bool)? onOpen,
  void Function(String, DesktopHoursField)? onPick,
}) =>
    DesktopOperatingHoursView(
      days: [
        for (final e in _labels.entries)
          DesktopHoursDay(
            key: e.key,
            label: e.value,
            closed: e.key == 'sun',
            open: '08:00',
            close: '18:00',
            hasBreak: e.key == 'fri',
            breakStart: '13:00',
            breakEnd: '14:00',
          ),
      ],
      weekStartDay: 'mon',
      weekStartOptions: [
        for (final e in _labels.entries) (e.key, e.value.substring(0, 3))
      ],
      saving: saving,
      onWeekStart: (_) {},
      onOpenChanged: onOpen ?? (_, __) {},
      onBreakChanged: (_, __) {},
      onPickTime: onPick ?? (_, __) {},
      onSave: onSave ?? () {},
      onBack: () {},
    );

DesktopUserGuideView _guide() => const DesktopUserGuideView(
      topics: [
        DesktopGuideTopic(
          icon: Icons.point_of_sale_rounded,
          title: 'Selling',
          steps: [
            'Open Sell',
            'Scan or search a product',
            'Press Ctrl+Enter to pay'
          ],
        ),
        DesktopGuideTopic(
          icon: Icons.inventory_2_rounded,
          title: 'Products',
          steps: ['Open Products', 'Add a product'],
        ),
        DesktopGuideTopic(
          icon: Icons.analytics_rounded,
          title: 'Reports',
          steps: ['Open Reports'],
        ),
      ],
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('settings-operating-hours', () => _hours());
  shotMatrix('settings-user-guide', () => _guide());
  shotMatrix('settings-gateway', () {
    getIt.registerSingleton<StorageService>(_Storage());
    return _inShell(const AxonGatewaySettingsScreen());
  });
  shotMatrix('settings-bug-report', () => _inShell(const BugReportScreen()));

  tearDown(() async => getIt.reset());

  testWidgets('operating hours: switch a day, pick a time, save with Ctrl+S',
      (tester) async {
    useWindow(tester, desktopSizes['1093']!);
    String? opened;
    String? picked;
    var saves = 0;
    await tester.pumpWidget(desktopApp(_hours(
      onSave: () => saves++,
      onOpen: (day, open) => opened = '$day:$open',
      onPick: (day, field) => picked = '$day:${field.name}',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    expect(opened, 'mon:false');

    await tester.tap(find.byKey(const ValueKey('hours-tue-close')));
    expect(picked, 'tue:close');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(saves, 1);

    await tester.tap(find.byKey(const ValueKey('hours-save')));
    expect(saves, 2);
  });

  testWidgets('operating hours: a closed day shows no times', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_hours()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hours-sun-open')), findsNothing);
    expect(find.byKey(const ValueKey('hours-mon-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('hours-fri-breakStart')), findsOneWidget);
  });

  testWidgets('user guide: arrow keys and clicks change the topic',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_guide()));
    await tester.pumpAndSettle();
    expect(find.text('Press Ctrl+Enter to pay'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Add a product'), findsOneWidget);
    expect(find.text('Press Ctrl+Enter to pay'), findsNothing);

    await tester.tap(find.text('Reports'));
    await tester.pump();
    expect(find.text('Open Reports'), findsOneWidget);
  });

  testWidgets('gateway key page: header and no phone app bar on a computer',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    getIt.registerSingleton<StorageService>(_Storage());
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: _inShell(const AxonGatewaySettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Axon AI Gateway'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Key saved on this device'), findsOneWidget);
  });

  testWidgets('phone layout keeps its app bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    getIt.registerSingleton<StorageService>(_Storage());
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const AxonGatewaySettingsScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Axon AI Gateway'), findsOneWidget);
  });

  testWidgets('bug report: form fits and Ctrl+Enter is offered',
      (tester) async {
    useWindow(tester, desktopSizes['1093']!);
    await tester.pumpWidget(desktopApp(_inShell(const BugReportScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Report a bug'), findsOneWidget);
    expect(find.byKey(const ValueKey('bug-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
