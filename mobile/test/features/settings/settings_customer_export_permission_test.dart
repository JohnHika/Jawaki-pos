import 'dart:io';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/settings/presentation/screens/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'data.export keeps sales, stock and product exports but hides customer accounts without customers.view',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        initialPermissions: const ['data.export'],
        initialPane: 'export',
      );
      addTearDown(() => harness.dispose(tester));

      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Stock levels'), findsOneWidget);
      expect(find.text('Product list'), findsOneWidget);
      expect(find.text('Customer accounts'), findsNothing);
    },
  );

  testWidgets(
    'customer export loads accounts when customers.view is granted',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        initialPermissions: const ['data.export', 'customers.view'],
        initialPane: 'export',
      );
      addTearDown(() => harness.dispose(tester));

      await tester.tap(find.text('Customer accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV spreadsheet'));
      await tester.pumpAndSettle();

      expect(harness.database.allCustomerCalls, 1);
    },
  );

  testWidgets(
    'customer export rechecks customers.view before loading after the permission is revoked',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        initialPermissions: const ['data.export', 'customers.view'],
        initialPane: 'export',
      );
      addTearDown(() => harness.dispose(tester));

      expect(find.text('Customer accounts'), findsOneWidget);
      await tester.tap(find.text('Customer accounts'));
      await tester.pumpAndSettle();
      expect(find.text('CSV spreadsheet'), findsOneWidget);

      harness.permissions.state = RolePermissions(const ['data.export']);
      await tester.pump();
      await tester.tap(find.text('CSV spreadsheet'));
      await tester.pumpAndSettle();

      expect(harness.database.allCustomerCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customer export does not query or share if data.export is revoked while format selection is open',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        initialPermissions: const ['data.export', 'customers.view'],
        initialPane: 'export',
      );
      var shareCalls = 0;
      const documentsChannel =
          MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final documentsPath = Directory.current.path;
      final filesBefore = Directory.current
          .listSync()
          .where((file) => file.uri.pathSegments.last.startsWith(
                'customer_accounts_export_',
              ))
          .map((file) => file.path)
          .toSet();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        documentsChannel,
        (call) async => documentsPath,
      );
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shareCalls++;
        return 'success';
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(documentsChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        for (final file in Directory.current.listSync()) {
          if (file.uri.pathSegments.last.startsWith(
                'customer_accounts_export_',
              ) &&
              !filesBefore.contains(file.path)) {
            await file.delete();
          }
        }
        await harness.dispose(tester);
      });

      await tester.tap(find.text('Customer accounts'));
      await tester.pumpAndSettle();
      expect(find.text('CSV spreadsheet'), findsOneWidget);

      harness.permissions.state = RolePermissions(const ['customers.view']);
      await tester.pump();
      await tester.tap(find.text('CSV spreadsheet'));
      await tester.pumpAndSettle();

      expect(harness.database.allCustomerCalls, 0);
      expect(shareCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester, {
  required List<String> initialPermissions,
  required String initialPane,
}) async {
  final database = _SettingsDatabase();
  final auth = _SettingsAuth();
  final connectivity = _SettingsConnectivity();
  final permissions = _MutablePermissions(RolePermissions(initialPermissions));
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;

  getIt.pushNewScope();
  getIt.registerSingleton<AuthService>(auth);
  getIt.registerSingleton<ConnectivityService>(connectivity);
  getIt.registerSingleton<StorageService>(StorageService());
  getIt.registerSingleton<AppDatabase>(database);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(const {
        'name': 'Cashier',
        'role': 'CASHIER',
        'tenantName': 'Test Shop',
        'permissions': ['data.export'],
      }),
      permissionsProvider
          .overrideWith((ref) => ref.watch(_mutablePermissionsProvider)),
      _mutablePermissionsProvider.overrideWith((ref) => permissions),
      isOnlineProvider.overrideWithValue(true),
      businessLayoutProvider
          .overrideWith((ref) => businessLayoutFromUser(null)),
    ],
    child: MaterialApp(home: SettingsScreen(openEntry: initialPane)),
  ));
  await tester.pumpAndSettle();
  return _SettingsHarness(
    database: database,
    permissions: permissions,
  );
}

final _mutablePermissionsProvider =
    StateNotifierProvider<_MutablePermissions, RolePermissions>(
  (ref) => _MutablePermissions(RolePermissions(const [])),
);

class _MutablePermissions extends StateNotifier<RolePermissions> {
  _MutablePermissions(super.state);
}

class _SettingsHarness {
  const _SettingsHarness({required this.database, required this.permissions});

  final _SettingsDatabase database;
  final _MutablePermissions permissions;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
    await getIt.popScope();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

class _SettingsDatabase extends AppDatabase {
  _SettingsDatabase()
      : super.forTesting(NativeDatabase.memory(), StorageService());

  var allCustomerCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    allCustomerCalls++;
    return const [
      {
        'id': 'customer-1',
        'name': 'Private Customer',
        'phone': '0712345678',
      },
    ];
  }
}

class _SettingsAuth implements AuthService {
  @override
  bool get isAuthenticated => true;

  @override
  bool get isLocked => false;

  @override
  bool get isLocalWorkspace => true;

  @override
  bool get isLocalWorkspaceOwner => false;

  @override
  double get taxRatePercent => 0;

  @override
  bool get showTaxOnReceipt => false;

  @override
  Map<String, dynamic>? get currentUser => const {
        'name': 'Cashier',
        'role': 'CASHIER',
        'tenantName': 'Test Shop',
        'permissions': ['data.export'],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsConnectivity implements ConnectivityService {
  @override
  bool get isOnline => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
