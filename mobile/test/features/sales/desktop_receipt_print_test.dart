import 'dart:async';
import 'dart:typed_data';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/features/sales/presentation/receipts_desktop/desktop_receipt_page.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/core/services/print_queue_service.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/sales_provider.dart';
import 'package:axon_pos/features/sales/presentation/screens/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';

const _saleId = 'sale-12345678';

const _receipt = <String, dynamic>{
  'receiptNumber': 'R-1001',
  'subtotal': 100.0,
  'discount': 0.0,
  'tax': 0.0,
  'total': 100.0,
  'paymentMethod': 'CASH',
  'createdAt': '2026-11-10T12:00:00.000Z',
  'branchName': 'Counterbase Test Shop',
  'branchAddress': '1 Market Road',
  'branchPhone': '0700 000 000',
  'isSynced': true,
  'items': [
    {
      'productName': 'Test product',
      'quantity': 1.0,
      'unitPrice': 100.0,
      'total': 100.0,
      'unit': 'piece',
      'quantityPerUnit': 1.0,
    },
  ],
};

class _CapturingPrintingPlatform extends PrintingPlatform {
  int layoutCalls = 0;
  int shareCalls = 0;
  String? jobName;
  Uint8List? document;
  PdfPageFormat? requestedFormat;
  bool? requestedDynamicLayout;
  Object? layoutError;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    layoutCalls++;
    jobName = name;
    requestedFormat = format;
    requestedDynamicLayout = dynamicLayout;
    if (layoutError != null) throw layoutError!;
    document = await onLayout(format);
    return true;
  }

  @override
  Future<PrintingInfo> info() async => throw UnimplementedError();

  @override
  Future<List<Printer>> listPrinters() async => throw UnimplementedError();

  @override
  Future<Printer?> pickPrinter(Rect bounds) async => throw UnimplementedError();

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    shareCalls++;
    return true;
  }

  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) async =>
      throw UnimplementedError();

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      throw UnimplementedError();
}

class _ReceiptAuth implements AuthService {
  @override
  bool get isLocalWorkspace => true;

  @override
  bool get showTaxOnReceipt => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableReceiptPrintPermissions extends StateNotifier<RolePermissions> {
  _MutableReceiptPrintPermissions(super.state);
}

final _mutableReceiptPrintPermissionsProvider =
    StateNotifierProvider<_MutableReceiptPrintPermissions, RolePermissions>(
  (ref) => _MutableReceiptPrintPermissions(RolePermissions(const [])),
);

class _CapturingPrintQueue implements PrintQueueService {
  Map<String, dynamic>? lastReceipt;

  @override
  Future<bool> isDesignatedPrinter() async => true;

  @override
  Future<bool> requestPrint({
    required Map<String, dynamic> receipt,
    required String saleId,
    required String paperWidth,
    bool showTax = true,
  }) async {
    lastReceipt = Map<String, dynamic>.from(receipt);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

late _CapturingPrintingPlatform _printingPlatform;
late _CapturingPrintQueue _printQueue;
var _receiptShareCalls = 0;
final _defaultPrintingPlatform = PrintingPlatform.instance;

Widget _app({Stream<Map<String, dynamic>>? receiptStream}) => DesktopScope(
      sidebarCollapsed: false,
      child: ProviderScope(
        overrides: [
          receiptProvider.overrideWith(
            (ref, saleId) => receiptStream ?? Stream.value(_receipt),
          ),
          permissionsProvider.overrideWithValue(RolePermissions(const [])),
          tenantIdentityProvider.overrideWithValue(TenantIdentity.empty),
        ],
        child: MaterialApp(
          theme: DesktopTheme.of(AppTheme.lightTheme),
          home: const Scaffold(body: ReceiptScreen(saleId: _saleId)),
        ),
      ),
    );

Widget _desktopPage({
  Map<String, dynamic>? receipt = _receipt,
  bool loading = false,
  String? errorMessage,
  VoidCallback? onPrint,
  VoidCallback? onPrintOnComputer,
}) =>
    MaterialApp(
      theme: DesktopTheme.of(AppTheme.lightTheme),
      home: Scaffold(
        body: DesktopReceiptPage(
          receipt: receipt,
          fallbackNumber: 'SALE1234',
          showTax: false,
          onClose: () {},
          loading: loading,
          errorMessage: errorMessage,
          onPrint: onPrint,
          onPrintOnComputer: onPrintOnComputer,
        ),
      ),
    );

void main() {
  setUpAll(loadShotFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<AuthService>(_ReceiptAuth());
    _printQueue = _CapturingPrintQueue();
    getIt.registerSingleton<PrintQueueService>(_printQueue);
    _printingPlatform = _CapturingPrintingPlatform();
    _receiptShareCalls = 0;
    PrintingPlatform.instance = _printingPlatform;
  });

  tearDown(() async {
    PrintingPlatform.instance = _defaultPrintingPlatform;
    await getIt.reset();
  });

  testWidgets('desktop receipt offers system printing as a separate action',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_printingPlatform.layoutCalls, 0);
    final systemPrintButton =
        find.widgetWithText(OutlinedButton, 'Print on this computer');
    expect(systemPrintButton, findsOneWidget);
    expect(
        tester.widget<OutlinedButton>(systemPrintButton).onPressed, isNotNull);

    await tester.tap(systemPrintButton);
    await tester.pumpAndSettle();

    expect(_printingPlatform.layoutCalls, 1);
    expect(_printingPlatform.jobName, contains('R-1001'));
    expect(_printingPlatform.requestedFormat, PdfPageFormat.a4);
    expect(_printingPlatform.requestedDynamicLayout, isFalse);
    expect(_printingPlatform.document, isNotNull);
    expect(String.fromCharCodes(_printingPlatform.document!.take(5)), '%PDF-');
  });

  testWidgets(
    'desktop receipt screen hides injected customer PII without customers.view',
    (tester) async {
      useWindow(tester, const Size(1366, 768));
      final receipt = <String, dynamic>{
        ..._receipt,
        'customerName': 'Private Customer',
        'customerPhone': '0712345678',
        'customerEmail': 'private@example.test',
        'customer': {
          'name': 'Private Customer',
          'phone': '0712345678',
        },
      };
      await tester.pumpWidget(_app(receiptStream: Stream.value(receipt)));
      await tester.pumpAndSettle();

      expect(find.text('Private Customer'), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      expect(find.text('private@example.test'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Print on this computer'),
      );
      await tester.pumpAndSettle();
      expect(_printingPlatform.layoutCalls, 1);
      expect(_printingPlatform.document, isNotNull);
      final pdfBytes = String.fromCharCodes(_printingPlatform.document!);
      expect(pdfBytes, isNot(contains('Private Customer')));
      expect(pdfBytes, isNot(contains('0712345678')));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Print'));
      await tester.pumpAndSettle();
      expect(
        _printQueue.lastReceipt!.keys
            .where((key) => key.toLowerCase().startsWith('customer')),
        isEmpty,
      );
      expect(_printQueue.lastReceipt!['receiptNumber'], 'R-1001');
      expect(_printQueue.lastReceipt!['total'], 100.0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'computer printing aborts if customers.view is revoked during PDF construction',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    final pendingPdf = Completer<Uint8List>();
    final permissions = _MutableReceiptPrintPermissions(
      RolePermissions(const ['sales.view', 'customers.view']),
    );
    final receipt = <String, dynamic>{
      ..._receipt,
      'customerName': 'Private Customer',
      'customerPhone': '0712345678',
    };
    Map<String, dynamic>? pdfInput;

    await tester.pumpWidget(
      DesktopScope(
        sidebarCollapsed: false,
        child: ProviderScope(
          overrides: [
            receiptProvider.overrideWith(
              (ref, saleId) => Stream.value(receipt),
            ),
            permissionsProvider.overrideWith(
              (ref) => ref.watch(_mutableReceiptPrintPermissionsProvider),
            ),
            _mutableReceiptPrintPermissionsProvider
                .overrideWith((ref) => permissions),
            tenantIdentityProvider.overrideWithValue(TenantIdentity.empty),
            receiptPdfBuilderProvider.overrideWithValue(
              (ref, saleId, value) {
                pdfInput = value;
                return pendingPdf.future;
              },
            ),
          ],
          child: MaterialApp(
            theme: DesktopTheme.of(AppTheme.lightTheme),
            home: const Scaffold(body: ReceiptScreen(saleId: _saleId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final printButton =
        find.widgetWithText(OutlinedButton, 'Print on this computer');
    await tester.tap(printButton);
    await tester.pump();
    expect(pdfInput?['customerName'], 'Private Customer');

    permissions.state = RolePermissions(const ['sales.view']);
    await tester.pump();
    pendingPdf.complete(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
    await tester.pumpAndSettle();

    expect(_printingPlatform.layoutCalls, 0);
    expect(_printingPlatform.document, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'receipt PDF sharing aborts if customers.view is revoked during construction',
      (tester) async {
    final pendingPdf = Completer<Uint8List>();
    final permissions = _MutableReceiptPrintPermissions(
      RolePermissions(const ['sales.view', 'customers.view']),
    );
    final receipt = <String, dynamic>{
      ..._receipt,
      'customerName': 'Private Customer',
      'customerPhone': '0712345678',
    };
    Map<String, dynamic>? pdfInput;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider.overrideWith(
            (ref) => ref.watch(_mutableReceiptPrintPermissionsProvider),
          ),
          _mutableReceiptPrintPermissionsProvider
              .overrideWith((ref) => permissions),
          receiptPdfBuilderProvider.overrideWithValue((ref, saleId, value) {
            pdfInput = value;
            return pendingPdf.future;
          }),
          receiptPdfShareDispatcherProvider.overrideWithValue(
            (bytes, filename) async {
              _receiptShareCalls++;
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => const ReceiptScreen(saleId: _saleId)
                    .shareReceipt(context, ref, receipt),
                child: const Text('Share receipt'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Share receipt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF document'));
    await tester.pump();
    expect(pdfInput?['customerName'], 'Private Customer');

    permissions.state = RolePermissions(const ['sales.view']);
    pendingPdf.complete(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
    await tester.pumpAndSettle();

    expect(_receiptShareCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thermal and computer print controls invoke separate actions',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    var thermalPrints = 0;
    var computerPrints = 0;
    await tester.pumpWidget(_desktopPage(
      onPrint: () => thermalPrints++,
      onPrintOnComputer: () => computerPrints++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Print'));
    await tester.pump();
    expect(thermalPrints, 1);
    expect(computerPrints, 0);

    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Print on this computer'));
    await tester.pump();
    expect(thermalPrints, 1);
    expect(computerPrints, 1);
    expect(_printingPlatform.layoutCalls, 0);
  });

  testWidgets('computer print is disabled while receipt loads', (tester) async {
    useWindow(tester, const Size(1366, 768));
    final receiptStream = StreamController<Map<String, dynamic>>();
    await tester.pumpWidget(_app(receiptStream: receiptStream.stream));
    await tester.pump();

    final systemPrintButton =
        find.widgetWithText(OutlinedButton, 'Print on this computer');
    expect(systemPrintButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(systemPrintButton).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_printingPlatform.layoutCalls, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await receiptStream.close();
  });

  testWidgets('computer print is disabled when receipt provider fails',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    final receiptStream = Stream<Map<String, dynamic>>.error(
      StateError('Receipt unavailable'),
    );
    await tester.pumpWidget(_app(receiptStream: receiptStream));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final systemPrintButton =
        find.widgetWithText(OutlinedButton, 'Print on this computer');
    expect(systemPrintButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(systemPrintButton).onPressed, isNull);
    expect(find.textContaining('Receipt unavailable'), findsOneWidget);
    expect(_printingPlatform.layoutCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('computer print reports operating system print errors',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    _printingPlatform.layoutError = StateError('Printing failed');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Print on this computer'));
    await tester.pumpAndSettle();

    expect(_printingPlatform.layoutCalls, 1);
    expect(find.textContaining('Could not print receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
