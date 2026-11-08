import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
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
    Future<void> bill(String id, String supplier, double total) async {
      await database.recordSupplierInvoice(
        invoiceId: id,
        branchId: 'branch-1',
        supplierName: supplier,
        invoiceNumber: id.toUpperCase(),
        terms: 'credit',
        paidAmount: 0,
        items: [
          {'name': '', 'lineTotal': total},
        ],
      );
      // Supplier ids come from the clock; keep them apart.
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }

    await bill('inv-m1', 'Mwalimu Wholesalers', 12000);
    await bill('inv-m2', 'Mwalimu Wholesalers', 3000);
    await bill('inv-k1', 'Kamau Distributors', 8000);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Map<String, Map<String, dynamic>>> bills() async => {
        for (final row in await database.getLocalFinanceSupplierInvoices())
          row['id'] as String: row,
      };

  test('pays bills from several suppliers in one go', () async {
    await database.recordLocalSupplierPaymentsBatch(
      payments: [
        (invoiceId: 'inv-m1', amount: 12000),
        (invoiceId: 'inv-m2', amount: 1000),
        (invoiceId: 'inv-k1', amount: 8000),
      ],
      branchId: 'branch-1',
      fundingSource: 'BANK_OR_MPESA',
      requestId: 'batch-1',
      notes: 'QK12AB34CD',
    );

    final after = await bills();
    expect(after['inv-m1']!['outstandingAmount'], 0);
    expect(after['inv-m1']!['status'], 'paid');
    expect(after['inv-m2']!['outstandingAmount'], 2000);
    expect(after['inv-m2']!['status'], 'partial');
    expect(after['inv-k1']!['outstandingAmount'], 0);
    final payment = (after['inv-k1']!['payments'] as List).single as Map;
    expect(payment['amount'], 8000);
    expect(payment['fundingSource'], 'BANK_OR_MPESA');
    expect(payment['notes'], 'QK12AB34CD');
  });

  test('pays nothing when one bill is wrong', () async {
    await expectLater(
      database.recordLocalSupplierPaymentsBatch(
        payments: [
          (invoiceId: 'inv-m1', amount: 12000),
          (invoiceId: 'inv-k1', amount: 9000),
        ],
        branchId: 'branch-1',
        fundingSource: 'CASH_TILL',
        requestId: 'batch-2',
      ),
      throwsStateError,
    );

    final after = await bills();
    expect(after['inv-m1']!['outstandingAmount'], 12000);
    expect(after['inv-k1']!['outstandingAmount'], 8000);
  });

  test('a repeated tap does not pay twice', () async {
    Future<void> pay() => database.recordLocalSupplierPaymentsBatch(
          payments: [
            (invoiceId: 'inv-m2', amount: 1500),
            (invoiceId: 'inv-k1', amount: 2000),
          ],
          branchId: 'branch-1',
          fundingSource: 'CASH_TILL',
          requestId: 'batch-3',
        );

    await pay();
    await pay();

    final after = await bills();
    expect(after['inv-m2']!['outstandingAmount'], 1500);
    expect(after['inv-k1']!['outstandingAmount'], 6000);
  });

  test('refuses an empty list and the same bill twice', () async {
    expect(
      () => database.recordLocalSupplierPaymentsBatch(
        payments: const [],
        branchId: 'branch-1',
        fundingSource: 'CASH_TILL',
        requestId: 'batch-4',
      ),
      throwsArgumentError,
    );
    expect(
      () => database.recordLocalSupplierPaymentsBatch(
        payments: [
          (invoiceId: 'inv-m1', amount: 100),
          (invoiceId: 'inv-m1', amount: 200),
        ],
        branchId: 'branch-1',
        fundingSource: 'CASH_TILL',
        requestId: 'batch-5',
      ),
      throwsArgumentError,
    );
  });

  test('a single bill payment still works as before', () async {
    await database.recordLocalSupplierInvoicePayment(
      invoiceId: 'inv-m2',
      branchId: 'branch-1',
      amount: 3000,
      fundingSource: 'CASH_TILL',
      requestId: 'single-1',
    );

    expect((await bills())['inv-m2']!['status'], 'paid');
  });
}
