import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/sales/domain/recorded_payment.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseMpesaMessage', () {
    const message =
        'SKL4X9Q2TB Confirmed. Ksh4,200.00 received from WANJIKU K 0712 ••• 678 on 4/11/26 at 11:19 AM. New balance is Ksh12,345.00.';

    test('reads the code, amount and time', () {
      final parsed = parseMpesaMessage(message);
      expect(parsed.code, 'SKL4X9Q2TB');
      expect(parsed.amount, 4200);
      expect(parsed.receivedAt, DateTime(2026, 11, 4, 11, 19));
    });

    test('takes the first amount, not the balance', () {
      expect(parseMpesaMessage(message).amount, isNot(12345));
    });

    test('reads a PM time and a four digit year', () {
      final parsed = parseMpesaMessage(
        'RBC7Y2KLM9 Confirmed. Ksh 650.50 received on 15/1/2026 at 2:05 PM.',
      );
      expect(parsed.code, 'RBC7Y2KLM9');
      expect(parsed.amount, 650.5);
      expect(parsed.receivedAt, DateTime(2026, 1, 15, 14, 5));
    });

    test('does not mistake a long word for a code', () {
      final parsed = parseMpesaMessage('CONFIRMED payment of Ksh100 received');
      expect(parsed.code, isNull);
      expect(parsed.amount, 100);
    });

    test('an empty or unrelated message gives nothing', () {
      expect(parseMpesaMessage('').isEmpty, isTrue);
      expect(parseMpesaMessage('hello there').isEmpty, isTrue);
    });
  });

  group('code formats', () {
    test('an M-Pesa code is ten upper-case letters and digits', () {
      expect(looksLikeMpesaCode('SKL4X9Q2TB'), isTrue);
      expect(looksLikeMpesaCode('skl4x9q2tb'), isTrue);
      expect(looksLikeMpesaCode('SKL4X9Q2T'), isFalse);
      expect(looksLikeMpesaCode('1KL4X9Q2TB'), isFalse);
      expect(looksLikeMpesaCode('SKL4X9Q2TB1'), isFalse);
    });

    test('a bank reference is six to thirty letters, digits and separators',
        () {
      expect(looksLikeBankReference('FT26308X1'), isTrue);
      expect(looksLikeBankReference('ABC-123/45'), isTrue);
      expect(looksLikeBankReference('123'), isFalse);
      expect(looksLikeBankReference('has space 123'), isFalse);
    });
  });

  group('RecordedPaymentRules', () {
    test('defaults are the safe ones', () {
      const rules = RecordedPaymentRules();
      expect(rules.enabled, isTrue);
      expect(rules.approvalLimit, 5000);
      expect(rules.requireMessage, isTrue);
    });

    test('approval is needed above the limit, never at or below it', () {
      const rules = RecordedPaymentRules(approvalLimit: 5000);
      expect(rules.needsApproval(5000), isFalse);
      expect(rules.needsApproval(5000.5), isTrue);
      expect(rules.needsApproval(100), isFalse);
    });

    test('a limit of zero needs approval every time', () {
      const rules = RecordedPaymentRules(approvalLimit: 0);
      expect(rules.needsApproval(1), isTrue);
    });

    test('rules survive a save and load, and a damaged value falls back', () {
      const rules = RecordedPaymentRules(
        enabled: false,
        approvalLimit: 8000,
        requireMessage: false,
        tillNumber: '5 123 456',
      );
      final restored = RecordedPaymentRules.fromJson(rules.toJson());
      expect(restored.enabled, isFalse);
      expect(restored.approvalLimit, 8000);
      expect(restored.requireMessage, isFalse);
      expect(restored.tillNumber, '5 123 456');

      final damaged = RecordedPaymentRules.fromJson({'approvalLimit': 'lots'});
      expect(damaged.approvalLimit, 5000);
      expect(RecordedPaymentRules.fromJson(null).enabled, isTrue);
    });
  });

  group('RecordedPaymentDetails', () {
    test('saves who recorded and approved, and reads back', () {
      final details = RecordedPaymentDetails(
        method: RecordedPaymentMethod.mpesa,
        code: 'skl4x9q2tb',
        amount: 4200,
        recordedById: 'u1',
        recordedByName: 'Brian',
        approvedById: 'u2',
        approvedByName: 'Wanjiru',
        message: ' SKL4X9Q2TB Confirmed. ',
        recordedAt: DateTime.utc(2026, 11, 4, 8, 19),
      );
      final restored = RecordedPaymentDetails.tryParse(details.toReference());

      expect(restored, isNotNull);
      expect(restored!.code, 'SKL4X9Q2TB');
      expect(restored.amount, 4200);
      expect(restored.recordedByName, 'Brian');
      expect(restored.approvedByName, 'Wanjiru');
      expect(restored.message, 'SKL4X9Q2TB Confirmed.');
    });

    test('a cash or split reference is not a recorded payment', () {
      expect(RecordedPaymentDetails.tryParse(null), isNull);
      expect(RecordedPaymentDetails.tryParse(''), isNull);
      expect(RecordedPaymentDetails.tryParse('not json'), isNull);
      expect(
        RecordedPaymentDetails.tryParse('[{"method":"CASH","amount":10}]'),
        isNull,
      );
    });

    test('labels never read as verified', () {
      expect(RecordedPaymentMethod.label(RecordedPaymentMethod.mpesa),
          'M-Pesa (recorded)');
      expect(RecordedPaymentMethod.label(RecordedPaymentMethod.bank),
          'Bank transfer (recorded)');
      expect(RecordedPaymentMethod.isRecorded('MPESA'), isFalse);
      expect(RecordedPaymentMethod.isRecorded('mpesa_recorded'), isTrue);
    });
  });

  group('one code, one sale', () {
    late AppDatabase database;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.initialize();
      await storage.saveTenantId('tenant-1');
      await storage.saveBranchId('branch-1');
      database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    });

    tearDown(() => database.close());

    Future<void> recordSale(String id, String method, String code) async {
      final details = RecordedPaymentDetails(
        method: method,
        code: code,
        amount: 100,
        recordedById: 'u1',
        recordedByName: 'Brian',
      );
      await database.into(database.pendingSales).insert(
            PendingSalesCompanion.insert(
              id: id,
              receiptNumber: 'RCP-$id',
              subtotal: 100,
              total: 100,
              paymentMethod: method,
              paymentReference: Value(details.toReference()),
              cashierId: 'u1',
              branchId: 'branch-1',
              createdAt: DateTime.now(),
            ),
          );
    }

    Future<bool> used(String code) => database.hasPendingSaleReferenceLike(
          recordedCodeSearchPattern(code),
          methods: const [
            RecordedPaymentMethod.mpesa,
            RecordedPaymentMethod.bank,
          ],
        );

    test('a code that was recorded is found, in any letter case', () async {
      await recordSale('s1', RecordedPaymentMethod.mpesa, 'SKL4X9Q2TB');

      expect(await used('SKL4X9Q2TB'), isTrue);
      expect(await used('skl4x9q2tb'), isTrue);
    });

    test('a different code is free', () async {
      await recordSale('s1', RecordedPaymentMethod.mpesa, 'SKL4X9Q2TB');

      expect(await used('SKM2P7R4DA'), isFalse);
    });

    test('a bank reference counts too', () async {
      await recordSale('s1', RecordedPaymentMethod.bank, 'FT26308X1');

      expect(await used('FT26308X1'), isTrue);
    });

    test('a cash sale never blocks a code', () async {
      await database.into(database.pendingSales).insert(
            PendingSalesCompanion.insert(
              id: 'cash1',
              receiptNumber: 'RCP-cash1',
              subtotal: 100,
              total: 100,
              paymentMethod: 'CASH',
              cashierId: 'u1',
              branchId: 'branch-1',
              createdAt: DateTime.now(),
            ),
          );

      expect(await used('SKL4X9Q2TB'), isFalse);
    });
  });
}
