import 'package:axon_pos/core/desktop/adaptive_overlays.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

class _Product {
  const _Product(this.id, this.name, this.sku, this.category, this.price,
      this.stock);
  final int id;
  final String name;
  final String sku;
  final String category;
  final int price;
  final int stock;
}

const _products = [
  _Product(1, 'Sugar 2kg', '6001234000011', 'Groceries', 330, 48),
  _Product(2, 'Fresh milk 500ml', '6001234000028', 'Dairy', 65, 6),
  _Product(3, 'Cooking oil 1L', '6001234000035', 'Groceries', 310, 0),
  _Product(4, 'Bread, white', '6001234000042', 'Bakery', 70, 22),
  _Product(5, 'Airtime KES 100', '6001234000059', 'Airtime', 100, 999),
  _Product(6, 'Maize flour 2kg', '6001234000066', 'Groceries', 150, 31),
];

Widget _page({required int? selected, required void Function(int?) onSelect}) {
  final columns = <DesktopColumn<_Product>>[
    DesktopColumn(
      label: 'Product',
      flex: 3,
      sortBy: (r) => r.name,
      cell: (c, r) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopCellText(r.name, strong: true),
          DesktopCellText(r.sku, muted: true),
        ],
      ),
    ),
    DesktopColumn(
      label: 'Category',
      flex: 2,
      sortBy: (r) => r.category,
      cell: (c, r) => DesktopCellText(r.category, muted: true),
    ),
    DesktopColumn(
      label: 'Price',
      width: 110,
      numeric: true,
      sortBy: (r) => r.price,
      cell: (c, r) => DesktopCellText('${r.price}.00', numeric: true),
    ),
    DesktopColumn(
      label: 'Stock',
      width: 130,
      numeric: true,
      sortBy: (r) => r.stock,
      cell: (c, r) => r.stock == 0
          ? const DesktopStatusChip(label: 'Out of stock', color: Colors.red)
          : r.stock < 10
              ? DesktopStatusChip(
                  label: 'Low · ${r.stock}', color: Colors.orange.shade700)
              : DesktopCellText('${r.stock}', numeric: true),
    ),
  ];

  return Builder(builder: (context) {
    final picked = _products.where((p) => p.id == selected).firstOrNull;
    return Scaffold(
      body: DesktopInspectorLayout(
        onClose: () => onSelect(null),
        inspector: picked == null
            ? null
            : DesktopInspector(
                title: picked.name,
                subtitle: picked.sku,
                onClose: () => onSelect(null),
                footer: FilledButton(
                    onPressed: () {}, child: const Text('Receive stock')),
                child: const Text('Stock by location, price history…'),
              ),
        main: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Products',
              subtitle: '6 items · 1 out of stock',
              actions: [
                OutlinedButton(onPressed: () {}, child: const Text('Import')),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add product'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: DesktopTokens.gutter),
              child: DesktopMetricStrip(metrics: [
                DesktopMetric(label: 'Stock value', value: 'KES 184,200'),
                DesktopMetric(
                    label: 'Low stock', value: '1', hint: 'Needs reordering'),
                DesktopMetric(label: 'Out of stock', value: '1'),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DesktopTokens.gutter, 14, DesktopTokens.gutter, 10),
              child: Row(
                children: [
                  const DesktopSearchField(
                      hint: 'Search name, SKU or scan', width: 300),
                  const SizedBox(width: 12),
                  DesktopFilterChip(
                      label: 'All', selected: true, count: 6, onTap: () {}),
                  const SizedBox(width: 8),
                  DesktopFilterChip(
                      label: 'Low stock', selected: false, onTap: () {}),
                ],
              ),
            ),
            Expanded(
              child: DesktopDataTable<_Product>(
                columns: columns,
                rows: _products,
                rowId: (r) => r.id,
                selectedId: selected,
                onRowSelected: (r) => onSelect(r.id),
                initialSortColumn: 0,
                footer: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text('6 of 6 products'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  });
}

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    testWidgets('kit screenshot ${dark ? 'dark' : 'light'}', (tester) async {
      useWindow(tester, const Size(1100, 640));
      final key = GlobalKey();
      int? selected = 2;
      late StateSetter setState;
      final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DesktopTheme.of(base),
        home: ShotFrame(
          boundaryKey: key,
          child: StatefulBuilder(builder: (context, set) {
            setState = set;
            return _page(
                selected: selected, onSelect: (v) => set(() => selected = v));
          }),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Sugar 2kg'), findsWidgets);

      // arrow keys move the selection
      await tester.tap(find.text('Bread, white'));
      await tester.pump();
      expect(selected, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 3); // sorted by name: Bread, then Cooking oil
      // Esc closes the inspector
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(selected, isNull);

      setState(() => selected = 2);
      await tester.pumpAndSettle();
      await saveShot(
          tester, key, 'build/shots/desktop-kit-${dark ? 'dark' : 'light'}.png');
    });
  }

  testWidgets('sort header reorders rows', (tester) async {
    useWindow(tester, const Size(1100, 640));
    await tester.pumpWidget(MaterialApp(
      theme: DesktopTheme.of(AppTheme.lightTheme),
      home: _page(selected: null, onSelect: (_) {}),
    ));
    await tester.pump();
    final firstBefore = tester.getTopLeft(find.text('Bread, white')).dy;
    await tester.tap(find.text('Price'));
    await tester.pump();
    await tester.tap(find.text('Price'));
    await tester.pump();
    // price descending puts Cooking oil (310) above Bread (70)
    expect(tester.getTopLeft(find.text('Cooking oil 1L')).dy,
        lessThan(tester.getTopLeft(find.text('Bread, white')).dy));
    expect(firstBefore, isNonNegative);
  });

  testWidgets('showAdaptiveSheet is a dialog on desktop, a sheet on a phone',
      (tester) async {
    for (final desktop in [true, false]) {
      DesktopLayout.debugIsDesktopPlatform = desktop;
      addTearDown(() => DesktopLayout.debugIsDesktopPlatform = null);
      useWindow(tester, desktop ? const Size(1300, 800) : const Size(390, 800));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAdaptiveSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 80, child: Text('hello')),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), desktop ? findsOneWidget : findsNothing);
      expect(find.byType(BottomSheet), desktop ? findsNothing : findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
    }
  });
}
