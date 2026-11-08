import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubStorage extends StorageService {
  _StubStorage() : super();

  @override
  Future<void> initialize() async {}
}

/// Answers the two reads the screen makes and keeps added expenses in memory.
class _FakeDatabase extends AppDatabase {
  _FakeDatabase() : super(_StubStorage());

  final expenses = <Map<String, dynamic>>[];
  var _salesReads = 0;

  /// The first read is the opening "Today" view; later reads come from a
  /// reload. Told apart by order, not by the range: on a Monday "This week"
  /// and "Today" cover the same day.
  @override
  Future<({double total, int count})> getLocalCompletedSalesTotal({
    required String branchId,
    required DateTime from,
    required DateTime to,
  }) async {
    return _salesReads++ == 0
        ? (total: 400.0, count: 2)
        : (total: 2600.0, count: 9);
  }

  @override
  Future<List<Map<String, dynamic>>> getLocalExpenses({
    required String branchId,
    required DateTime from,
    required DateTime to,
  }) async =>
      List.of(expenses);

  @override
  Future<String> addLocalExpense({
    required String branchId,
    required double amount,
    required String category,
    required String paymentMethod,
    required String recordedBy,
    String? note,
    DateTime? spentAt,
  }) async {
    expenses.add({
      'id': 'e${expenses.length + 1}',
      'amount': amount,
      'category': category,
      'note': note,
      'paymentMethod': paymentMethod,
      'spentAt': DateTime.now(),
      'recordedBy': recordedBy,
    });
    return 'e${expenses.length}';
  }
}

class _StubAuth extends AuthService {
  _StubAuth(AppDatabase database)
      : super(
          storage: _StubStorage(),
          apiClient: ApiClient(Dio()),
          database: database,
        );

  @override
  String? get branchId => 'branch-1';

  @override
  Map<String, dynamic>? get currentUser => const {'name': 'Wanjiru'};
}

void main() {
  late _FakeDatabase database;

  setUp(() {
    getIt.pushNewScope();
    database = _FakeDatabase();
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(_StubAuth(database));
  });

  tearDown(() async {
    await getIt.popScope();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(
          RolePermissions(const <String>['expenses.view']),
        ),
      ],
      child: const MaterialApp(home: ExpensesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('switching the period reloads the totals', (tester) async {
    await pumpScreen(tester);
    expect(find.text('LEFT FROM SALES, TODAY'), findsOneWidget);
    expect(find.text('Sales (2)'), findsOneWidget);

    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();

    expect(find.text('LEFT FROM SALES, THIS WEEK'), findsOneWidget);
    expect(find.text('Sales (9)'), findsOneWidget);
  });

  testWidgets('a saved expense shows straight away', (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('Nothing recorded today'), findsOneWidget);

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Transport'));
    await tester.pump();
    final save = find.text('Save expense');
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(database.expenses, hasLength(1));
    expect(find.textContaining('Nothing recorded today'), findsNothing);
    expect(find.text('Transport'), findsWidgets);
  });
}
