import 'dart:async';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/pricelist/domain/price_list_builder.dart';
import 'package:axon_pos/features/pricelist/presentation/screens/price_list_screen.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

const _products = <Map<String, dynamic>>[
  {
    'id': 'maize',
    'name': 'Maize flour 2kg',
    'categoryId': 'groceries',
    'price': 120,
    'unit': 'piece',
    'trackInventory': true,
    'stock': 12,
    'pricingTiers': [
      {'unit': 'Carton', 'quantityPerUnit': 12, 'price': 1320},
    ],
  },
  {
    'id': 'wheat',
    'name': 'Wheat flour 2kg',
    'categoryId': 'groceries',
    'price': 145.5,
    'unit': 'piece',
    'trackInventory': true,
    'stock': 0,
    'pricingTiers': [],
  },
  {
    'id': 'soap',
    'name': 'Laundry soap',
    'categoryId': 'household',
    'price': 80,
    'unit': 'piece',
    'trackInventory': false,
    'stock': 0,
    'pricingTiers': [],
  },
];

const _categories = <Map<String, dynamic>>[
  {'id': 'groceries', 'name': 'Groceries'},
  {'id': 'household', 'name': 'Household'},
];

const _previewKey = ValueKey('price-list-preview');
const _stockToggleKey = ValueKey('price-list-stock-toggle');
const _tiersToggleKey = ValueKey('price-list-tiers-toggle');
const _phoneKey = ValueKey('price-list-contact-phone');
const _whatsappKey = ValueKey('price-list-whatsapp');
const _pdfKey = ValueKey('price-list-share-pdf');
const _copyKey = ValueKey('price-list-copy');

GoRouter _router({GlobalKey? boundary, bool desktopShell = true}) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            Widget page = const PriceListScreen();
            if (boundary != null) {
              page = ShotFrame(boundaryKey: boundary, child: page);
            }
            return desktopShell
                ? DesktopScope(sidebarCollapsed: true, child: page)
                : page;
          },
        ),
      ],
    );

Widget _app(
  GoRouter router, {
  bool dark = false,
  Stream<List<Map<String, dynamic>>> Function()? productStream,
}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return ProviderScope(
    overrides: [
      filteredProductsProvider(FilterParams()).overrideWith(
        (ref) => productStream?.call() ?? Stream.value(_products),
      ),
      categoriesProvider.overrideWith((ref) async => _categories),
      businessLayoutProvider
          .overrideWith((ref) => businessLayoutFromUser(null)),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: DesktopTheme.of(base),
      routerConfig: router,
    ),
  );
}

Finder _inTable(String text) => find.descendant(
      of: find.byType(DesktopDataTable<PriceListItem>),
      matching: find.text(text),
    );

String _preview(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byKey(_previewKey)).data!;

void main() {
  setUpAll(loadShotFonts);

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({
      'user': '{"tenant":{"name":"Maua Market"},"phone":"0712 345 678"}',
    });
    final storage = StorageService();
    await storage.initialize();
    getIt.registerSingleton<StorageService>(storage);
  });

  tearDown(() async {
    await getIt.reset();
  });

  for (final dark in [false, true]) {
    for (final entry in desktopSizes.entries) {
      testWidgets(
        'desktop price list workspace ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          useWindow(tester, entry.value);
          final boundary = GlobalKey();
          final router = _router(boundary: boundary);
          addTearDown(router.dispose);
          await tester.pumpWidget(_app(router, dark: dark));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(DesktopPageHeader), findsOneWidget);
          expect(find.byType(DesktopDataTable<PriceListItem>), findsOneWidget);
          expect(find.text('WhatsApp preview'), findsOneWidget);
          expect(_inTable('Maize flour 2kg'), findsOneWidget);
          expect(_inTable('Laundry soap'), findsOneWidget);
          expect(_inTable('Wheat flour 2kg'), findsNothing);
          expect(_preview(tester), contains('Maize flour 2kg: KES 120'));
          expect(_preview(tester), contains('Carton (12): KES 1,320'));
          expect(_preview(tester), isNot(contains('Wheat flour 2kg')));
          await saveShot(
            tester,
            boundary,
            'build/shots/price-list-desktop-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );
        },
      );
    }
  }

  testWidgets(
      'stock, category, bulk-price and contact controls update the preview',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(_preview(tester), contains('Laundry soap'));
    expect(_preview(tester), isNot(contains('Wheat flour 2kg')));
    await tester.tap(find.byKey(_stockToggleKey));
    await tester.pumpAndSettle();
    expect(_inTable('Wheat flour 2kg'), findsOneWidget);
    expect(_preview(tester), contains('Wheat flour 2kg: KES 145.50'));

    await tester.tap(find.byKey(_tiersToggleKey));
    await tester.pumpAndSettle();
    expect(_preview(tester), isNot(contains('Carton (12)')));

    await tester.tap(find.widgetWithText(DesktopFilterChip, 'Household'));
    await tester.pumpAndSettle();
    expect(_inTable('Laundry soap'), findsNothing);
    expect(_preview(tester), isNot(contains('Laundry soap')));

    await tester.enterText(find.byKey(_phoneKey), '0700 111 222');
    await tester.pumpAndSettle();
    expect(_preview(tester), contains('Call or WhatsApp 0700 111 222'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'copy uses the current preview and share actions stay callback-safe',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(_whatsappKey)).onPressed,
        isNotNull);
    expect(tester.widget<OutlinedButton>(find.byKey(_pdfKey)).onPressed,
        isNotNull);

    await tester.tap(find.byKey(_copyKey));
    await tester.pumpAndSettle();
    expect(clipboardText, contains('Maize flour 2kg: KES 120'));
    expect(clipboardText, contains('Carton (12): KES 1,320'));
    expect(find.text('Price list copied'), findsOneWidget);
  });

  testWidgets('loading keeps the desktop table frame and skeleton rows',
      (tester) async {
    useWindow(tester, desktopSizes['1093']!);
    final router = _router();
    addTearDown(router.dispose);
    final pendingProducts = StreamController<List<Map<String, dynamic>>>();
    addTearDown(pendingProducts.close);

    await tester.pumpWidget(_app(
      router,
      productStream: () => pendingProducts.stream,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(DesktopPageHeader), findsOneWidget);
    expect(
      tester
          .widget<DesktopDataTable<PriceListItem>>(
            find.byType(DesktopDataTable<PriceListItem>),
          )
          .loading,
      isTrue,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a product load error is shown inside the desktop workspace',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(
      router,
      productStream: () => Stream.error(StateError('offline')),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Couldn't load price list"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(DesktopPageHeader), findsOneWidget);
  });

  testWidgets('the phone route retains its original price-list controls',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final router = _router(desktopShell: false);
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DesktopPageHeader), findsNothing);
    expect(find.byType(DesktopDataTable<PriceListItem>), findsNothing);
    expect(find.text('Only products in stock'), findsOneWidget);
    expect(find.text('Show bulk prices'), findsOneWidget);
    expect(find.text('Send on WhatsApp'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('Carton (12): KES 1,320'),
    );
  });
}
