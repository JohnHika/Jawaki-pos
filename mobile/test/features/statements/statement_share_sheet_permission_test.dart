import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/statements/presentation/widgets/statement_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStatementApi implements ApiClient {
  final preview = <String, dynamic>{
    'debtor': {'name': 'Private Customer'},
    'outstanding': 42.5,
    'overdue': 0,
    'oldestOverdueDays': 0,
    'items': <dynamic>[],
    'business': {'payInstructions': 'Paybill 123'},
  };
  Completer<Map<String, dynamic>>? pendingPreview;
  Completer<Map<String, dynamic>>? pendingLink;
  var previewCalls = 0;
  var historyCalls = 0;
  var createLinkCalls = 0;
  var downloadCalls = 0;
  String? lastCustomerId;
  String? lastDebtorId;

  @override
  Future<Map<String, dynamic>> previewStatement(
      {String? customerId, String? debtorId}) {
    previewCalls++;
    lastCustomerId = customerId;
    lastDebtorId = debtorId;
    return pendingPreview?.future ?? Future.value(preview);
  }

  @override
  Future<List<Map<String, dynamic>>> getStatementLinks(
      {String? customerId, String? debtorId}) async {
    historyCalls++;
    return const [];
  }

  @override
  Future<Map<String, dynamic>> createStatementLink({
    String? customerId,
    String? debtorId,
    String? message,
    int? days,
  }) {
    createLinkCalls++;
    return pendingLink?.future ??
        Future.value({
          'id': 'link-1',
          'path': '/s/token',
          'url': 'https://example.test/s/token',
          'shareText': {'en': 'Your statement: https://example.test/s/token'},
        });
  }

  @override
  Future<List<int>> downloadStatementPdf(String path, {String lang = 'en'}) {
    downloadCalls++;
    return Future.value(const []);
  }

  @override
  String absoluteUrl(String path) => 'https://example.test$path';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableStatementPermissions extends StateNotifier<RolePermissions> {
  _MutableStatementPermissions(super.state);
}

final _mutableStatementPermissionsProvider =
    StateNotifierProvider<_MutableStatementPermissions, RolePermissions>(
  (ref) => _MutableStatementPermissions(RolePermissions([])),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('remote statement drops customer preview after permission revoke',
      (tester) async {
    await getIt.reset();
    final api = _FakeStatementApi()..pendingPreview = Completer();
    getIt.registerSingleton<ApiClient>(api);
    final permissions = _MutableStatementPermissions(
      RolePermissions(['statements.share', 'customers.view']),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await getIt.reset();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWith(
          (ref) => ref.watch(_mutableStatementPermissionsProvider),
        ),
        _mutableStatementPermissionsProvider.overrideWith((ref) => permissions),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStatementSheet(
                context,
                customerId: 'customer-1',
                name: 'Private Customer',
                phone: '0712345678',
              ),
              child: const Text('Open statement'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open statement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.previewCalls, 1);
    expect(api.historyCalls, 1);

    permissions.state = RolePermissions(['statements.share']);
    await tester.pump();
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);

    api.pendingPreview!.complete(api.preview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('Owes now'), findsNothing);
    expect(find.text('Customer details hidden'), findsOneWidget);
    expect(api.previewCalls, 1);
    expect(api.historyCalls, 1);
  });

  testWidgets(
      'remote PDF share stops if customer permission is revoked in flight',
      (tester) async {
    await getIt.reset();
    final api = _FakeStatementApi();
    getIt.registerSingleton<ApiClient>(api);
    final permissions = _MutableStatementPermissions(
      RolePermissions(['statements.share', 'customers.view']),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (api.pendingLink?.isCompleted == false) {
        api.pendingLink!.complete({
          'id': 'link-1',
          'path': '/s/token',
          'url': 'https://example.test/s/token',
        });
      }
      await getIt.reset();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWith(
          (ref) => ref.watch(_mutableStatementPermissionsProvider),
        ),
        _mutableStatementPermissionsProvider.overrideWith((ref) => permissions),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStatementSheet(
                context,
                customerId: 'customer-1',
                name: 'Private Customer',
                phone: '0712345678',
              ),
              child: const Text('Open statement'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open statement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Share PDF'), findsOneWidget);

    api.pendingLink = Completer();
    await tester.tap(find.text('Share PDF'));
    await tester.pump();
    expect(api.createLinkCalls, 1);

    permissions.state = RolePermissions(['statements.share']);
    await tester.pump();
    api.pendingLink!.complete({
      'id': 'link-1',
      'path': '/s/token',
      'url': 'https://example.test/s/token',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.downloadCalls, 0);
    expect(api.historyCalls, 1);
    expect(find.text('Private Customer'), findsNothing);
  });

  testWidgets('shop-ledger statement does not require customers.view',
      (tester) async {
    await getIt.reset();
    final api = _FakeStatementApi();
    getIt.registerSingleton<ApiClient>(api);
    final permissions = _MutableStatementPermissions(
      RolePermissions(['statements.share']),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await getIt.reset();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWith(
          (ref) => ref.watch(_mutableStatementPermissionsProvider),
        ),
        _mutableStatementPermissionsProvider.overrideWith((ref) => permissions),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStatementSheet(
                context,
                debtorId: 'shop-debtor-1',
                name: 'Partner Shop',
                phone: '0712000000',
              ),
              child: const Text('Open ledger statement'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open ledger statement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.previewCalls, 1);
    expect(api.lastCustomerId, isNull);
    expect(api.lastDebtorId, 'shop-debtor-1');
    expect(find.text('Partner Shop'), findsOneWidget);
  });
}
