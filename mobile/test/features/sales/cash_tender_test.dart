import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/sales/domain/cash_tender.dart';
import 'package:axon_pos/features/sales/presentation/widgets/cash_tender_sheet.dart';

void main() {
  group('cash maths', () {
    test('change and shortfall are exact and never negative', () {
      expect(cashChange(total: 60, tendered: 100), 40);
      expect(cashChange(total: 60, tendered: 60), 0);
      expect(cashChange(total: 60, tendered: 50), 0);
      expect(cashShortfall(total: 60, tendered: 50), 10);
      expect(cashShortfall(total: 60, tendered: 100), 0);
    });

    test('does not drift on float-unfriendly amounts', () {
      expect(cashChange(total: 0.1 + 0.2, tendered: 1), 0.7);
      expect(coversTotal(total: 0.1 + 0.2, tendered: 0.3), isTrue);
      expect(cashShortfall(total: 19.99, tendered: 10), 9.99);
    });

    test('covers the total only when it is enough and there is a sale', () {
      expect(coversTotal(total: 60, tendered: 60), isTrue);
      expect(coversTotal(total: 60, tendered: 59.99), isFalse);
      expect(coversTotal(total: 0, tendered: 100), isFalse);
    });

    test('suggests the exact total then the notes above it', () {
      expect(suggestedTenders(60), [60, 100, 500, 1000]);
      expect(suggestedTenders(500), [500, 1000]);
      expect(suggestedTenders(1230), [1230, 1250, 1300, 1500]);
      expect(suggestedTenders(45.5), [50, 100, 500, 1000]);
      expect(suggestedTenders(0), isEmpty);
    });
  });

  group('cash sheet', () {
    Future<double?> open(WidgetTester tester, double total) async {
      double? result;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showCashTenderSheet(context, total: total);
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      return result;
    }

    testWidgets('shows change and only completes once enough is given',
        (tester) async {
      await open(tester, 60);

      FilledButton button() =>
          tester.widget<FilledButton>(find.byKey(const ValueKey('cash-confirm')));
      expect(button().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('cash-input')), '50');
      await tester.pump();
      expect(find.text('Still to pay'), findsOneWidget);
      expect(find.text('KES 10'), findsOneWidget);
      expect(button().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('cash-input')), '100');
      await tester.pump();
      expect(find.text('Change to give'), findsOneWidget);
      expect(find.text('KES 40'), findsOneWidget);
      expect(button().onPressed, isNotNull);
    });

    testWidgets('a quick-amount chip fills the field and returns the amount',
        (tester) async {
      double? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await showCashTenderSheet(context, total: 60),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cash-chip-500')));
      await tester.pump();
      expect(find.text('KES 440'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cash-confirm')));
      await tester.pumpAndSettle();
      expect(result, 500);
    });

    testWidgets('dismissing the sheet returns null (sale is abandoned)',
        (tester) async {
      double? result = -1;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await showCashTenderSheet(context, total: 60),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
