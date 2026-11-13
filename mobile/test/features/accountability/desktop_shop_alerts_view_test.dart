import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/accountability/domain/accountability_models.dart';
import 'package:axon_pos/features/accountability/presentation/desktop/desktop_shop_alerts_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

DateTime _ago({int minutes = 0, int hours = 0, int days = 0}) => DateTime.now()
    .subtract(Duration(minutes: minutes, hours: hours, days: days));

ShopAlert _a(
  String id,
  String type,
  AlertSeverity severity,
  String title,
  String body,
  DateTime at, {
  bool seen = false,
  String? who,
}) =>
    ShopAlert(
      id: id,
      type: type,
      severity: severity,
      title: title,
      body: body,
      createdAt: at,
      acknowledged: seen,
      actorName: who,
    );

List<ShopAlert> _sample() => [
      _a('a1', 'BELOW_COST', AlertSeverity.high, 'Sale below cost',
          'Blue Band 500g sold for KES 180. Cost is KES 205, so the shop lost KES 25.',
          _ago(minutes: 25), who: 'Brian Otieno'),
      _a('a2', 'CASH_SHORT', AlertSeverity.high, 'Till short by KES 1,250',
          'Closing count was KES 18,400 but the system expected KES 19,650.',
          _ago(hours: 3), who: 'Faith Wambui'),
      _a('a3', 'VOID', AlertSeverity.medium, 'Sale voided after payment',
          'Receipt 10482 for KES 2,340 (M-Pesa) was voided 4 minutes after it was paid.',
          _ago(hours: 5), who: 'Brian Otieno'),
      _a('a4', 'STOCK_WRITE_OFF', AlertSeverity.medium, 'Stock written off',
          '12 x Fresh milk 500ml written off as expired, worth KES 1,440.',
          _ago(days: 1), who: 'Faith Wambui'),
      _a('a5', 'DISCOUNT_LIMIT', AlertSeverity.low, 'Discount above the limit',
          'A 12% discount was given on a KES 3,100 sale. The limit for cashiers is 5%.',
          _ago(days: 1, hours: 3), who: 'Brian Otieno', seen: true),
      _a('a6', 'CREDIT_LIMIT_EXCEEDED', AlertSeverity.medium,
          'Credit over the limit',
          'Mama Njeri owes KES 24,000 against a limit of KES 20,000.',
          _ago(days: 2), who: 'Faith Wambui', seen: true),
      _a('a7', 'DAILY_SUMMARY', AlertSeverity.low, 'Daily summary',
          'Sales KES 48,250 across 63 receipts. Profit about KES 9,800.',
          _ago(days: 2, hours: 2), seen: true),
    ];

class _Harness extends StatefulWidget {
  const _Harness({
    required this.alerts,
    this.error,
    this.initialSelected,
    this.log,
  });

  final List<ShopAlert> alerts;
  final String? error;
  final String? initialSelected;
  final List<String>? log;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  DesktopAlertFilter _filter = DesktopAlertFilter.open;
  late String? _selected = widget.initialSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesktopShopAlertsView(
        title: 'Shop alerts',
        alerts: widget.alerts,
        openCount: widget.alerts.where((a) => !a.acknowledged).length,
        loadedOnce: true,
        error: widget.error,
        filter: _filter,
        onFilter: (f) => setState(() => _filter = f),
        selectedId: _selected,
        onSelect: (a) => setState(() => _selected = a?.id),
        onSeen: (a) => widget.log?.add('seen ${a.id}'),
        onSeenAll: () => widget.log?.add('seen all'),
        onRetry: () => widget.log?.add('retry'),
        onRules: () => widget.log?.add('rules'),
        todayState: DesktopTodayState.ready,
        todayTitle: 'Today, Westlands branch',
        todayBody:
            'KES 48,250 from 63 receipts so far, about 12% up on last Tuesday. M-Pesa took 65%. Two things need a look below.',
        onRefreshToday: () {},
      ),
    );
  }
}

Widget _app(Widget home, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DesktopTheme.of(base),
    home: boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
  );
}

const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
  '1920': Size(1688, 1012),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('alerts $theme ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(
          _Harness(alerts: _sample(), initialSelected: 'a1'),
          dark: dark,
          boundary: key,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/inbox-alerts-$theme-${entry.key}.png');
      });
    }
  }

  testWidgets('the New filter hides seen alerts, All shows them', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(alerts: _sample())));
    await tester.pumpAndSettle();
    expect(find.text('Sale below cost'), findsOneWidget);
    expect(find.text('Discount above the limit'), findsNothing);
    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    expect(find.text('Discount above the limit'), findsOneWidget);
  });

  testWidgets('a row opens the inspector, Mark seen reports it, Esc closes',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(_app(_Harness(alerts: _sample(), log: log)));
    await tester.pumpAndSettle();
    expect(find.text('What happened'), findsNothing);
    await tester.tap(find.text('Till short by KES 1,250'));
    await tester.pumpAndSettle();
    expect(find.text('What happened'), findsOneWidget);
    expect(find.text('Cash short'), findsOneWidget);
    await tester.tap(find.text('Mark seen'));
    expect(log, ['seen a2']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('What happened'), findsNothing);
  });

  testWidgets('header actions: Rules and Mark all seen', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(_app(_Harness(alerts: _sample(), log: log)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.tap(find.text('Mark all seen'));
    expect(log, ['rules', 'seen all']);
  });

  testWidgets('nothing to review says so and teaches what shows up',
      (tester) async {
    useWindow(tester, _sizes['1093']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      _Harness(alerts: [for (final a in _sample()) _a(a.id, a.type, a.severity, a.title, a.body, a.createdAt, seen: true, who: a.actorName)]),
      dark: true,
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs your attention'), findsWidgets);
    expect(find.text('Mark all seen'), findsNothing);
    await saveShot(tester, key, 'build/shots/inbox-alerts-empty-dark-1093.png');
  });

  testWidgets('a failed refresh keeps the rows and offers Try again',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(
      _Harness(alerts: _sample(), error: 'No connection. Check the internet and try again.'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sale below cost'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
