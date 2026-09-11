import 'dart:async';

import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:axon_pos/features/finance/presentation/providers/finance_hub_controller.dart';
import 'package:axon_pos/features/finance/presentation/screens/finance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FinanceHubController', () {
    test('publishes the cached snapshot before the background refresh resolves',
        () {
      final source = _FakeFinanceHubDataSource(cached: _snapshot());
      final controller = FinanceHubController(
        source: source,
        tenantId: 'tenant-a',
        branchId: 'branch-a',
      );

      expect(controller.state.snapshot?.supplierPayablesOutstanding, 1200);
      expect(controller.state.isRefreshing, isTrue);
      expect(source.refreshCalls, 1);
      source.refreshCompleter.complete(_snapshot(payable: 1500));
      controller.dispose();
    });

    test('rejects a receivable request without a selected branch', () async {
      final source = _FakeFinanceHubDataSource(cached: _snapshot());
      final controller = FinanceHubController(
        source: source,
        tenantId: 'tenant-a',
        branchId: '',
      );

      await expectLater(
        controller.createPeerReceivable(const PeerReceivableRequest(
          branchId: '',
          debtorId: 'debtor-1',
          description: 'Stock',
          amount: 50,
        )),
        throwsA(isA<FinanceFormException>()),
      );
      controller.dispose();
    });

    test('keeps cached figures and exposes retryable reconnect error',
        () async {
      final source = _FakeFinanceHubDataSource(cached: _snapshot());
      final controller = FinanceHubController(
        source: source,
        tenantId: 'tenant-a',
        branchId: 'branch-a',
      );

      source.refreshCompleter.completeError(Exception('offline'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.snapshot?.supplierPayablesOutstanding, 1200);
      expect(controller.state.errorMessage,
          'Couldn’t refresh — showing saved figures');
      expect(controller.state.canRetry, isTrue);
      controller.dispose();
    });
  });

  testWidgets('cached finance snapshot renders immediately while refreshing',
      (tester) async {
    final source = _FakeFinanceHubDataSource(cached: _snapshot());
    final controller = FinanceHubController(
      source: source,
      tenantId: 'tenant-a',
      branchId: 'branch-a',
    );

    await tester.pumpWidget(_app(controller));

    expect(find.text('KES 1,200'), findsOneWidget);
    expect(find.text('Refreshing'), findsOneWidget);
    source.refreshCompleter.complete(_snapshot(payable: 1500));
    await tester.pump();
  });

  testWidgets('refresh error retains cached totals and shows reconnect retry',
      (tester) async {
    final source = _FakeFinanceHubDataSource(cached: _snapshot());
    final controller = FinanceHubController(
      source: source,
      tenantId: 'tenant-a',
      branchId: 'branch-a',
    );

    await tester.pumpWidget(_app(controller));
    source.refreshCompleter.completeError(Exception('offline'));
    await tester.pump();

    expect(find.text('KES 1,200'), findsOneWidget);
    expect(
        find.text('Couldn’t refresh — showing saved figures'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(find.text('No supplier data'), findsNothing);
  });

  testWidgets('shows four finance tabs with separate figures', (tester) async {
    final source = _FakeFinanceHubDataSource(cached: _snapshot());
    final controller = FinanceHubController(
      source: source,
      tenantId: 'tenant-a',
      branchId: 'branch-a',
    );
    source.refreshCompleter.complete(_snapshot());

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(find.text('Customer Credit'), findsOneWidget);
    expect(find.text('Other Shops'), findsOneWidget);
    expect(find.text('We owe suppliers'), findsOneWidget);

    await tester.tap(find.text('Suppliers'));
    await tester.pump();
    expect(find.text('Fresh Farm'), findsOneWidget);

    await tester.tap(find.text('Customer Credit'));
    await tester.pump();
    expect(find.text('R-100'), findsOneWidget);

    await tester.tap(find.text('Other Shops'));
    await tester.pump();
    expect(find.text('Neighbour Shop'), findsWidgets);
  });

  testWidgets('peer receivable validates then posts real request with branch',
      (tester) async {
    final source = _FakeFinanceHubDataSource(cached: _snapshot());
    final controller = FinanceHubController(
      source: source,
      tenantId: 'tenant-a',
      branchId: 'branch-a',
    );
    source.refreshCompleter.complete(_snapshot());
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.text('Other Shops'));
    await tester.pump();
    await tester.tap(find.text('Add receivable'));
    await tester.pumpAndSettle();
    final create = find.text('Create receivable');
    await tester.scrollUntilVisible(create, 420,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(create, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Description is required'), findsOneWidget);
    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('peer-description')), 'Stock transfer');
    await tester.enterText(find.byKey(const Key('peer-amount')), '250');
    await tester.scrollUntilVisible(create, 420,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(create, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(source.createdReceivable, isNotNull);
    expect(source.createdReceivable!.branchId, 'branch-a');
    expect(source.createdReceivable!.description, 'Stock transfer');
    expect(source.createdReceivable!.amount, 250);
  });
}

Widget _app(FinanceHubController controller) => ProviderScope(
      overrides: <Override>[
        financeHubProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const FinanceScreen(),
      ),
    );

FinanceSnapshot _snapshot({double payable = 1200}) => FinanceSnapshot(
      branchId: 'branch-a',
      supplierPayablesOutstanding: payable,
      retailReceivablesOutstanding: 320,
      peerReceivablesOutstanding: 180,
      savedAt: DateTime.utc(2026, 9, 11, 9),
      payables: <FinancePayable>[
        FinancePayable(
          id: 'payable-1',
          supplierId: 'supplier-1',
          supplierName: 'Fresh Farm',
          supplierPhone: null,
          invoiceNumber: 'INV-7',
          totalAmount: payable,
          paidAmount: 0,
          outstandingAmount: payable,
          dueDate: DateTime.utc(2026, 9, 1),
          status: 'OPEN',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      ],
      retailReceivables: <RetailReceivable>[
        RetailReceivable(
          id: 'retail-1',
          saleId: 'sale-1',
          receiptNumber: 'R-100',
          customerId: 'customer-1',
          customerName: 'Ada',
          originalAmount: 320,
          outstandingAmount: 320,
          dueDate: DateTime.utc(2026, 9, 1),
          status: 'OPEN',
          createdAt: DateTime.utc(2026, 8, 1),
          payments: const <ReceivablePayment>[],
        ),
      ],
      peerDebtors: <PeerDebtor>[
        PeerDebtor(
          id: 'debtor-1',
          tenantId: 'tenant-a',
          name: 'Neighbour Shop',
          contactName: null,
          phone: null,
          email: null,
          address: null,
          notes: null,
          isActive: true,
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      ],
      peerReceivables: <PeerReceivable>[
        PeerReceivable(
          id: 'peer-1',
          debtor: const PeerDebtor(
            id: 'debtor-1',
            tenantId: 'tenant-a',
            name: 'Neighbour Shop',
            contactName: null,
            phone: null,
            email: null,
            address: null,
            notes: null,
            isActive: true,
            createdAt: null,
            updatedAt: null,
          ),
          reference: 'B2B-1',
          description: 'Stock transfer',
          originalAmount: 180,
          outstandingAmount: 180,
          dueDate: DateTime.utc(2026, 9, 1),
          status: 'OPEN',
          createdAt: DateTime.utc(2026, 8, 1),
          payments: const <ReceivablePayment>[],
        ),
      ],
    );

class _FakeFinanceHubDataSource implements FinanceHubDataSource {
  _FakeFinanceHubDataSource({required this.cached});

  final FinanceSnapshot? cached;
  final Completer<FinanceSnapshot> refreshCompleter =
      Completer<FinanceSnapshot>();
  int refreshCalls = 0;
  PeerReceivableRequest? createdReceivable;

  @override
  FinanceSnapshot? loadCachedSnapshot(String tenantId, String branchId) =>
      cached;

  @override
  Future<FinanceSnapshot> refresh(String branchId) {
    refreshCalls++;
    return refreshCompleter.future;
  }

  @override
  Future<void> createPeerDebtor(
      {required String name, String? contact}) async {}

  @override
  Future<void> createPeerReceivable(PeerReceivableRequest request) async {
    createdReceivable = request;
  }

  @override
  Future<void> recordPeerCollection(
      ReceivableCollectionRequest request) async {}

  @override
  Future<void> recordRetailCollection(
      ReceivableCollectionRequest request) async {}
}
