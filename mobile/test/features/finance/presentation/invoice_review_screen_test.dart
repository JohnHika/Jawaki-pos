import 'dart:async';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/core/services/supplier_receipt_ocr_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/finance/presentation/screens/invoice_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends Fake implements AuthService {
  @override
  String? get branchId => 'branch-1';

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLocked => false;

  @override
  // Exercise the cloud save path (api.createSupplierInvoice).
  bool get isLocalWorkspace => false;

  @override
  Map<String, dynamic>? get currentUser => null;

  final _statusController = StreamController<AuthStatus>.broadcast();

  @override
  Stream<AuthStatus> get authStatusStream => _statusController.stream;
}

class _Net extends Fake implements ConnectivityService {
  @override
  bool get isOnline => true;
}

class _Api extends Fake implements ApiClient {
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>> createSupplierInvoice(
      Map<String, dynamic> payload) async {
    saved = payload;
    return <String, dynamic>{};
  }
}

const _scan = SupplierReceiptScan(
  imagePath: '',
  rawText: 'raw',
  suggestedSupplierName: 'Unknown Supplier',
  invoiceNumber: 'INV-204',
  totalAmount: 5200,
  summary: 'Scanned 2 lines',
  items: [
    SupplierReceiptLineItem(
        name: 'Omo 1kg',
        quantity: 10,
        unit: 'carton',
        unitCost: 200,
        lineTotal: 2000,
        confidence: 0.9,
        rawText: 'Omo 1kg 10 x 200'),
    SupplierReceiptLineItem(
        name: 'Cooking oil 5L',
        quantity: 4,
        unit: 'carton',
        unitCost: 800,
        lineTotal: 3200,
        confidence: 0.8,
        rawText: 'Oil 4 x 800'),
  ],
);

void main() {
  late _Api api;
  bool? popped;

  setUp(() {
    api = _Api();
    popped = null;
    // A scope shadows the cloud-mode AuthService stub from
    // flutter_test_config.dart instead of colliding with it.
    getIt.pushNewScope();
    getIt.registerSingleton<AuthService>(_Auth());
    getIt.registerSingleton<ConnectivityService>(_Net());
    getIt.registerSingleton<ApiClient>(api);
  });

  tearDown(() async => getIt.popScope());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => popped = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(
                        builder: (_) => const InvoiceReviewScreen(scan: _scan))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the scanned lines and a running total', (tester) async {
    await open(tester);

    expect(find.text('Review Invoice'), findsOneWidget);
    expect(find.text('Scanned 2 lines'), findsOneWidget);
    expect(find.text('INV-204'), findsOneWidget);
    expect(find.text('Omo 1kg'), findsOneWidget);
    expect(find.text('Cooking oil 5L'), findsOneWidget);
    expect(find.textContaining('5,200'), findsWidgets);
  });

  testWidgets('cannot be saved until a supplier name is entered',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Save Invoice'));
    await tester.pumpAndSettle();
    expect(api.saved, isNull, reason: 'Unknown Supplier must be named first');

    await tester.enterText(find.byType(TextFormField).first, 'Bidco Africa');
    await tester.pump();
    await tester.tap(find.text('Save Invoice'));
    await tester.pumpAndSettle();
    expect(api.saved, isNotNull);
  });

  testWidgets('editing a quantity updates the total and what is saved',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Bidco Africa');

    // The first line's quantity is the field showing "10".
    final qty = find.widgetWithText(TextFormField, '10');
    expect(qty, findsOneWidget);
    await tester.enterText(qty, '12');
    await tester.pump();
    expect(find.textContaining('5,600'), findsWidgets); // 12*200 + 4*800

    await tester.tap(find.text('Save Invoice'));
    await tester.pumpAndSettle();

    final saved = api.saved!;
    expect(saved['branchId'], 'branch-1');
    expect(saved['supplierName'], 'Bidco Africa');
    expect(saved['invoiceNumber'], 'INV-204');
    final items = saved['items'] as List;
    expect(items, hasLength(2));
    expect(items.first, containsPair('quantity', 12.0));
    expect(items.first, containsPair('unitCost', 200.0));
    expect(popped, isTrue, reason: 'screen closes and reports success');
  });

  testWidgets('keeps keyboard focus while typing a product name',
      (tester) async {
    await open(tester);
    final product = find.widgetWithText(TextFormField, 'Omo 1kg');
    await tester.tap(product);
    await tester.pump();
    await tester.enterText(product, 'Omo 1kg Lemon');
    await tester.pump();

    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(focused!.context!.findAncestorWidgetOfExactType<EditableText>()?.controller.text,
        'Omo 1kg Lemon');
    expect(find.text('Omo 1kg Lemon'), findsOneWidget);
  });

  testWidgets('an item can be added and removed', (tester) async {
    await open(tester);
    expect(find.text('Product'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Product'), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Product'), findsNWidgets(2));
    expect(find.text('Omo 1kg'), findsNothing);
  });
}
