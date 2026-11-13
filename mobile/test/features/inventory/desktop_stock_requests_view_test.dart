import 'package:axon_pos/features/inventory/presentation/desktop/desktop_restock_view.dart';
import 'package:axon_pos/features/inventory/presentation/desktop/desktop_stock_requests_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

List<DesktopStockRequest> _requests() => [
      DesktopStockRequest(
        id: 'a',
        productName: 'Brookside Milk 500ml',
        sku: 'BRK-500',
        quantity: 48,
        unit: 'piece',
        priority: 'urgent',
        status: 'PENDING',
        requester: 'Achieng Otieno',
        branch: 'Westlands',
        createdAt: DateTime(2026, 11, 10, 8, 12),
        currentStock: 0,
        reason: 'Sold out before noon three days running.',
      ),
      DesktopStockRequest(
        id: 'b',
        productName: 'Unga Jogoo 2kg',
        sku: 'UNG-2KG',
        quantity: 20,
        unit: 'bale',
        priority: 'normal',
        status: 'PENDING',
        requester: 'Brian Kamau',
        branch: 'Westlands',
        createdAt: DateTime(2026, 11, 9, 16, 40),
        currentStock: 12,
      ),
      DesktopStockRequest(
        id: 'c',
        productName: 'Sugar Mumias 1kg',
        sku: 'SUG-1KG',
        quantity: 30,
        unit: 'piece',
        priority: 'low',
        status: 'PENDING',
        requester: 'Achieng Otieno',
        branch: 'Karen',
        createdAt: DateTime(2026, 11, 8, 11, 5),
        currentStock: 64,
      ),
    ];

Widget _view({
  List<DesktopStockRequest>? rows,
  String status = 'PENDING',
  ValueChanged<String>? onApprove,
  ValueChanged<String>? onReject,
  ValueChanged<String>? onFulfill,
  ValueChanged<String>? onStatus,
  String? error,
}) =>
    DesktopStockRequestsView(
      rows: rows ?? _requests(),
      status: status,
      onStatus: onStatus ?? (_) {},
      errorMessage: error,
      onApprove: onApprove ?? (_) {},
      onReject: onReject ?? (_) {},
      onFulfill: onFulfill ?? (_) {},
      onNewRequest: () {},
      onRefresh: () {},
      onRetry: () {},
    );

DesktopRestockView _restock({bool empty = false}) => DesktopRestockView(
      availableCash: 42500,
      trimmedCount: empty ? 0 : 2,
      aiRationale: empty
          ? null
          : 'Milk and unga are selling fastest this week, so they come first. '
              'Two slower lines were left out to keep within your cash.',
      items: empty
          ? const []
          : const [
              DesktopRestockItem(
                productName: 'Brookside Milk 500ml',
                suggestedQty: 96,
                unitCost: 48,
                estimatedCost: 4608,
                daysLeft: 1,
                currentStock: 6,
              ),
              DesktopRestockItem(
                productName: 'Unga Jogoo 2kg',
                suggestedQty: 40,
                unitCost: 168,
                estimatedCost: 6720,
                daysLeft: 3,
                currentStock: 18,
              ),
              DesktopRestockItem(
                productName: 'Sugar Mumias 1kg',
                suggestedQty: 60,
                unitCost: 142,
                estimatedCost: 8520,
                daysLeft: 9,
                currentStock: 52,
              ),
              DesktopRestockItem(
                productName: 'Cooking oil Fresh Fri 1L',
                suggestedQty: 24,
                unitCost: 295,
                estimatedCost: 7080,
                daysLeft: 999,
                currentStock: 31,
              ),
            ],
      onBuy: (_) {},
      onRefresh: () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('inventory-requests', () => _view(), beforeShot: (tester) async {
    await tester.tap(find.text('Brookside Milk 500ml'));
    await tester.pumpAndSettle();
  });
  shotMatrix('inventory-restock', () => _restock());

  testWidgets('approve and reject act on the open request', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    String? approved;
    String? rejected;
    await tester.pumpWidget(desktopApp(_view(
      onApprove: (id) => approved = id,
      onReject: (id) => rejected = id,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unga Jogoo 2kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    expect(approved, 'b');
    await tester.tap(find.text('Reject'));
    expect(rejected, 'b');
  });

  testWidgets('an approved request can be marked fulfilled', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    String? done;
    final rows = [
      for (final r in _requests())
        DesktopStockRequest(
          id: r.id,
          productName: r.productName,
          sku: r.sku,
          quantity: r.quantity,
          unit: r.unit,
          priority: r.priority,
          status: 'APPROVED',
          requester: r.requester,
          branch: r.branch,
          createdAt: r.createdAt,
          currentStock: r.currentStock,
        ),
    ];
    await tester.pumpWidget(desktopApp(_view(
      rows: rows,
      status: 'APPROVED',
      onFulfill: (id) => done = id,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sugar Mumias 1kg'));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.text('Mark as fulfilled'));
    expect(done, 'c');
  });

  testWidgets('the status filter and the search narrow the list',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    String? status;
    await tester.pumpWidget(desktopApp(_view(onStatus: (s) => status = s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fulfilled'));
    expect(status, 'FULFILLED');
    await tester.enterText(find.byType(TextField), 'karen');
    await tester.pumpAndSettle();
    expect(find.text('Sugar Mumias 1kg'), findsOneWidget);
    expect(find.text('Unga Jogoo 2kg'), findsNothing);
  });

  testWidgets('an empty pending list says everything is handled',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view(rows: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No pending requests'), findsOneWidget);
    expect(find.textContaining('All caught up'), findsOneWidget);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(
        desktopApp(_view(rows: const [], error: 'No connection.')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load stock requests"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('restock marks what runs out within three days as urgent',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    String? bought;
    await tester.pumpWidget(desktopApp(DesktopRestockView(
      items: const [
        DesktopRestockItem(
          productName: 'Brookside Milk 500ml',
          suggestedQty: 96,
          unitCost: 48,
          estimatedCost: 4608,
          daysLeft: 1,
          currentStock: 6,
        ),
      ],
      onBuy: (i) => bought = i.productName,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Urgent'), findsWidgets);
    await tester.tap(find.text('Buy').last);
    expect(bought, 'Brookside Milk 500ml');
  });

  testWidgets('restock with nothing to buy explains why', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_restock(empty: true)));
    await tester.pumpAndSettle();
    expect(find.text('Stock levels look healthy'), findsOneWidget);
  });
}
