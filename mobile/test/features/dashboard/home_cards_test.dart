import 'package:axon_pos/features/dashboard/presentation/widgets/home_cards.dart';
import 'package:axon_pos/features/home/domain/shop_guidance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the split bar is drawn with one segment per money group',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HomeTakingsCard(
          revenue: 1000,
          transactions: 3,
          averageTicket: 333,
          split: TakingsSplit(cash: 600, recorded: 300, credit: 100),
        ),
      ),
    ));

    final bars = find.byWidgetPredicate(
      (w) => w is ColoredBox &&
          (w.color == kCashColor ||
              w.color == kRecordedColor ||
              w.color == kCreditColor),
    );
    expect(bars, findsNWidgets(3));
    for (final element in bars.evaluate()) {
      final size = element.renderObject!.paintBounds.size;
      expect(size.height, 8);
      expect(size.width, greaterThan(10));
    }
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('M-Pesa or bank, recorded'), findsOneWidget);
    expect(find.text('On credit'), findsOneWidget);
  });

  testWidgets('a day with only recorded money still shows its bar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HomeTakingsCard(
          revenue: 250,
          transactions: 1,
          averageTicket: 250,
          split: TakingsSplit(recorded: 250),
        ),
      ),
    ));
    final bars = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == kRecordedColor);
    expect(bars, findsOneWidget);
    expect(bars.evaluate().single.renderObject!.paintBounds.width,
        greaterThan(100));
  });

  testWidgets('once a sale has been rung the card says when selling began',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HomeTakingsCard(
          revenue: 250,
          transactions: 1,
          averageTicket: 250,
          split: TakingsSplit(cash: 250),
          dateLabel: 'Wed 4 Nov',
          sellingSince: '7:42',
        ),
      ),
    ));
    expect(find.text('Selling since 7:42'), findsOneWidget);
    expect(find.text('Wed 4 Nov'), findsNothing);
  });

  testWidgets('before the first sale the card shows the date', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HomeTakingsCard(
          revenue: 0,
          transactions: 0,
          averageTicket: 0,
          split: TakingsSplit(),
          dateLabel: 'Wed 4 Nov',
        ),
      ),
    ));
    expect(find.text('Wed 4 Nov'), findsOneWidget);
    expect(find.textContaining('Selling since'), findsNothing);
  });
}
