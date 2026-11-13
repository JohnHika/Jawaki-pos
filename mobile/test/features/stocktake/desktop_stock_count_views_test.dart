import 'package:axon_pos/features/stocktake/domain/stocktake_models.dart';
import 'package:axon_pos/features/stocktake/presentation/desktop/desktop_stock_count_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

final _now = DateTime.now();

List<StockCountSummary> _counts() => [
      StockCountSummary(
        id: '1',
        status: 'SUBMITTED',
        itemCount: 84,
        createdAt: _now.subtract(const Duration(hours: 3)),
        title: 'Weekly shelf count',
        createdByName: 'Brian Kamau',
        totalVarianceValue: -3420,
      ),
      StockCountSummary(
        id: '2',
        status: 'IN_PROGRESS',
        itemCount: 40,
        createdAt: _now.subtract(const Duration(minutes: 25)),
        createdByName: 'Achieng Otieno',
      ),
      StockCountSummary(
        id: '3',
        status: 'APPROVED',
        itemCount: 112,
        createdAt: _now.subtract(const Duration(days: 8)),
        title: 'Month-end count',
        createdByName: 'Brian Kamau',
        totalVarianceValue: 1150,
      ),
      StockCountSummary(
        id: '4',
        status: 'CANCELLED',
        itemCount: 12,
        createdAt: _now.subtract(const Duration(days: 20)),
      ),
    ];

List<DesktopCountLine> _lines({bool blind = false}) => [
      for (final (i, name) in [
        'Brookside Milk 500ml',
        'Unga Jogoo 2kg',
        'Sugar Mumias 1kg',
        'Cooking oil Fresh Fri 1L',
        'Rice Pishori 2kg',
        'Bread Supaloaf 400g',
      ].indexed)
        DesktopCountLine(
          id: 'p$i',
          name: name,
          unit: 'piece',
          sku: 'SKU-${100 + i}',
          expected: blind ? null : (20 + i * 7).toDouble(),
          controller: TextEditingController(text: i < 2 ? '${19 + i * 7}' : ''),
        ),
    ];

Widget _counting({
  bool blind = false,
  DesktopCountShow show = DesktopCountShow.all,
  VoidCallback? onHandIn,
  VoidCallback? onSave,
  ValueChanged<String>? onChanged,
}) {
  final lines = _lines(blind: blind);
  return DesktopCountingView(
    title: 'Weekly shelf count',
    lines: lines,
    counted: 2,
    total: 6,
    show: show,
    onShow: (_) {},
    search: TextEditingController(),
    onSearch: () {},
    onChanged: onChanged ?? (_) {},
    expectedHidden: blind,
    onBack: () {},
    onSave: onSave ?? () {},
    onHandIn: onHandIn ?? () {},
  );
}

StockCountDetail _detail({String status = 'SUBMITTED', bool noDifferences = false}) =>
    StockCountDetail(
      id: '1',
      status: status,
      blind: true,
      expectedHidden: false,
      title: 'Weekly shelf count',
      totalLines: 84,
      countedLines: 80,
      completionPercent: 95,
      lossValue: 3980,
      gainValue: 560,
      netValue: -3420,
      shortLines: 6,
      overLines: 2,
      submittedByName: 'Brian Kamau',
      items: noDifferences
          ? const []
          : [
              StockCountLine(
                productId: 'a',
                productName: 'Brookside Milk 500ml',
                sku: 'BRK-500',
                expectedQty: 40,
                countedQty: 34,
                varianceQty: -6,
                varianceValue: -288,
                countedByName: 'Brian Kamau',
              ),
              StockCountLine(
                productId: 'b',
                productName: 'Cooking oil Fresh Fri 1L',
                sku: 'OIL-1L',
                expectedQty: 24,
                countedQty: 20,
                varianceQty: -4,
                varianceValue: -1180,
                countedByName: 'Brian Kamau',
              ),
              StockCountLine(
                productId: 'c',
                productName: 'Unga Jogoo 2kg',
                sku: 'UNG-2KG',
                expectedQty: 30,
                countedQty: 33,
                varianceQty: 3,
                varianceValue: 504,
                countedByName: 'Achieng Otieno',
              ),
            ],
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix(
    'stocktake-list',
    () => DesktopStockCountsView(
      title: 'Stock counts',
      rows: _counts(),
      canCreate: true,
      onOpen: (_) {},
      onStart: () {},
    ),
  );
  shotMatrix('stocktake-counting', () => _counting());
  shotMatrix(
    'stocktake-review',
    () => DesktopCountReviewView(
      title: 'Weekly shelf count',
      detail: _detail(),
      canApprove: true,
      onBack: () {},
      onApprove: () {},
      onCancel: () {},
    ),
  );

  testWidgets('the list filters by status and opens a count', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    StockCountSummary? opened;
    await tester.pumpWidget(desktopApp(DesktopStockCountsView(
      title: 'Stock counts',
      rows: _counts(),
      canCreate: true,
      onOpen: (r) => opened = r,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Weekly shelf count'), findsOneWidget);
    expect(find.text('Missing KES 3,420'), findsOneWidget);
    await tester.tap(find.text('Needs approval').first);
    await tester.pumpAndSettle();
    expect(find.text('Month-end count'), findsNothing);
    await tester.tap(find.text('Weekly shelf count'));
    await tester.pumpAndSettle();
    expect(opened?.id, '1');
  });

  testWidgets('a person without the right cannot start a count',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(DesktopStockCountsView(
      title: 'Stock counts',
      rows: _counts(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('New count'), findsNothing);
  });

  testWidgets('an empty list says what a count is for', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(const DesktopStockCountsView(
      title: 'Stock counts',
      rows: [],
      canCreate: true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('No stock counts yet'), findsOneWidget);
  });

  testWidgets('typing a quantity tells the screen and shows the difference',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final changed = <String>[];
    await tester.pumpWidget(desktopApp(_counting(onChanged: changed.add)));
    await tester.pumpAndSettle();
    // Third line: system 34, typed 30 -> -4.
    final field = find.byType(TextField).at(3); // search, then three rows
    await tester.enterText(field, '30');
    await tester.pumpAndSettle();
    expect(changed, isNotEmpty);
    expect(find.text('-4'), findsOneWidget);
  });

  testWidgets('a blind count shows no system quantities', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_counting(blind: true)));
    await tester.pumpAndSettle();
    expect(find.text('System'), findsNothing);
    expect(find.text('Difference'), findsNothing);
    expect(
        find.text('System quantities are hidden. Count what is really on the shelf.'),
        findsOneWidget);
  });

  testWidgets('Hand in needs at least one counted line; Save is a shortcut',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var saved = 0;
    var handedIn = 0;
    await tester.pumpWidget(desktopApp(_counting(
      onSave: () => saved++,
      onHandIn: () => handedIn++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hand in count'));
    expect(handedIn, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(saved, 1);
  });

  testWidgets('the review lists differences worst first and can approve',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var approved = 0;
    await tester.pumpWidget(desktopApp(DesktopCountReviewView(
      title: 'Weekly shelf count',
      detail: _detail(),
      canApprove: true,
      onApprove: () => approved++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Approve & adjust'), findsOneWidget);
    final worst = tester.getTopLeft(find.text('Cooking oil Fresh Fri 1L'));
    final mild = tester.getTopLeft(find.text('Brookside Milk 500ml'));
    expect(worst.dy, lessThan(mild.dy));
    await tester.tap(find.text('Approve & adjust'));
    expect(approved, 1);
  });

  testWidgets('a reviewer without approval rights only reads the count',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(DesktopCountReviewView(
      title: 'Weekly shelf count',
      detail: _detail(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Approve & adjust'), findsNothing);
    expect(find.text('Cancel count'), findsNothing);
  });

  testWidgets('a count with no gaps says so', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(DesktopCountReviewView(
      title: 'Weekly shelf count',
      detail: _detail(noDifferences: true),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Everything counted matched the system'), findsOneWidget);
  });
}
