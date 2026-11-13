import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/accountability/data/till_guard_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'credit review keeps the limit block but hides customer standing without customers.view',
    (tester) async {
      getIt.pushNewScope();
      final database = _CustomerDatabase();
      getIt.registerSingleton<AppDatabase>(database);
      getIt.registerSingleton<AuthService>(_CashierWithoutCustomerView());
      addTearDown(() async {
        await database.close();
        await getIt.popScope();
      });

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => TillGuardService.instance.review(
                context,
                lines: const [],
                creditAmount: 100,
                customerId: 'customer-1',
                customerName: 'Private Customer',
              ),
              child: const Text('Review credit sale'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Review credit sale'));
      await tester.pumpAndSettle();

      expect(find.text('Sale blocked by policy'), findsOneWidget);
      expect(
        find.text('This sale does not meet the account’s credit policy.'),
        findsOneWidget,
      );
      expect(find.textContaining('Private Customer'), findsNothing);
      expect(find.textContaining('KES 550'), findsNothing);
      expect(find.textContaining('KES 500'), findsNothing);
      expect(find.text('Sell anyway'), findsNothing);
      expect(find.text('Change the sale'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Change the sale'));
      await tester.pumpAndSettle();
    },
  );
}

class _CustomerDatabase extends AppDatabase {
  _CustomerDatabase()
      : super.forTesting(NativeDatabase.memory(), StorageService());

  @override
  Future<Map<String, dynamic>?> getCustomer(String id) async => {
        'id': id,
        'name': 'Private Customer',
        'balance': 450.0,
        'creditLimit': 500.0,
      };
}

class _CashierWithoutCustomerView implements AuthService {
  @override
  bool get isLocalWorkspace => true;

  @override
  Map<String, dynamic>? get currentUser => const {
        'permissions': ['sales.create'],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
