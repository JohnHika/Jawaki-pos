import 'dart:async';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/finance/data/finance_repository.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Finance domain models', () {
    test('parse the complete finance snapshot JSON contract', () {
      final snapshot = FinanceSnapshot.fromJson(<String, dynamic>{
        'branchId': 'branch-a',
        'supplierPayablesOutstanding': 1250.50,
        'retailReceivablesOutstanding': 320.25,
        'peerReceivablesOutstanding': 99.75,
        'savedAt': '2026-09-11T09:30:00.000Z',
        'payables': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'payable-1',
            'supplier': <String, dynamic>{
              'id': 'supplier-1',
              'name': 'Fresh Farm',
              'phone': '0712345678',
            },
            'invoiceNumber': 'INV-7',
            'totalAmount': 1500,
            'paidAmount': 249.5,
            'outstandingAmount': 1250.5,
            'dueDate': '2026-09-20T00:00:00.000Z',
            'status': 'PARTIAL',
            'createdAt': '2026-09-01T00:00:00.000Z',
          },
        ],
        'retailReceivables': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'retail-1',
            'saleId': 'sale-1',
            'receiptNumber': 'R-100',
            'customer': <String, dynamic>{'id': 'customer-1', 'name': 'Ada'},
            'originalAmount': 500,
            'outstandingAmount': 320.25,
            'dueDate': null,
            'status': 'PARTIAL',
            'createdAt': '2026-09-02T00:00:00.000Z',
            'payments': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'payment-1',
                'receivableId': 'retail-1',
                'amount': 179.75,
                'method': 'MPESA',
                'reference': 'ABC123',
                'notes': null,
                'paidAt': '2026-09-03T00:00:00.000Z',
                'createdAt': '2026-09-03T00:00:00.000Z',
              },
            ],
          },
        ],
        'peerDebtors': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'debtor-1',
            'tenantId': 'tenant-a',
            'name': 'Neighbour Shop',
            'contactName': 'Sam',
            'phone': null,
            'email': null,
            'address': null,
            'notes': null,
            'isActive': true,
            'createdAt': '2026-09-01T00:00:00.000Z',
            'updatedAt': '2026-09-01T00:00:00.000Z',
          },
        ],
        'peerReceivables': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'peer-1',
            'debtor': <String, dynamic>{
              'id': 'debtor-1',
              'tenantId': 'tenant-a',
              'name': 'Neighbour Shop',
              'isActive': true,
              'createdAt': '2026-09-01T00:00:00.000Z',
              'updatedAt': '2026-09-01T00:00:00.000Z',
            },
            'reference': 'B2B-1',
            'description': 'Stock transfer',
            'originalAmount': 200,
            'outstandingAmount': 99.75,
            'dueDate': null,
            'status': 'PARTIAL',
            'createdAt': '2026-09-02T00:00:00.000Z',
            'payments': <Map<String, dynamic>>[],
          },
        ],
      });

      expect(snapshot.payables.single.supplierName, 'Fresh Farm');
      expect(snapshot.retailReceivables.single.payments.single.method, 'MPESA');
      expect(snapshot.peerReceivables.single.debtor.name, 'Neighbour Shop');
      expect(FinanceSnapshot.fromJson(snapshot.toJson()).toJson(),
          snapshot.toJson());
    });
  });

  group('Finance snapshot cache', () {
    test(
        'isolates cached snapshots by tenant and branch and ignores invalid JSON',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = StorageService();
      await storage.initialize();

      final tenantASnapshot = _snapshot(branchId: 'branch-a', payableTotal: 10);
      final tenantBSnapshot = _snapshot(branchId: 'branch-a', payableTotal: 20);
      await storage.saveFinanceSnapshot(
        tenantId: 'tenant-a',
        branchId: 'branch-a',
        snapshot: tenantASnapshot,
      );
      await storage.saveFinanceSnapshot(
        tenantId: 'tenant-b',
        branchId: 'branch-a',
        snapshot: tenantBSnapshot,
      );

      expect(
        storage.getFinanceSnapshot(tenantId: 'tenant-a', branchId: 'branch-a'),
        tenantASnapshot,
      );
      expect(
        storage.getFinanceSnapshot(tenantId: 'tenant-b', branchId: 'branch-a'),
        tenantBSnapshot,
      );
      expect(
        storage.getFinanceSnapshot(tenantId: 'tenant-a', branchId: 'branch-b'),
        isNull,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageService.financeSnapshotKey('tenant-a', 'branch-b'),
        '{invalid json',
      );
      expect(
        storage.getFinanceSnapshot(tenantId: 'tenant-a', branchId: 'branch-b'),
        isNull,
      );

      await storage.clearFinanceSnapshot(
        tenantId: 'tenant-a',
        branchId: 'branch-a',
      );
      expect(
        storage.getFinanceSnapshot(tenantId: 'tenant-a', branchId: 'branch-a'),
        isNull,
      );
      expect(
        storage.getFinanceSnapshot(tenantId: 'tenant-b', branchId: 'branch-a'),
        tenantBSnapshot,
      );
    });
  });

  group('FinanceRepository', () {
    test('retains an existing cache snapshot when a remote refresh fails',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = StorageService();
      await storage.initialize();
      final cached = _snapshot(branchId: 'branch-a', payableTotal: 55);
      await storage.saveFinanceSnapshot(
        tenantId: 'tenant-a',
        branchId: 'branch-a',
        snapshot: cached,
      );
      final repository = FinanceRepository(
        apiClient: _FakeFinanceApi(failRetail: true),
        storage: storage,
        tenantId: 'tenant-a',
      );

      await expectLater(
        repository.refresh('branch-a'),
        throwsA(isA<DioException>()),
      );
      expect(repository.loadCachedSnapshot('tenant-a', 'branch-a'), cached);
    });

    test('starts all remote requests in parallel and maps every response',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = StorageService();
      await storage.initialize();
      final api = _FakeFinanceApi.withCompleters();
      final repository = FinanceRepository(
        apiClient: api,
        storage: storage,
        tenantId: 'tenant-a',
      );

      final refresh = repository.refresh('branch-a');
      await Future<void>.delayed(Duration.zero);
      expect(
        api.calls,
        unorderedEquals(<String>[
          'overview',
          'payables',
          'retail',
          'debtors',
          'peerReceivables',
        ]),
      );

      api.completeAll();
      final snapshot = await refresh;

      expect(snapshot.branchId, 'branch-a');
      expect(snapshot.supplierPayablesOutstanding, 50);
      expect(snapshot.payables.single.id, 'payable-1');
      expect(snapshot.retailReceivables.single.id, 'retail-1');
      expect(snapshot.peerDebtors.single.id, 'debtor-1');
      expect(snapshot.peerReceivables.single.id, 'peer-1');
      expect(
        repository.loadCachedSnapshot('tenant-a', 'branch-a'),
        snapshot,
      );
    });
  });
}

FinanceSnapshot _snapshot(
    {required String branchId, required double payableTotal}) {
  return FinanceSnapshot(
    branchId: branchId,
    supplierPayablesOutstanding: payableTotal,
    retailReceivablesOutstanding: 0,
    peerReceivablesOutstanding: 0,
    savedAt: DateTime.utc(2026, 9, 11),
  );
}

class _FakeFinanceApi extends ApiClient {
  _FakeFinanceApi({this.failRetail = false}) : super(Dio());

  _FakeFinanceApi.withCompleters()
      : failRetail = false,
        super(Dio()) {
    _overviewCompleter = Completer<FinanceSnapshot>();
    _payablesCompleter = Completer<List<FinancePayable>>();
    _retailCompleter = Completer<List<RetailReceivable>>();
    _debtorsCompleter = Completer<List<PeerDebtor>>();
    _peerReceivablesCompleter = Completer<List<PeerReceivable>>();
  }

  final bool failRetail;
  final List<String> calls = <String>[];
  Completer<FinanceSnapshot>? _overviewCompleter;
  Completer<List<FinancePayable>>? _payablesCompleter;
  Completer<List<RetailReceivable>>? _retailCompleter;
  Completer<List<PeerDebtor>>? _debtorsCompleter;
  Completer<List<PeerReceivable>>? _peerReceivablesCompleter;

  @override
  Future<FinanceSnapshot> getFinanceOverview(String branchId) {
    calls.add('overview');
    return _overviewCompleter?.future ?? Future.value(_overview(branchId));
  }

  @override
  Future<List<FinancePayable>> getFinancePayables(String branchId,
      {String? status}) {
    calls.add('payables');
    return _payablesCompleter?.future ??
        Future.value(<FinancePayable>[_payable()]);
  }

  @override
  Future<List<RetailReceivable>> getRetailReceivables(String branchId,
      {String? status}) {
    calls.add('retail');
    if (failRetail) {
      return Future.error(DioException(
        requestOptions: RequestOptions(path: '/finance/retail-receivables'),
      ));
    }
    return _retailCompleter?.future ??
        Future.value(<RetailReceivable>[_retailReceivable()]);
  }

  @override
  Future<List<PeerDebtor>> getPeerDebtors() {
    calls.add('debtors');
    return _debtorsCompleter?.future ?? Future.value(<PeerDebtor>[_debtor()]);
  }

  @override
  Future<List<PeerReceivable>> getPeerReceivables(String branchId,
      {String? status}) {
    calls.add('peerReceivables');
    return _peerReceivablesCompleter?.future ??
        Future.value(<PeerReceivable>[_peerReceivable()]);
  }

  void completeAll() {
    _overviewCompleter!.complete(_overview('branch-a'));
    _payablesCompleter!.complete(<FinancePayable>[_payable()]);
    _retailCompleter!.complete(<RetailReceivable>[_retailReceivable()]);
    _debtorsCompleter!.complete(<PeerDebtor>[_debtor()]);
    _peerReceivablesCompleter!.complete(<PeerReceivable>[_peerReceivable()]);
  }

  FinanceSnapshot _overview(String branchId) => FinanceSnapshot(
        branchId: branchId,
        supplierPayablesOutstanding: 50,
        retailReceivablesOutstanding: 25,
        peerReceivablesOutstanding: 10,
      );

  FinancePayable _payable() => const FinancePayable(
        id: 'payable-1',
        supplierId: 'supplier-1',
        supplierName: 'Supplier',
        supplierPhone: null,
        invoiceNumber: null,
        totalAmount: 50,
        paidAmount: 0,
        outstandingAmount: 50,
        dueDate: null,
        status: 'OPEN',
        createdAt: null,
      );

  RetailReceivable _retailReceivable() => RetailReceivable(
        id: 'retail-1',
        saleId: 'sale-1',
        receiptNumber: null,
        customerId: null,
        customerName: null,
        originalAmount: 25,
        outstandingAmount: 25,
        dueDate: null,
        status: 'OPEN',
        createdAt: null,
        payments: <ReceivablePayment>[],
      );

  PeerDebtor _debtor() => const PeerDebtor(
        id: 'debtor-1',
        tenantId: 'tenant-a',
        name: 'Peer',
        contactName: null,
        phone: null,
        email: null,
        address: null,
        notes: null,
        isActive: true,
        createdAt: null,
        updatedAt: null,
      );

  PeerReceivable _peerReceivable() => PeerReceivable(
        id: 'peer-1',
        debtor: _debtor(),
        reference: null,
        description: 'Goods',
        originalAmount: 10,
        outstandingAmount: 10,
        dueDate: null,
        status: 'OPEN',
        createdAt: null,
        payments: const <ReceivablePayment>[],
      );
}
