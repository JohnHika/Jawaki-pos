import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:axon_pos/features/finance/presentation/providers/finance_hub_controller.dart';
import 'package:axon_pos/features/finance/presentation/screens/finance_screen.dart';
import 'package:go_router/go_router.dart';

FinanceSnapshot _snapshot({
  String branchId = 'branch-1',
  double payable = 0,
  double retail = 0,
  double peer = 0,
  List<FinancePayable> payables = const <FinancePayable>[],
  List<RetailReceivable> retailReceivables = const <RetailReceivable>[],
  List<PeerDebtor> peerDebtors = const <PeerDebtor>[],
  List<PeerReceivable> peerReceivables = const <PeerReceivable>[],
}) =>
    FinanceSnapshot(
      branchId: branchId,
      supplierPayablesOutstanding: payable,
      retailReceivablesOutstanding: retail,
      peerReceivablesOutstanding: peer,
      payables: payables,
      retailReceivables: retailReceivables,
      peerDebtors: peerDebtors,
      peerReceivables: peerReceivables,
      savedAt: DateTime.utc(2026, 9, 11, 9),
    );

FinancePayable _payable(double outstanding) => FinancePayable(
      id: 'payable-1',
      supplierId: 'supplier-1',
      supplierName: 'Fresh Farm',
      supplierPhone: null,
      invoiceNumber: 'INV-7',
      totalAmount: outstanding,
      paidAmount: 0,
      outstandingAmount: outstanding,
      dueDate: DateTime.utc(2026, 9, 20),
      status: 'OPEN',
      createdAt: DateTime.utc(2026, 9, 1),
    );

RetailReceivable _retail(double outstanding) => RetailReceivable(
      id: 'retail-1',
      saleId: 'sale-1',
      receiptNumber: 'R-100',
      customerId: 'customer-1',
      customerName: 'Ada',
      originalAmount: outstanding,
      outstandingAmount: outstanding,
      dueDate: DateTime.utc(2026, 9, 5),
      status: 'OPEN',
      createdAt: DateTime.utc(2026, 9, 2),
      payments: const <ReceivablePayment>[],
    );

const _debtor = PeerDebtor(
  id: 'debtor-1',
  tenantId: 'tenant-1',
  name: 'Neighbour Shop',
  contactName: null,
  phone: null,
  email: null,
  address: null,
  notes: null,
  isActive: true,
  createdAt: null,
  updatedAt: null,
);

PeerReceivable _peer(double outstanding) => PeerReceivable(
      id: 'peer-1',
      debtor: _debtor,
      reference: null,
      description: 'Wholesale stock',
      originalAmount: outstanding,
      outstandingAmount: outstanding,
      dueDate: DateTime.utc(2026, 9, 6),
      status: 'OPEN',
      createdAt: DateTime.utc(2026, 9, 2),
      payments: const <ReceivablePayment>[],
    );

class _StubSource implements FinanceHubDataSource {
  _StubSource({this.cached, this.error, this.refreshCompleter});

  final FinanceSnapshot? cached;
  Object? error;
  Completer<FinanceSnapshot>? refreshCompleter;
  int refreshCalls = 0;

  @override
  FinanceSnapshot? loadCachedSnapshot(String tenantId, String branchId) =>
      cached;

  @override
  Future<FinanceSnapshot> refresh(String branchId) async {
    refreshCalls++;
    final pending = refreshCompleter;
    if (pending != null) return pending.future;
    final failure = error;
    if (failure != null) throw failure;
    return _snapshot(
      payable: 1250,
      retail: 320,
      peer: 100,
      payables: <FinancePayable>[_payable(1250)],
      retailReceivables: <RetailReceivable>[_retail(320)],
      peerReceivables: <PeerReceivable>[_peer(100)],
      peerDebtors: const <PeerDebtor>[_debtor],
    );
  }

  @override
  Future<void> createPeerDebtor(
      {required String name, String? contact}) async {}

  @override
  Future<void> createPeerReceivable(PeerReceivableRequest request) async {}

  @override
  Future<void> recordRetailCollection(
      ReceivableCollectionRequest request) async {}

  @override
  Future<void> recordPeerCollection(
      ReceivableCollectionRequest request) async {}
}

Widget _host(FinanceHubController controller) => ProviderScope(
      overrides: [financeHubProvider.overrideWith((ref) => controller)],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/finance',
          routes: [
            GoRoute(
              path: '/finance',
              builder: (context, state) => FinanceScreen(
                prefill: state.uri.queryParameters.containsKey('prefill')
                    ? const RestockPrefill(
                        productName: 'x', quantity: 1, unitCost: 1)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets(
    'cached snapshot renders totals immediately while refresh is in flight',
    (tester) async {
      final source = _StubSource(
        cached: _snapshot(payable: 900, retail: 150, peer: 60),
        refreshCompleter: Completer<FinanceSnapshot>(),
      );
      final controller = FinanceHubController(
        source: source,
        tenantId: 'tenant-1',
        branchId: 'branch-1',
      );
      await tester.pumpWidget(_host(controller));
      await tester.pump();

      expect(find.text('We owe suppliers'), findsOneWidget);
      expect(find.text('Customers owe us'), findsOneWidget);
      expect(find.text('Other shops owe us'), findsOneWidget);
      expect(find.textContaining('900'), findsWidgets);
      expect(find.textContaining('150'), findsWidgets);
      expect(find.textContaining('60'), findsWidgets);
      // Refresh is still in flight; only the cached figures painted.
      expect(source.refreshCalls, 1);
      expect(find.text('Refreshing'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh failure keeps cached figures and shows the reconnect banner',
    (tester) async {
      final source = _StubSource(
        cached: _snapshot(payable: 900, retail: 150, peer: 60),
        error: Exception('offline'),
      );
      final controller = FinanceHubController(
        source: source,
        tenantId: 'tenant-1',
        branchId: 'branch-1',
      );
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      expect(source.refreshCalls, 1);
      expect(find.textContaining('900'), findsWidgets);
      expect(find.text('Couldn’t refresh — showing saved figures'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No supplier data'), findsNothing);
    },
  );

  testWidgets(
    'no snapshot and a failed refresh shows an explicit error, not zeros',
    (tester) async {
      final source = _StubSource(error: Exception('offline'));
      final controller = FinanceHubController(
        source: source,
        tenantId: 'tenant-1',
        branchId: 'branch-1',
      );
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t load Finance. Reconnect and try again.'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('KES 0'), findsNothing);
    },
  );

  testWidgets('successful refresh reveals all four ledgers', (tester) async {
    final controller = FinanceHubController(
      source: _StubSource(),
      tenantId: 'tenant-1',
      branchId: 'branch-1',
    );
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suppliers'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Farm'), findsOneWidget);

    await tester.tap(find.text('Customer Credit'));
    await tester.pumpAndSettle();
    expect(find.text('R-100'), findsOneWidget);

    await tester.tap(find.text('Other Shops'));
    await tester.pumpAndSettle();
    expect(find.text('Neighbour Shop'), findsWidgets);
    expect(find.text('Wholesale stock'), findsOneWidget);

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1,250'), findsWidgets);
  });
}
