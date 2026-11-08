import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/expenses/domain/expenses.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final businessDate =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

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

  Future<void> addCashSale(String id, double total, {double? cashGiven}) {
    return database.createPendingSale(
      PendingSalesCompanion.insert(
        id: id,
        receiptNumber: 'RCP-$id',
        subtotal: total,
        total: total,
        paymentMethod: 'CASH',
        cashierId: 'cashier-1',
        branchId: 'branch-1',
        status: const Value('COMPLETED'),
        createdAt: today.add(const Duration(hours: 9)),
      ),
      const [],
      cashGiven: cashGiven,
    );
  }

  group('cash given and change', () {
    test('are saved with a cash sale and read back for the receipt',
        () async {
      await addCashSale('s1', 280, cashGiven: 500);

      final tender = await database.getSaleCashTender('s1');

      expect(tender, {'cashGiven': 500.0, 'change': 220.0});
    });

    test('are not saved when the cash did not cover the sale', () async {
      await addCashSale('s2', 280, cashGiven: 200);
      await addCashSale('s3', 280);

      expect(await database.getSaleCashTender('s2'), isNull);
      expect(await database.getSaleCashTender('s3'), isNull);
    });
  });

  group('expenses', () {
    test('are listed newest first and summed into the day', () async {
      await database.addLocalExpense(
        branchId: 'branch-1',
        amount: 300,
        category: 'Transport',
        paymentMethod: 'CASH',
        recordedBy: 'Owner',
        note: 'Boda to the wholesaler',
        spentAt: today.add(const Duration(hours: 10)),
      );
      await database.addLocalExpense(
        branchId: 'branch-1',
        amount: 1000,
        category: 'Rent',
        paymentMethod: 'MPESA',
        recordedBy: 'Owner',
        spentAt: today.add(const Duration(hours: 11)),
      );

      final list = await database.getLocalExpenses(
        branchId: 'branch-1',
        from: today,
        to: today.add(const Duration(days: 1)),
      );
      expect(list.map((e) => e['category']), ['Rent', 'Transport']);
      expect(list.last['note'], 'Boda to the wholesaler');

      final summary = await database.getDailySalesSummary('branch-1', today);
      expect(summary['expenses'], 1300.0);
      expect(summary['cashExpenses'], 300.0);
    });

    test('a removed expense stops counting', () async {
      final id = await database.addLocalExpense(
        branchId: 'branch-1',
        amount: 300,
        category: 'Transport',
        paymentMethod: 'CASH',
        recordedBy: 'Owner',
      );

      await database.removeLocalExpense(id: id, removedBy: 'Owner');

      final list = await database.getLocalExpenses(
        branchId: 'branch-1',
        from: today,
        to: today.add(const Duration(days: 1)),
      );
      expect(list, isEmpty);
      final summary = await database.getDailySalesSummary('branch-1', today);
      expect(summary['cashExpenses'], 0.0);
    });

    test('refuses a zero amount or an unknown way of paying', () async {
      expect(
        () => database.addLocalExpense(
          branchId: 'branch-1',
          amount: 0,
          category: 'Rent',
          paymentMethod: 'CASH',
          recordedBy: 'Owner',
        ),
        throwsArgumentError,
      );
      expect(
        () => database.addLocalExpense(
          branchId: 'branch-1',
          amount: 50,
          category: 'Rent',
          paymentMethod: 'CHEQUE',
          recordedBy: 'Owner',
        ),
        throwsArgumentError,
      );
    });

    test('cash expenses come off the cash expected at the till close',
        () async {
      await addCashSale('s1', 1000);
      await database.addLocalExpense(
        branchId: 'branch-1',
        amount: 300,
        category: 'Transport',
        paymentMethod: 'CASH',
        recordedBy: 'Owner',
      );

      await database.saveLocalDailyClose(
        branchId: 'branch-1',
        businessDate: businessDate,
        openingFloat: 500,
        cashSales: 1000,
        cashCollections: 0,
        cashPayouts: 0,
        cashRefunds: 0,
        cashExpenses: 300,
        voidedCashReceived: 0,
        netCashMovement: 0,
        countedCash: 1200,
        closedBy: 'Owner',
      );

      final close = await database.getLatestLocalDailyClose(
        branchId: 'branch-1',
        businessDate: businessDate,
      );
      expect(close!['expectedCash'], 1200.0);
      expect(close['discrepancy'] ?? close['cashDiscrepancy'], 0.0);
      expect(close['cashExpenses'], 300.0);
      final history =
          await database.getLocalDailyCloseHistory(branchId: 'branch-1');
      expect(history.single['cashExpenses'], 300.0);
    });

    test('a close that leaves out a cash expense is refused', () async {
      await addCashSale('s1', 1000);
      await database.addLocalExpense(
        branchId: 'branch-1',
        amount: 300,
        category: 'Transport',
        paymentMethod: 'CASH',
        recordedBy: 'Owner',
      );

      expect(
        () => database.saveLocalDailyClose(
          branchId: 'branch-1',
          businessDate: businessDate,
          openingFloat: 500,
          cashSales: 1000,
          cashCollections: 0,
          cashPayouts: 0,
          cashRefunds: 0,
          voidedCashReceived: 0,
          netCashMovement: 0,
          countedCash: 1500,
          closedBy: 'Owner',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('sales total for a period counts completed sales only', () async {
      await addCashSale('s1', 1000);
      await addCashSale('s2', 250);
      await database.into(database.pendingSales).insert(
            PendingSalesCompanion.insert(
              id: 'void',
              receiptNumber: 'RCP-void',
              subtotal: 99,
              total: 99,
              paymentMethod: 'CASH',
              cashierId: 'cashier-1',
              branchId: 'branch-1',
              status: const Value('VOIDED'),
              createdAt: today.add(const Duration(hours: 9)),
            ),
          );

      final sales = await database.getLocalCompletedSalesTotal(
        branchId: 'branch-1',
        from: today,
        to: today.add(const Duration(days: 1)),
      );

      expect(sales.total, 1250.0);
      expect(sales.count, 2);
    });
  });

  group('debt payments', () {
    Future<void> addCustomerOwing(double balance) async {
      await database.createCustomersTable();
      await database.customStatement(
        'INSERT INTO customers (id, tenant_id, name, created_at, balance) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          'c1',
          'tenant-1',
          'Mama Njeri',
          DateTime.now().toUtc().toIso8601String(),
          balance,
        ],
      );
    }

    test('an M-Pesa debt payment lowers the debt but not the till cash',
        () async {
      await addCustomerOwing(1000);

      await database.recordLocalCustomerCollections(
        branchId: 'branch-1',
        allocations: [
          {'receivableId': 'local-customer:c1', 'amount': 600},
        ],
        requestId: 'r1',
        reference: 'SKL4X9Q2TB',
        paymentMethod: 'MPESA_RECORDED',
      );

      final customer = await database.getCustomer('c1');
      expect(customer!['balance'], 400.0);
      final summary = await database.getDailySalesSummary('branch-1', today);
      expect(summary['cashCollections'], 0.0);
      final payments = await database.getRecentCustomerCollections('c1');
      expect(payments.single['paymentMethod'], 'MPESA_RECORDED');
    });

    test('an M-Pesa debt payment needs its code', () async {
      await addCustomerOwing(1000);

      expect(
        () => database.recordLocalCustomerCollections(
          branchId: 'branch-1',
          allocations: [
            {'receivableId': 'local-customer:c1', 'amount': 600},
          ],
          requestId: 'r2',
          paymentMethod: 'MPESA_RECORDED',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('expense maths', () {
    test('sets expenses against sales, biggest category first', () {
      final summary = ExpenseSummary.from(sales: 5000, expenses: [
        {'amount': 300.0, 'category': 'Transport'},
        {'amount': 1000.0, 'category': 'Rent'},
        {'amount': 0.1, 'category': 'Transport'},
        {'amount': 0.2, 'category': 'Transport'},
      ]);

      expect(summary.expenses, 1300.3);
      expect(summary.left, 3699.7);
      expect(summary.byCategory.first.category, 'Rent');
      expect(summary.byCategory.last.amount, 300.3);
      expect(summary.spentShare, closeTo(0.26, 0.001));
    });

    test('no sales gives no share, and spending more shows a loss', () {
      final summary = ExpenseSummary.from(sales: 0, expenses: [
        {'amount': 200.0, 'category': 'Rent'},
      ]);

      expect(summary.spentShare, isNull);
      expect(summary.left, -200.0);
    });

    test('a week starts on Monday and a month on the 1st', () {
      // Thursday 12 November 2026.
      final thursday = DateTime(2026, 11, 12, 15, 30);

      final week = expensePeriodRange(ExpensePeriod.week, thursday);
      final month = expensePeriodRange(ExpensePeriod.month, thursday);
      final day = expensePeriodRange(ExpensePeriod.today, thursday);

      expect(week.from, DateTime(2026, 11, 9));
      expect(month.from, DateTime(2026, 11, 1));
      expect(day.from, DateTime(2026, 11, 12));
      expect(day.to, DateTime(2026, 11, 13));
      expect(week.to, day.to);
    });
  });
}
