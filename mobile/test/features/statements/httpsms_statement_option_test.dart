import 'dart:convert';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/desktop/adaptive_overlays.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/httpsms_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/statements/presentation/widgets/send_statement_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;

import '../../support/shot.dart';

class _LocalAuthService implements AuthService {
  @override
  bool get isLocalWorkspace => true;

  @override
  bool get isLocalWorkspaceOwner => true;

  @override
  Map<String, dynamic>? get currentUser => {
        'authMode': 'local',
        'companyName': 'Njeri Shop',
        'branchName': 'Main',
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConnectedAuthService implements AuthService {
  @override
  bool get isLocalWorkspace => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConfiguredSmsStorage extends StorageService {
  @override
  Future<String?> getHttpsmsApiKey() async => 'test-account-key';

  @override
  Future<String?> getHttpsmsSenderNumber() async => '+254711222333';
}

class _StatementDatabase extends AppDatabase {
  _StatementDatabase()
      : super.forTesting(NativeDatabase.memory(), StorageService());

  var customerCalls = 0;
  var installmentCalls = 0;
  var salesCalls = 0;
  var collectionCalls = 0;

  @override
  Future<Map<String, dynamic>?> getCustomer(String id) async {
    customerCalls++;
    return {'id': id, 'balance': 42.5};
  }

  @override
  Future<List<Map<String, dynamic>>> getCustomerInstallments(
    String customerId,
  ) async {
    installmentCalls++;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentCustomerSales(
    String customerId, {
    int limit = 8,
  }) async {
    salesCalls++;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentCustomerCollections(
    String customerId, {
    int limit = 8,
  }) async {
    collectionCalls++;
    return const [];
  }
}

class _MutableStatementPermissions extends StateNotifier<RolePermissions> {
  _MutableStatementPermissions(super.state);
}

final _mutableStatementPermissionsProvider =
    StateNotifierProvider<_MutableStatementPermissions, RolePermissions>(
  (ref) => _MutableStatementPermissions(RolePermissions(const [])),
);

void main() {
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthService>(_LocalAuthService());
    DesktopLayout.debugIsDesktopPlatform = false;
  });

  tearDown(() async {
    DesktopLayout.debugIsDesktopPlatform = null;
    await getIt.reset();
  });

  testWidgets('local statement choices offer HTTPSMS delivery', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(['statements.share', 'customers.view']),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              customerId: 'customer-1',
              name: 'Njeri Stores',
              phone: '0712 000 111',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();

    expect(find.text('Send by SMS via HTTPSMS'), findsOneWidget);
  });

  testWidgets(
      'customer statement does not query local data when customers.view is revoked before format selection',
      (tester) async {
    final database = _StatementDatabase();
    addTearDown(database.close);
    getIt.registerSingleton<AppDatabase>(database);
    final permissions = _MutableStatementPermissions(
      RolePermissions(const ['statements.share', 'customers.view']),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWith(
            (ref) => ref.watch(_mutableStatementPermissionsProvider),
          ),
          _mutableStatementPermissionsProvider
              .overrideWith((ref) => permissions),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              customerId: 'customer-1',
              name: 'Njeri Stores',
              phone: '0712 000 111',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();

    permissions.state = RolePermissions(const ['statements.share']);
    await tester.pump();
    await tester.tap(find.text('Short message'));
    await tester.pumpAndSettle();

    expect(database.customerCalls, 0);
    expect(database.installmentCalls, 0);
    expect(database.salesCalls, 0);
    expect(database.collectionCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'customers.view gates customer statements but not shop-ledger statements',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(const ['statements.share']),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              customerId: 'customer-1',
              name: 'Njeri Stores',
              phone: '0712 000 111',
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('send-statement')), findsNothing);

    await getIt.reset();
    getIt.registerSingleton<AuthService>(_ConnectedAuthService());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(const ['statements.share']),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              debtorId: 'debtor-1',
              name: 'Neighbour Shop',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('send-statement')), findsOneWidget);
    expect(find.text('Send statement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop statement choices use a side panel, not a bottom sheet',
      (tester) async {
    DesktopLayout.debugIsDesktopPlatform = true;
    useWindow(tester, const Size(1366, 768));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(['statements.share', 'customers.view']),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DesktopScope(
              sidebarCollapsed: true,
              child: SendStatementButton(
                customerId: 'customer-1',
                name: 'Njeri Stores',
                phone: '0712 000 111',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSheetFrame), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Send by SMS via HTTPSMS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop statement review is a dialog and shows consent',
      (tester) async {
    DesktopLayout.debugIsDesktopPlatform = true;
    useWindow(tester, const Size(1366, 768));
    final database = _StatementDatabase();
    addTearDown(database.close);
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<StorageService>(_ConfiguredSmsStorage());

    var requestCount = 0;
    getIt.registerSingleton<HttpsmsService>(
      HttpsmsService(
        transport: (uri, {required headers, required body}) async {
          requestCount++;
          return http.Response('{"data":{"id":"queued-1"}}', 200);
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(['statements.share', 'customers.view']),
          ),
        ],
        child: MaterialApp(
          theme: DesktopTheme.of(AppTheme.lightTheme),
          home: const Scaffold(
            body: DesktopScope(
              sidebarCollapsed: true,
              child: SendStatementButton(
                customerId: 'customer-1',
                name: 'Njeri Stores',
                phone: '0712 000 111',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();
    final httpsmsOption = find.text('Send by SMS via HTTPSMS');
    await tester.ensureVisible(httpsmsOption);
    await tester.tap(httpsmsOption);
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSheetFrame), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Review statement SMS'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(requestCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending requires consent and queues through HTTPSMS',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final database = _StatementDatabase();
    addTearDown(database.close);
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<StorageService>(_ConfiguredSmsStorage());

    var requestCount = 0;
    Map<String, dynamic>? requestBody;
    Map<String, String>? requestHeaders;
    getIt.registerSingleton<HttpsmsService>(
      HttpsmsService(
        transport: (uri, {required headers, required body}) async {
          requestCount++;
          requestHeaders = headers;
          requestBody = jsonDecode(body) as Map<String, dynamic>;
          return http.Response('{"data":{"id":"queued-1"}}', 200);
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(['statements.share', 'customers.view']),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              customerId: 'customer-1',
              name: 'Njeri Stores',
              phone: '0712 000 111',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();
    final httpsmsOption = find.text('Send by SMS via HTTPSMS');
    await tester.ensureVisible(httpsmsOption);
    await tester.tap(httpsmsOption);
    await tester.pumpAndSettle();

    expect(find.text('Review statement SMS'), findsOneWidget);
    expect(find.textContaining('HTTPSMS end-to-end encryption is off'),
        findsOneWidget);
    expect(find.textContaining('Carrier rates vary'), findsOneWidget);
    expect(requestCount, 0);
    final sendButton = find.widgetWithText(FilledButton, 'Queue SMS');
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(requestHeaders?['x-api-key'], 'test-account-key');
    expect(requestBody?['from'], '+254711222333');
    expect(requestBody?['to'], '+254712000111');
    expect(requestBody?['encrypted'], isFalse);
    expect(requestBody?['content'], contains('Outstanding balance:'));
    expect(requestBody?['content'], isNot(contains('Customer phone:')));
    expect(
      find.text('Queued in HTTPSMS. Check its queue for delivery status.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HTTPSMS does not queue a customer statement after customers.view is revoked',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final database = _StatementDatabase();
    addTearDown(database.close);
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<StorageService>(_ConfiguredSmsStorage());

    var requestCount = 0;
    getIt.registerSingleton<HttpsmsService>(
      HttpsmsService(
        transport: (uri, {required headers, required body}) async {
          requestCount++;
          return http.Response('{"data":{"id":"queued-1"}}', 200);
        },
      ),
    );
    final permissions = _MutableStatementPermissions(
      RolePermissions(const ['statements.share', 'customers.view']),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWith(
            (ref) => ref.watch(_mutableStatementPermissionsProvider),
          ),
          _mutableStatementPermissionsProvider
              .overrideWith((ref) => permissions),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              customerId: 'customer-1',
              name: 'Njeri Stores',
              phone: '0712 000 111',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();
    final httpsmsOption = find.text('Send by SMS via HTTPSMS');
    await tester.ensureVisible(httpsmsOption);
    await tester.tap(httpsmsOption);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final queueButton = find.widgetWithText(FilledButton, 'Queue SMS');
    final staleAction = tester.widget<FilledButton>(queueButton).onPressed!;

    permissions.state = RolePermissions(const ['statements.share']);
    staleAction();
    await tester.pumpAndSettle();

    expect(requestCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown queue outcome cannot be retried from the dialog',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final database = _StatementDatabase();
    addTearDown(database.close);
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<StorageService>(_ConfiguredSmsStorage());

    var requestCount = 0;
    getIt.registerSingleton<HttpsmsService>(
      HttpsmsService(
        transport: (uri, {required headers, required body}) async {
          requestCount++;
          throw http.ClientException('response connection dropped');
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(['statements.share', 'customers.view']),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SendStatementButton(
              customerId: 'customer-1',
              name: 'Njeri Stores',
              phone: '0712 000 111',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('send-statement')));
    await tester.pumpAndSettle();
    final httpsmsOption = find.text('Send by SMS via HTTPSMS');
    await tester.ensureVisible(httpsmsOption);
    await tester.tap(httpsmsOption);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue SMS'));
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.textContaining('Check the HTTPSMS queue before trying again'),
        findsOneWidget);
    expect(find.text('Close and check queue'), findsOneWidget);
    expect(find.text('Queue SMS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
