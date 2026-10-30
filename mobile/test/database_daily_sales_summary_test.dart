import 'dart:convert';

import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> addSale({
    required String id,
    required double total,
    required String method,
    String? paymentReference,
    String branchId = 'branch-1',
    String status = 'COMPLETED',
  }) async {
    await database.into(database.pendingSales).insert(
          PendingSalesCompanion.insert(
            id: id,
            receiptNumber: 'RCP-$id',
            subtotal: total,
            total: total,
            paymentMethod: method,
            paymentReference: Value(paymentReference),
            cashierId: 'cashier-1',
            branchId: branchId,
            status: Value(status),
            createdAt: DateTime(2026, 10, 26, 10),
          ),
        );
  }

  test('offline End of Day attributes split cash and credit tenders', () async {
    await addSale(id: 'cash', total: 80, method: 'CASH');
    await addSale(id: 'credit', total: 45, method: 'CREDIT');
    await addSale(id: 'mpesa', total: 30, method: 'MPESA');
    await addSale(id: 'card', total: 20, method: 'PESAPAL');
    await addSale(
      id: 'split',
      total: 100,
      method: 'SPLIT',
      paymentReference: jsonEncode([
        {'method': 'CASH', 'amount': 60},
        {'method': 'CREDIT', 'amount': 40},
      ]),
    );
    await addSale(
      id: 'other-branch',
      total: 1000,
      method: 'CASH',
      branchId: 'branch-2',
    );

    final summary = await database.getDailySalesSummary(
      'branch-1',
      DateTime(2026, 10, 26),
    );

    expect(summary['totalSales'], 275.0);
    expect(summary['totalTransactions'], 5);
    expect(summary['cashSales'], 140.0);
    expect(summary['creditSales'], 85.0);
    expect(summary['mpesaSales'], 30.0);
    expect(summary['cardSales'], 20.0);
  });

  test('reports an unbalanced split as unreconciled, not cash or credit',
      () async {
    await addSale(
      id: 'bad-split',
      total: 100,
      method: 'SPLIT',
      paymentReference: jsonEncode([
        {'method': 'CASH', 'amount': 60},
        {'method': 'CREDIT', 'amount': 35},
      ]),
    );

    // a8bef26: a split that does not balance no longer fails the whole End
    // of Day report — it is surfaced as unreconciled and folded into neither
    // cash nor credit, so the till is never quietly overstated.
    final summary = await database.getDailySalesSummary(
      'branch-1',
      DateTime(2026, 10, 26),
    );

    expect(summary['totalSales'], 100.0);
    expect(summary['cashSales'], 0.0);
    expect(summary['creditSales'], 0.0);
    expect(summary['otherSales'], 100.0);
    final otherMethods = summary['otherPaymentMethods'] as List<dynamic>;
    expect(
      otherMethods.whereType<Map>().any((m) =>
          m['method'] == 'SPLIT (UNRECONCILED)' && m['amount'] == 100.0),
      isTrue,
    );
  });
}
