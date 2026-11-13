import 'package:axon_pos/core/database/app_database.dart' show Product;
import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/catalog/domain/stock_status.dart';
import 'package:axon_pos/features/catalog/presentation/desktop/desktop_product_inspector.dart';
import 'package:axon_pos/features/catalog/presentation/desktop/desktop_products_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

const _names = [
  'Sugar 2kg',
  'Fresh milk 500ml',
  'Cooking oil 1L',
  'Bread, white 400g',
  'Airtime KES 100',
  'Maize flour 2kg',
  'Rice, pishori 1kg',
  'Tea leaves 250g',
  'Blue Band margarine Original 500g tub family pack special offer pack',
  'Soap, Menengai bar',
  'Eggs, tray of 30',
  'Salt 1kg',
  'Wheat flour 2kg',
  'Cabbage, medium',
  'Tomatoes, per kg',
  'Onions, per kg',
  'Kapa Oil cooking fat vegetable blend 2 litre jerrican with handle',
  'Toothpaste 100ml',
  'Matchbox, pack of 10',
  'Charcoal, 2kg tin',
  'Bar soap, white star',
  'Soda, Fanta 500ml',
  'Soda, Coke 500ml',
  'Water 1.5L',
  'Biscuits, Digestive',
  'Ugali flour 1kg',
  'Beans, Rosecoco 1kg',
  'Cooking gas refill 6kg',
  'Paraffin, per litre',
  'Candles, pack of 6',
  'Notebook A5',
  'Pen, blue',
  'Sanitary pads',
  'Diapers, size 3',
  'Baby powder 200g',
  'Vaseline 250ml',
  'Detergent, Omo 1kg',
  'Bleach 750ml',
  'Mandazi, each',
  'Sausage, smokie',
];

Product _product(int i, {bool active = true, bool tracked = true}) {
  final name = _names[i % _names.length];
  return Product(
    id: 'p$i',
    sku: '6001234${(10000 + i).toString()}',
    name: name,
    description: null,
    metadata: '{}',
    categoryId: i.isEven ? 'groceries' : 'household',
    price: 40.0 + (i * 17 % 400),
    costPrice: tracked ? 30.0 + (i * 13 % 300) : null,
    unit: i % 7 == 0 ? 'kg' : 'piece',
    imageUrl: null,
    isActive: active,
    trackInventory: tracked,
    allowFractions: false,
    minStock: 6,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

List<Product> _sample([int count = 40]) =>
    [for (var i = 0; i < count; i++) _product(i)];

Map<String, double> _quantities(List<Product> products) => {
      for (var i = 0; i < products.length; i++)
        products[i].id: i % 9 == 0
            ? 0
            : i % 5 == 0
                ? 3
                : (12 + i * 3).toDouble(),
    };

const _categories = [
  DesktopCategoryOption('groceries', 'Groceries'),
  DesktopCategoryOption('household', 'Household'),
];
const _categoryNames = {'groceries': 'Groceries', 'household': 'Household'};

/// Holds the page state the routed screen keeps in providers, so the view can
/// be driven in a test.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.products,
    this.selectedId,
    this.initialQuery = '',
    this.canEdit = true,
    this.starterNames = const [],
    this.onAdd,
    this.onSubmit,
    this.loading = false,
  });

  final List<Product> products;
  final String? selectedId;
  final String initialQuery;
  final bool canEdit;
  final List<String> starterNames;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onSubmit;
  final bool loading;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final TextEditingController _search =
      TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;
  String? _selected;
  String? _category;
  DesktopStockFilter _filter = DesktopStockFilter.all;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.products;
    final quantities = _quantities(all);
    StockLevel levelOf(Product p) => stockLevelFor(
          trackInventory: p.trackInventory,
          quantity: quantities[p.id],
          minStock: p.minStock,
        );
    var rows = all.where((p) => p.isActive != _removed).toList();
    if (_category != null) {
      rows = rows.where((p) => p.categoryId == _category).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      rows = rows
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q))
          .toList();
    }
    if (_filter == DesktopStockFilter.low) {
      rows = rows.where((p) => levelOf(p) == StockLevel.low).toList();
    } else if (_filter == DesktopStockFilter.out) {
      rows = rows.where((p) => levelOf(p) == StockLevel.out).toList();
    }
    final active = all.where((p) => p.isActive).toList();
    final selected = all.where((p) => p.id == _selected).firstOrNull;

    return Scaffold(
      body: DesktopProductsView(
        title: 'Products',
        singular: 'Product',
        products: rows,
        quantities: quantities,
        categoryNames: _categoryNames,
        categories: _categories,
        totalCount: active.length,
        lowCount: active.where((p) => levelOf(p) == StockLevel.low).length,
        outCount: active.where((p) => levelOf(p) == StockLevel.out).length,
        stockFilter: _filter,
        onStockFilter: (f) => setState(() => _filter = f),
        categoryId: _category,
        onCategory: (id) => setState(() => _category = id),
        searchController: _search,
        searchQuery: _query,
        onSearchChanged: (v) => setState(() => _query = v),
        onSearchSubmitted: (v) => widget.onSubmit?.call(v),
        selectedId: selected?.id,
        onSelect: (p) => setState(() => _selected = p?.id),
        showRemoved: _removed,
        onShowRemoved: (v) => setState(() => _removed = v),
        canEdit: widget.canEdit,
        canReceive: widget.canEdit,
        showCost: widget.canEdit,
        loading: widget.loading,
        starterNames: widget.starterNames,
        onAdd: widget.onAdd ?? () {},
        onAddNamed: (_) {},
        onManageCategories: () {},
        onEdit: (_) {},
        onReceive: (_) {},
        onCorrectCount: (_) {},
        onToggleRemoved: (_) {},
        inspector: selected == null
            ? null
            : DesktopProductInspector(
                product: selected,
                categoryName:
                    _categoryNames[selected.categoryId] ?? 'Uncategorized',
                quantity: quantities[selected.id],
                history: [
                  StockMovement(
                    kind: StockMovementKind.sale,
                    at: DateTime(2026, 11, 9, 16, 42),
                    quantity: -2,
                  ),
                  StockMovement(
                    kind: StockMovementKind.delivery,
                    at: DateTime(2026, 11, 8, 9, 5),
                    quantity: 24,
                    unitCost: 290,
                    note: 'Invoice 4471',
                  ),
                  StockMovement(
                    kind: StockMovementKind.correction,
                    at: DateTime(2026, 11, 3, 18, 20),
                    quantity: -1,
                    note: 'Torn bag',
                  ),
                ],
                historyAvailable: true,
                showCost: widget.canEdit,
                canEdit: widget.canEdit,
                canReceive: widget.canEdit,
                onClose: () => setState(() => _selected = null),
                onEdit: () {},
                onReceive: () {},
                onCorrectCount: () {},
                onToggleRemoved: () {},
              ),
      ),
    );
  }
}

Widget _app(Widget home, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DesktopTheme.of(base),
    home:
        boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
  );
}

/// Page area left of the window after the shell: sidebar 232 at 1366, rail 56
/// at 1093, sidebar 232 at 1920; top bar 44 and status bar 24 above and below.
const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
  '1920': Size(1688, 1012),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      testWidgets(
        'products table with inspector ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          useWindow(tester, entry.value);
          final key = GlobalKey();
          await tester.pumpWidget(_app(
            _Harness(products: _sample(), selectedId: 'p8'),
            dark: dark,
            boundary: key,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await saveShot(
            tester,
            key,
            'build/shots/stock-products-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );
        },
      );
    }
  }

  testWidgets('products without a selection, light 1366', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(_Harness(products: _sample()), boundary: key),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('40 products'), findsOneWidget);
    await saveShot(
        tester, key, 'build/shots/stock-products-open-light-1366.png');
  });

  testWidgets('first-run empty list teaches the page', (tester) async {
    for (final dark in [false, true]) {
      useWindow(tester, dark ? _sizes['1093']! : _sizes['1366']!);
      final key = GlobalKey();
      await tester.pumpWidget(_app(
        const _Harness(
          products: [],
          starterNames: ['Sugar', 'Cooking oil', 'Bread', 'Milk'],
        ),
        dark: dark,
        boundary: key,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing to sell yet'), findsOneWidget);
      expect(find.text('Add product'), findsWidgets);
      await saveShot(
        tester,
        key,
        'build/shots/stock-products-empty-${dark ? 'dark-1093' : 'light-1366'}.png',
      );
    }
  });

  testWidgets('a search with no match says so and offers to add it',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      _Harness(products: _sample(), initialQuery: 'zzqx'),
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(find.text('No product called "zzqx"'), findsOneWidget);
    expect(find.text('Add "zzqx"'), findsOneWidget);
    await saveShot(
        tester, key, 'build/shots/stock-products-noresults-light-1366.png');
  });

  testWidgets('clicking a row opens the inspector and Esc closes it',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(products: _sample())));
    await tester.pumpAndSettle();
    expect(find.text('Recent movements'), findsNothing);
    await tester.tap(find.text('Airtime KES 100').first);
    await tester.pumpAndSettle();
    expect(find.text('Recent movements'), findsOneWidget);
    expect(find.text('Receive stock'), findsWidgets);
    expect(find.text('Sold 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Recent movements'), findsNothing);
  });

  testWidgets('arrow keys move the selection and the inspector follows',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(products: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airtime KES 100').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // Sorted by name, the row after "Airtime KES 100" is "Baby powder 200g".
    expect(
      find.descendant(
        of: find.byType(DesktopInspector),
        matching: find.text('Baby powder 200g'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('stock chips narrow the table to low and out of stock',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(products: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Out of stock').first);
    await tester.pumpAndSettle();
    // p0, p9, p18, p27, p36 are out (index % 9 == 0).
    expect(find.text('5 products'), findsOneWidget);
    await tester.tap(find.text('Out of stock').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low stock').first);
    await tester.pumpAndSettle();
    // index % 5 == 0 but not % 9 == 0: 5,10,15,20,25,30,35 -> 7 products.
    expect(find.text('7 products'), findsOneWidget);
  });

  testWidgets('Enter in the search box reports the scanned code, Ctrl+N adds',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    String? submitted;
    var added = 0;
    await tester.pumpWidget(_app(_Harness(
      products: _sample(),
      onSubmit: (v) => submitted = v,
      onAdd: () => added++,
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '600123410003');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, '600123410003');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(added, 1);
  });

  testWidgets('a role that cannot edit sees no add button or cost column',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(
      _app(_Harness(products: _sample(), canEdit: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add product'), findsNothing);
    expect(find.text('Cost'), findsNothing);
  });

  testWidgets('loading shows skeleton rows, not a spinner page',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(
      _app(const _Harness(products: [], loading: true)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Product'), findsOneWidget);
  });
}
