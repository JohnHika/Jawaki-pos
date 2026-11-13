import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:axon_pos/features/finance/presentation/providers/finance_hub_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local finance loader masks names but retains receivable balances',
      () async {
    getIt.pushNewScope();
    final database = _FinanceDatabase();
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(_LocalFinanceAuth());
    final container = ProviderContainer(overrides: [
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['finance.view', 'finance.manage_receivables']),
      ),
    ]);
    final subscription = container.listen(financeHubProvider, (_, __) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await database.close();
      await getIt.popScope();
    });

    await container.read(financeHubProvider.notifier).refresh();
    final receivable =
        container.read(financeHubProvider).snapshot!.retailReceivables.single;

    expect(receivable.customerName, isNull);
    expect(receivable.customerId, isNull);
    expect(receivable.id, isNot(contains('customer-1')));
    expect(receivable.saleId, isNot('customer-1'));
    expect(receivable.toJson().toString(), isNot(contains('customer-1')));
    expect(receivable.outstandingAmount, 320);
    expect(receivable.originalAmount, 400);

    await container.read(financeHubProvider.notifier).recordRetailCollection(
          ReceivableCollectionRequest(
            receivableId: receivable.id,
            branchId: 'branch-1',
            amount: 25,
            method: 'CASH',
          ),
        );
    expect(database.lastAllocations, [
      {'receivableId': 'local-customer:customer-1', 'amount': 25},
    ]);
  });

  test('cached and refreshed finance snapshots redact customer identifiers',
      () async {
    final rawSnapshot = FinanceSnapshot(
      branchId: 'branch-1',
      supplierPayablesOutstanding: 0,
      retailReceivablesOutstanding: 320,
      peerReceivablesOutstanding: 0,
      retailReceivables: [
        RetailReceivable(
          id: 'receivable-1',
          saleId: 'sale-1',
          receiptNumber: 'R-100',
          customerId: 'customer-1',
          customerName: 'Private Customer',
          originalAmount: 400,
          outstandingAmount: 320,
          dueDate: null,
          status: 'OPEN',
          createdAt: null,
          payments: const [],
        ),
      ],
    );
    final source = _SnapshotSource(rawSnapshot);
    final controller = FinanceHubController(
      source: source,
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      canViewCustomerDetails: false,
    );
    addTearDown(controller.dispose);

    void expectRedacted(FinanceSnapshot snapshot) {
      final receivable = snapshot.retailReceivables.single;
      expect(receivable.customerName, isNull);
      expect(receivable.customerId, isNull);
      expect(receivable.id, isNot(contains('customer-1')));
      expect(receivable.saleId, isNot('sale-1'));
      expect(snapshot.toJson().toString(), isNot(contains('customer-1')));
      expect(snapshot.toJson().toString(), isNot(contains('Private Customer')));
      expect(receivable.outstandingAmount, 320);
    }

    expectRedacted(controller.state.snapshot!);
    await controller.refresh();
    expectRedacted(controller.state.snapshot!);

    final visibleReference =
        controller.state.snapshot!.retailReceivables.single.id;
    await controller.recordRetailCollection(ReceivableCollectionRequest(
      receivableId: visibleReference,
      branchId: 'branch-1',
      amount: 10,
      method: 'CASH',
    ));
    expect(source.collectionRequest?.receivableId, 'receivable-1');
  });
}

class _SnapshotSource implements FinanceHubDataSource {
  _SnapshotSource(this.snapshot);

  final FinanceSnapshot snapshot;
  ReceivableCollectionRequest? collectionRequest;

  @override
  FinanceSnapshot? loadCachedSnapshot(String tenantId, String branchId) =>
      snapshot;

  @override
  Future<FinanceSnapshot> refresh(String branchId) async => snapshot;

  @override
  Future<void> recordRetailCollection(
      ReceivableCollectionRequest request) async {
    collectionRequest = request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FinanceDatabase extends AppDatabase {
  _FinanceDatabase()
      : super.forTesting(NativeDatabase.memory(), StorageService());

  List<Map<String, dynamic>>? lastAllocations;

  @override
  Future<void> recordLocalCustomerCollections({
    required String branchId,
    required List<Map<String, dynamic>> allocations,
    required String requestId,
    String? reference,
    String paymentMethod = 'CASH',
  }) async {
    lastAllocations = allocations;
  }

  @override
  Future<List<Map<String, dynamic>>> getLocalFinanceSupplierInvoices() async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>>
      getLocalFinanceCustomerReceivables() async => const [
            {
              'id': 'customer-1',
              'name': 'Private Customer',
              'balance': 320,
              'originalAmount': 400,
              'dueDate': null,
              'createdAt': null,
              'payments': <Map<String, dynamic>>[],
            },
          ];
}

class _LocalFinanceAuth implements AuthService {
  @override
  bool get isLocalWorkspace => true;

  @override
  String? get tenantId => 'tenant-1';

  @override
  String? get branchId => 'branch-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
