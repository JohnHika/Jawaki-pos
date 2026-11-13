import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_finance_hub_view.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_finance_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

final _now = DateTime(2026, 11, 10, 10);

PeerDebtor _shop(String id, String name, {String? contact}) => PeerDebtor(
      id: id,
      tenantId: 't',
      name: name,
      contactName: contact,
      phone: '0712 000 111',
      email: null,
      address: null,
      notes: null,
      isActive: true,
      createdAt: _now,
      updatedAt: _now,
    );

ReceivablePayment _pay(String rid, double amount, DateTime at,
        {String method = 'CASH'}) =>
    ReceivablePayment(
      id: 'pay-$rid-${at.millisecondsSinceEpoch}',
      receivableId: rid,
      amount: amount,
      method: method,
      reference: null,
      notes: null,
      paidAt: at,
      createdAt: at,
    );

FinanceSnapshot _snapshot({bool empty = false}) {
  if (empty) {
    return FinanceSnapshot(
      branchId: 'b1',
      supplierPayablesOutstanding: 0,
      retailReceivablesOutstanding: 0,
      peerReceivablesOutstanding: 0,
    );
  }
  final shopA = _shop('s1', 'Mama Njeri Wholesalers', contact: 'Njeri W.');
  final shopB = _shop('s2', 'Kwa Ochieng Cosmetics');
  return FinanceSnapshot(
    branchId: 'b1',
    supplierPayablesOutstanding: 84300,
    retailReceivablesOutstanding: 12750,
    peerReceivablesOutstanding: 9200,
    savedAt: _now,
    payables: [
      FinancePayable(
        id: 'p1',
        supplierId: 'sup1',
        supplierName: 'FRESH FARM DISTRIBUTORS',
        supplierPhone: '0722 111 222',
        invoiceNumber: 'INV-2031',
        totalAmount: 52000,
        paidAmount: 12000,
        outstandingAmount: 40000,
        dueDate: DateTime(2026, 11, 4),
        status: 'PARTIAL',
        createdAt: DateTime(2026, 10, 20),
        payments: [
          FinancePayablePayment(
            id: 'pp1',
            amount: 12000,
            fundingSource: 'CASH_TILL',
            paidAt: DateTime(2026, 10, 28),
            notes: 'First instalment',
          ),
        ],
      ),
      FinancePayable(
        id: 'p2',
        supplierId: 'sup2',
        supplierName: 'Bidco Africa',
        supplierPhone: null,
        invoiceNumber: 'BA-77812',
        totalAmount: 44300,
        paidAmount: 0,
        outstandingAmount: 44300,
        dueDate: DateTime(2026, 11, 18),
        status: 'OPEN',
        createdAt: DateTime(2026, 11, 2),
      ),
      FinancePayable(
        id: 'p3',
        supplierId: 'sup3',
        supplierName: 'Kenchic Ltd',
        supplierPhone: null,
        invoiceNumber: 'KC-5530',
        totalAmount: 18000,
        paidAmount: 18000,
        outstandingAmount: 0,
        dueDate: DateTime(2026, 10, 30),
        status: 'PAID',
        createdAt: DateTime(2026, 10, 14),
      ),
    ],
    retailReceivables: [
      RetailReceivable(
        id: 'r1',
        saleId: 'sale1',
        receiptNumber: 'RC-10432',
        customerId: 'c1',
        customerName: 'Wanjiku Mwangi',
        originalAmount: 8500,
        outstandingAmount: 6000,
        dueDate: DateTime(2026, 11, 6),
        status: 'PARTIAL',
        createdAt: DateTime(2026, 10, 30),
        payments: [_pay('r1', 2500, DateTime(2026, 11, 8, 15, 30))],
      ),
      RetailReceivable(
        id: 'r2',
        saleId: 'sale2',
        receiptNumber: null,
        customerId: 'c2',
        customerName: 'Otieno Hardware',
        originalAmount: 6750,
        outstandingAmount: 6750,
        dueDate: DateTime(2026, 11, 20),
        status: 'OPEN',
        createdAt: DateTime(2026, 11, 3),
        payments: const [],
      ),
    ],
    peerDebtors: [shopA, shopB],
    peerReceivables: [
      PeerReceivable(
        id: 'pr1',
        debtor: shopA,
        reference: null,
        description: '12 cartons of unga',
        originalAmount: 12000,
        outstandingAmount: 9200,
        dueDate: DateTime(2026, 11, 12),
        status: 'PARTIAL',
        createdAt: DateTime(2026, 11, 1),
        payments: [_pay('pr1', 2800, DateTime(2026, 11, 10, 9, 15), method: 'MPESA')],
      ),
    ],
  );
}

Widget _app(Widget body, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  final home = Scaffold(body: body);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DesktopTheme.of(base),
    home:
        boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
  );
}

DesktopFinanceHubView _hub({
  FinanceHubTab tab = FinanceHubTab.overview,
  FinanceSnapshot? snapshot,
  bool local = false,
  bool canViewCustomerDetails = true,
  String? error,
  ValueChanged<FinancePayable>? onOpenPayable,
  ValueChanged<RetailReceivable>? onCollectRetail,
  ValueChanged<PeerReceivable>? onCollectPeer,
}) =>
    DesktopFinanceHubView(
      title: 'Finance',
      subtitle: 'Payables, customer credit and shop debts · Saved 10 Nov, 10:00',
      headerBottom: const DesktopFinanceTabs(
        current: FinanceSection.overview,
        available: {
          FinanceSection.overview,
          FinanceSection.expenses,
          FinanceSection.cashFlow,
        },
      ),
      snapshot: snapshot ?? _snapshot(),
      initialTab: tab,
      localWorkspace: local,
      canRecordRestock: true,
      canRecordSupplierPayment: true,
      canManageReceivables: true,
      canViewCustomerDetails: canViewCustomerDetails,
      errorMessage: error,
      now: _now,
      onRefresh: () {},
      onRetry: () {},
      onScan: () {},
      onManualInvoice: () {},
      onOpenPayable: onOpenPayable ?? (_) {},
      onPaySeveral: () {},
      onCollectRetail: onCollectRetail ?? (_) {},
      onCollectForCustomer: () {},
      onOpenShop: (_) {},
      onAddShop: () {},
      onAddDebt: () {},
      onCollectPeer: onCollectPeer ?? (_) {},
    );

const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final mode = dark ? 'dark' : 'light';
      for (final tab in FinanceHubTab.values) {
        testWidgets('hub ${tab.name} $mode ${entry.key}', (tester) async {
          useWindow(tester, entry.value);
          final key = GlobalKey();
          await tester.pumpWidget(
              _app(_hub(tab: tab), dark: dark, boundary: key));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Only the overview and the open-inspector views need a picture.
          if (tab == FinanceHubTab.overview || tab == FinanceHubTab.suppliers) {
            if (tab == FinanceHubTab.suppliers) {
              await tester.tap(find.text('Fresh Farm Distributors').first);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            await saveShot(tester, key,
                'build/shots/finance-hub-${tab.name}-$mode-${entry.key}.png');
          }
        });
      }
    }
  }

  testWidgets('overdue items come first on the overview', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_hub()));
    await tester.pumpAndSettle();
    expect(find.text('Overdue 6d'), findsOneWidget);
    expect(find.text('Overdue 4d'), findsOneWidget);
    // The overdue supplier bill sits above the one that is not late yet.
    final late = tester.getTopLeft(find.text('Fresh Farm Distributors').first);
    final fine = tester.getTopLeft(find.text('Bidco Africa').first);
    expect(late.dy, lessThan(fine.dy));
  });

  testWidgets('a supplier row opens its panel and the button opens the sheet',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    FinancePayable? opened;
    await tester.pumpWidget(_app(_hub(
      tab: FinanceHubTab.suppliers,
      onOpenPayable: (p) => opened = p,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bidco Africa'));
    await tester.pumpAndSettle();
    expect(find.text('PAYMENT HISTORY'), findsOneWidget);
    await tester.tap(find.text('Record a payment'));
    expect(opened?.id, 'p2');
  });

  testWidgets('a settled bill offers to open it, not to record a payment',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_hub(tab: FinanceHubTab.suppliers)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kenchic Ltd'));
    await tester.pumpAndSettle();
    expect(find.text('Open the bill'), findsOneWidget);
    expect(find.text('Record a payment'), findsNothing);
  });

  testWidgets('customers collect, shops collect per debt', (tester) async {
    useWindow(tester, _sizes['1366']!);
    RetailReceivable? retail;
    PeerReceivable? peer;
    await tester.pumpWidget(_app(_hub(
      tab: FinanceHubTab.customers,
      onCollectRetail: (r) => retail = r,
      onCollectPeer: (r) => peer = r,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wanjiku Mwangi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collect payment'));
    expect(retail?.id, 'r1');

    await tester.tap(find.text('Other shops'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mama Njeri Wholesalers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collect'));
    expect(peer?.id, 'pr1');
  });

  testWidgets(
    'desktop finance masks customer names and identifiers without customers.view while retaining balances and collection controls',
    (tester) async {
      useWindow(tester, _sizes['1366']!);
      await tester.pumpWidget(_app(_hub(
        tab: FinanceHubTab.customers,
        canViewCustomerDetails: false,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Wanjiku Mwangi'), findsNothing);
      expect(find.text('Otieno Hardware'), findsNothing);
      expect(find.text('c1'), findsNothing);
      expect(find.textContaining('6,000'), findsWidgets);
      expect(find.text('Collect for a customer'), findsOneWidget);

      await tester.tap(find.text('Receipt RC-10432'));
      await tester.pumpAndSettle();
      expect(find.text('Wanjiku Mwangi'), findsNothing);
      expect(find.text('Collect payment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop finance overview masks customer names in recent collections without customers.view',
    (tester) async {
      useWindow(tester, _sizes['1366']!);
      await tester.pumpWidget(_app(_hub(canViewCustomerDetails: false)));
      await tester.pumpAndSettle();

      expect(find.text('Wanjiku Mwangi'), findsNothing);
      expect(find.text('Customer details hidden'), findsWidgets);
      expect(find.textContaining('2,500'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a local shop has no Other shops tab', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_hub(local: true)));
    await tester.pumpAndSettle();
    expect(find.text('Other shops'), findsNothing);
    expect(find.text('Other shops owe us'), findsNothing);
  });

  testWidgets('empty ledgers say what the tab is for', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_hub(snapshot: _snapshot(empty: true))));
    await tester.pumpAndSettle();
    expect(find.text('You are all square'), findsOneWidget);
    await tester.tap(find.text('Suppliers'));
    await tester.pumpAndSettle();
    expect(find.text('No supplier bills yet'), findsOneWidget);
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();
    expect(find.text('No customer credit is outstanding'), findsOneWidget);
    await tester.tap(find.text('Other shops'));
    await tester.pumpAndSettle();
    expect(find.text('No other shops added yet'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the saved figures and offers Retry',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_hub(error: 'No connection.')));
    await tester.pumpAndSettle();
    expect(find.text('No connection.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('KES 84,300'), findsOneWidget);
  });
}
