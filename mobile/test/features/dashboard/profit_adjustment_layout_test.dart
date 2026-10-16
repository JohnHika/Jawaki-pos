import 'package:axon_pos/features/dashboard/presentation/screens/profit_adjustment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {double revenue = 1510}) async {
  tester.view.physicalSize = const Size(1000, 1700); // 500 x 850 dp
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: ProfitAdjustmentScreen(
        date: DateTime(2026, 10, 16),
        currentRevenue: revenue,
        currentCost: 0,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the summary fits with large text, including a big amount',
      (tester) async {
    await _pump(tester, revenue: 12345678.9);

    expect(tester.takeException(), isNull);
    expect(find.text('Your Adjusted Profit:'), findsOneWidget);
    expect(find.text('Your Adjusted Cost:'), findsOneWidget);
  });

  testWidgets('typing a cost updates the adjusted profit', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextFormField).first, '400');
    await tester.pump();

    expect(find.textContaining('1,110'), findsWidgets);
  });
}
