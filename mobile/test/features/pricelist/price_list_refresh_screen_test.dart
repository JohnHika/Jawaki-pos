import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:axon_pos/core/cache/swr_cache.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/pricelist/presentation/providers/price_list_sync_provider.dart';
import 'package:axon_pos/features/pricelist/presentation/screens/price_list_screen.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

Map<String, dynamic> _maize(num price) => {
      'id': 'maize',
      'name': 'Maize flour 2kg',
      'categoryId': 'groceries',
      'price': price,
      'unit': 'piece',
      'trackInventory': true,
      'stock': 12,
      'pricingTiers': [
        {'unit': 'Carton', 'quantityPerUnit': 12, 'price': 1320},
      ],
    };

const _soap = <String, dynamic>{
  'id': 'soap',
  'name': 'Laundry soap',
  'categoryId': 'household',
  'price': 80,
  'unit': 'piece',
  'trackInventory': true,
  'stock': 2,
  'minStock': 5,
  'pricingTiers': [],
};

const _categories = <Map<String, dynamic>>[
  {'id': 'groceries', 'name': 'Groceries'},
  {'id': 'household', 'name': 'Household'},
];

/// The shop's catalogue as the phone sees it; a refresh from the server changes
/// it, then the screen reads it again.
class _Shop {
  _Shop() : products = [_maize(120), _soap];

  List<Map<String, dynamic>> products;
  int syncs = 0;
  bool offline = false;

  Future<void> sync() async {
    syncs++;
    if (offline) throw StateError('offline');
    // Each pull brings a price KES 10 higher than the one before.
    products = [_maize(120 + 10 * syncs), _soap];
  }
}

Widget _app(
  _Shop shop, {
  bool deviceOnly = false,
  bool desktop = false,
  List<DisplayFeature> features = const [],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => desktop
            ? const DesktopScope(
                sidebarCollapsed: true, child: PriceListScreen())
            : const PriceListScreen(),
      ),
    ],
  );
  final base = AppTheme.lightTheme;
  return ProviderScope(
    overrides: [
      filteredProductsProvider(FilterParams())
          .overrideWith((ref) => Stream.value(shop.products)),
      categoriesProvider.overrideWith((ref) async => _categories),
      businessLayoutProvider.overrideWith((ref) => businessLayoutFromUser(null)),
      priceListSyncProvider.overrideWith(
        (ref) => PriceListSync(
          sync: shop.sync,
          deviceOnly: deviceOnly,
          scopeKey: 'test-shop',
          cache: SwrCache(namespace: 'pl_screen_test'),
        ),
      ),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: desktop ? DesktopTheme.of(base) : base,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(displayFeatures: features),
        child: child!,
      ),
    ),
  );
}

void main() {
  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({
      'user': '{"tenant":{"name":"Maua Market"},"phone":"0712 345 678"}',
    });
    final storage = StorageService();
    await storage.initialize();
    getIt.registerSingleton<StorageService>(storage);
  });

  tearDown(() async => getIt.reset());

  void phone(WidgetTester tester, [Size size = const Size(430, 850)]) =>
      useWindow(tester, size);

  testWidgets('opening the page asks the server, then shows when it did',
      (tester) async {
    final shop = _Shop();
    phone(tester);
    await tester.pumpWidget(_app(shop));
    await tester.pumpAndSettle();

    expect(shop.syncs, 1);
    expect(find.text('Updated just now'), findsOneWidget);
    // The quiet refresh brought the new price onto the list.
    expect(find.textContaining('130', findRichText: true), findsOneWidget);
  });

  testWidgets('the Refresh button pulls the server prices and says what moved',
      (tester) async {
    final shop = _Shop();
    phone(tester);
    await tester.pumpWidget(_app(shop));
    await tester.pumpAndSettle();
    expect(shop.syncs, 1);
    expect(find.textContaining('130', findRichText: true), findsOneWidget);

    // Another device raised the price on the server meanwhile.
    await tester.tap(find.byKey(const ValueKey('price-list-refresh')));
    await tester.pumpAndSettle();

    expect(shop.syncs, 2);
    expect(find.textContaining('140', findRichText: true), findsOneWidget);
    expect(find.text('Prices updated · 1 changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a price that moved is marked, filterable and explained',
      (tester) async {
    final shop = _Shop();
    phone(tester);
    // First look: 120 becomes the starting price, then the open-time pull
    // brings 130.
    await tester.pumpWidget(_app(shop));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('price-list-changed-chip')), findsOneWidget);
    expect(find.text('Changed · 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('price-list-changed-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Maize flour 2kg'), findsOneWidget);
    expect(find.text('Laundry soap'), findsNothing);

    await tester.tap(find.text('Maize flour 2kg'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('price-detail-price')), findsOneWidget);
    expect(find.textContaining('Up KES 10'), findsOneWidget);
    expect(find.textContaining('was KES 120'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the list and offers Retry',
      (tester) async {
    final shop = _Shop()..offline = true;
    phone(tester);
    await tester.pumpWidget(_app(shop));
    await tester.pumpAndSettle();

    expect(find.text('Maize flour 2kg'), findsOneWidget);
    expect(find.text('Showing saved prices'), findsOneWidget);
    expect(find.byKey(const ValueKey('price-list-retry')), findsOneWidget);
    expect(find.text('Not updated yet'), findsOneWidget);

    shop.offline = false;
    await tester.tap(find.byKey(const ValueKey('price-list-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Showing saved prices'), findsNothing);
    expect(find.text('Updated just now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pull-down gesture also reaches the server', (tester) async {
    final shop = _Shop();
    phone(tester);
    await tester.pumpWidget(_app(shop));
    await tester.pumpAndSettle();
    expect(shop.syncs, 1);

    await tester.fling(find.text('Maize flour 2kg'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(shop.syncs, 2);
  });

  testWidgets('a shop that keeps prices on the phone never asks a server',
      (tester) async {
    final shop = _Shop();
    phone(tester);
    await tester.pumpWidget(_app(shop, deviceOnly: true));
    await tester.pumpAndSettle();

    expect(shop.syncs, 0);
    expect(find.byKey(const ValueKey('price-list-freshness')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('price-list-refresh')));
    await tester.pumpAndSettle();
    expect(shop.syncs, 0);
    expect(find.text('Prices are up to date'), findsOneWidget);
  });

  testWidgets('tapping a row opens its price, bulk prices and a copy button',
      (tester) async {
    final shop = _Shop();
    phone(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(_app(shop, deviceOnly: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Laundry soap'));
    await tester.pumpAndSettle();
    expect(find.text('Low stock'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('price-detail-copy')));
    await tester.pumpAndSettle();
    expect(copied, contains('Laundry soap: KES 80'));
    expect(copied, isNot(contains('Maize')));
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });

  testWidgets('bulk prices show what each unit costs', (tester) async {
    final shop = _Shop();
    phone(tester);
    await tester.pumpWidget(_app(shop, deviceOnly: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maize flour 2kg'));
    await tester.pumpAndSettle();
    expect(find.text('Carton of 12'), findsOneWidget);
    expect(find.text('KES 110 each'), findsOneWidget);
  });

  group('foldable and small screens', () {
    testWidgets('an unfolded foldable splits the list and the send panel at the hinge',
        (tester) async {
      final shop = _Shop();
      phone(tester, const Size(673, 841));
      await tester.pumpWidget(_app(
        shop,
        deviceOnly: true,
        features: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(336, 0, 8, 841),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Send this list'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Send this list')).dx, greaterThan(344));
      expect(tester.getTopLeft(find.text('Maize flour 2kg')).dx, lessThan(336));
    });

    testWidgets('a foldable lying flat just uses the width', (tester) async {
      final shop = _Shop();
      phone(tester, const Size(673, 841));
      await tester.pumpWidget(_app(
        shop,
        deviceOnly: true,
        features: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(336, 0, 0, 841),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Send this list'), findsOneWidget);
    });

    testWidgets('the narrow cover screen of a foldable has no overflow',
        (tester) async {
      final shop = _Shop();
      phone(tester, const Size(280, 653));
      await tester.pumpWidget(_app(shop, deviceOnly: true));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Maize flour 2kg'), findsOneWidget);
    });
  });

  group('computer', () {
    testWidgets('Refresh button and F5 pull the server prices', (tester) async {
      final shop = _Shop();
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(_app(shop, desktop: true));
      await tester.pumpAndSettle();
      expect(shop.syncs, 1);
      expect(find.byKey(const ValueKey('price-list-freshness')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('price-list-refresh')));
      await tester.pumpAndSettle();
      expect(shop.syncs, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(shop.syncs, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed refresh shows the saved-prices note with Retry',
        (tester) async {
      final shop = _Shop()..offline = true;
      useWindow(tester, desktopSizes['1093']!);
      await tester.pumpWidget(_app(shop, desktop: true));
      await tester.pumpAndSettle();

      expect(find.text('Showing saved prices'), findsOneWidget);
      shop.offline = false;
      await tester.tap(find.byKey(const ValueKey('price-list-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Showing saved prices'), findsNothing);
    });
  });
}
