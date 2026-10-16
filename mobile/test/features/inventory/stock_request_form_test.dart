import 'package:axon_pos/features/inventory/presentation/screens/stock_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(const ProviderScope(
    child: MaterialApp(home: StockRequestScreen()),
  ));
  await tester.pump();
}

void main() {
  testWidgets('asks for product, amount, urgency, reason and photos',
      (tester) async {
    await _pump(tester);

    expect(find.text('Choose a product'), findsOneWidget);
    expect(find.text('How many do you need?'), findsOneWidget);
    expect(find.textContaining('How urgent is it?', findRichText: true), findsOneWidget);
    for (final p in ['Low', 'Normal', 'High', 'Urgent']) {
      expect(find.text(p), findsOneWidget);
    }
    expect(find.textContaining('Why do you need it?', findRichText: true), findsOneWidget);
    expect(find.text('Running low'), findsOneWidget);
    // The send button is always on screen, not at the bottom of a long page.
    expect(find.text('Send Request'), findsOneWidget);
  });

  testWidgets('quantity chips add up', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('quick-10')));
    await tester.tap(find.byKey(const ValueKey('quick-5')));
    await tester.pump();

    final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('request-quantity')));
    expect(field.controller!.text, '15');
  });

  testWidgets('a quick reason fills the note, and tapping it again clears it',
      (tester) async {
    await _pump(tester);
    final note = find.widgetWithText(TextFormField, '');

    await tester.ensureVisible(find.text('Out of stock'));
    await tester.tap(find.text('Out of stock'));
    await tester.pump();
    expect(find.text('Out of stock'), findsNWidgets(2)); // pill + note text

    await tester.tap(find.text('Out of stock').first);
    await tester.pump();
    expect(find.text('Out of stock'), findsOneWidget);
    expect(note, findsWidgets);
  });

  testWidgets('sending without a product or amount is refused', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Send Request'));
    await tester.pump();

    expect(find.text('Enter how many you need'), findsOneWidget);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    await _pump(tester, textScale: 1.3);
    await tester.tap(find.byKey(const ValueKey('quick-50')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Send Request'), findsOneWidget);
  });
}
