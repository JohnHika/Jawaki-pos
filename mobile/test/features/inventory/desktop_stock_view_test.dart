import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/catalog/presentation/desktop/desktop_products_view.dart'
    show DesktopStockFilter;
import 'package:axon_pos/features/inventory/presentation/desktop/desktop_inventory_tabs.dart';
import 'package:axon_pos/features/inventory/presentation/desktop/desktop_receive_document.dart';
import 'package:axon_pos/features/inventory/presentation/desktop/desktop_stock_view.dart';
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
];

List<Map<String, dynamic>> _items([int count = 40]) => [
      for (var i = 0; i < count; i++)
        {
          'id': 'p$i',
          'name':
              i < _names.length ? _names[i] : '${_names[i % 10]} ${i ~/ 10}',
          'sku': '6001234${10000 + i}',
          'categoryName': i.isEven ? 'Groceries' : 'Household',
          'price': 60.0 + i * 11,
          'costPrice': 45.0 + i * 8,
          'stock': i % 9 == 0
              ? 0.0
              : i % 5 == 0
                  ? 3.0
                  : (12 + i * 3).toDouble(),
          'minStock': 6,
          'unit': 'piece',
          'displayUnit': null,
          'displayQuantityPerUnit': null,
          'lastReceivedQuantity': null,
          'lastReceivedAt': DateTime(2026, 11, 8),
        },
    ];

class _Page extends StatefulWidget {
  const _Page({
    required this.items,
    this.selectedId,
    this.initialQuery = '',
  });

  final List<Map<String, dynamic>> items;
  final String? selectedId;
  final String initialQuery;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  late final TextEditingController _search =
      TextEditingController(text: widget.initialQuery);
  String? _selected;
  DesktopStockFilter _filter = DesktopStockFilter.all;
  late String _query = widget.initialQuery;

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
    final p = context.desktop;
    final rows = widget.items
        .where((i) =>
            _query.isEmpty ||
            i['name'].toString().toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageHeader(
            title: 'Inventory',
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            actions: [
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.inventory_rounded, size: 17),
                label: const Text('Receive stock'),
              ),
            ],
            bottom: DesktopInventoryTabs(
              tabs: DesktopInventoryTabs.forRole(
                isLocalWorkspace: false,
                canManageStock: true,
                canRequestStock: true,
                lowCount: 12,
              ),
              selectedLabel: 'Stock levels',
              onSelect: (_) {},
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: DesktopStockView(
              items: rows,
              searchController: _search,
              searchQuery: _query,
              onSearchChanged: (v) => setState(() => _query = v),
              selectedId: _selected,
              onSelect: (id) => setState(() => _selected = id),
              filter: _filter,
              onFilter: (f) => setState(() => _filter = f),
              canReceive: true,
              showCost: true,
              totalWorth: 184200,
              onReceive: (_) {},
              onOpenProduct: (_) {},
            ),
          ),
        ],
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

const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
};

class _ReceiveHarness extends StatefulWidget {
  const _ReceiveHarness({this.withRows = true, this.onScan, this.onSave});

  final bool withRows;
  final ValueChanged<String>? onScan;
  final VoidCallback? onSave;

  @override
  State<_ReceiveHarness> createState() => _ReceiveHarnessState();
}

class _ReceiveHarnessState extends State<_ReceiveHarness> {
  final supplier = TextEditingController(text: 'Mama Njeri Wholesalers');
  final note = TextEditingController();
  final scan = TextEditingController();
  final scanFocus = FocusNode();
  late final List<List<Object>> lines = widget.withRows
      ? [
          for (var i = 0; i < 4; i++)
            [
              TextEditingController(text: '${12 + i * 6}'),
              TextEditingController(text: i == 3 ? '' : '${40 + i * 9}'),
              FocusNode(),
              FocusNode(),
            ],
        ]
      : [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesktopReceiveDocument(
        supplier: supplier,
        note: note,
        scanController: scan,
        scanFocus: scanFocus,
        summary: '66 items in 4 products',
        paidLabel: widget.withRows ? 'KES 2,436 paid' : null,
        canSave: widget.withRows,
        tabs: DesktopInventoryTabs(
          tabs: DesktopInventoryTabs.forRole(
            isLocalWorkspace: true,
            canManageStock: true,
            canRequestStock: true,
          ),
          selectedLabel: 'Receive stock',
          onSelect: (_) {},
        ),
        rows: [
          for (var i = 0; i < lines.length; i++)
            DesktopReceiveRow(
              name: _names[i + 2],
              code: '6001234${10002 + i}',
              units: i == 1 ? const ['piece', 'carton'] : const ['piece'],
              unit: i == 1 ? 'carton' : 'piece',
              quantity: lines[i][0] as TextEditingController,
              cost: lines[i][1] as TextEditingController,
              qtyFocus: lines[i][2] as FocusNode,
              costFocus: lines[i][3] as FocusNode,
              note: i == 1 ? '= 288 piece' : null,
              lineTotal: i == 3 ? null : 480.0 + i * 120,
            ),
        ],
        onScanSubmitted: (v) => widget.onScan?.call(v),
        onBrowse: () {},
        onRemove: (_) {},
        onUnit: (_, __) {},
        onChanged: () => setState(() {}),
        onSave: widget.onSave ?? () {},
        onCancel: () {},
      ),
    );
  }
}

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      testWidgets(
        'stock table with inspector ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          useWindow(tester, entry.value);
          final key = GlobalKey();
          await tester.pumpWidget(_app(
            _Page(items: _items(), selectedId: 'p8'),
            dark: dark,
            boundary: key,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await saveShot(
            tester,
            key,
            'build/shots/stock-inventory-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );
        },
      );
    }
  }

  testWidgets('empty and no-result states', (tester) async {
    useWindow(tester, _sizes['1366']!);
    var key = GlobalKey();
    await tester.pumpWidget(
      _app(const _Page(items: []), boundary: key),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('to count yet'), findsOneWidget);
    await saveShot(
        tester, key, 'build/shots/stock-inventory-empty-light-1366.png');

    key = GlobalKey();
    await tester.pumpWidget(_app(
      _Page(items: _items(), initialQuery: 'zzqx'),
      boundary: key,
      dark: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('No match for "zzqx"'), findsOneWidget);
    await saveShot(
        tester, key, 'build/shots/stock-inventory-noresults-dark-1366.png');
  });

  testWidgets('Low stock chip narrows the table; row opens the inspector',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Page(items: _items())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low stock').last);
    await tester.pumpAndSettle();
    // index % 5 == 0 and not % 9 == 0: 7 rows.
    expect(find.text('7 products'), findsOneWidget);
    await tester.tap(find.text('Maize flour 2kg').first);
    await tester.pumpAndSettle();
    expect(find.text('On the shelf'), findsOneWidget);
  });

  testWidgets('tab strip shows the sub-areas and a role without stock rights',
      (tester) async {
    final full = DesktopInventoryTabs.forRole(
      isLocalWorkspace: false,
      canManageStock: true,
      canRequestStock: true,
    );
    expect(
      full.map((t) => t.label),
      [
        'Stock levels',
        'Receive stock',
        'Stock requests',
        'Restock suggestions'
      ],
    );
    final local = DesktopInventoryTabs.forRole(
      isLocalWorkspace: true,
      canManageStock: true,
      canRequestStock: false,
    );
    expect(local.map((t) => t.label),
        ['Stock levels', 'Receive stock', 'Restock suggestions']);
    final seller = DesktopInventoryTabs.forRole(
      isLocalWorkspace: false,
      canManageStock: false,
      canRequestStock: true,
    );
    expect(seller.map((t) => t.label),
        ['Stock levels', 'Stock requests', 'Restock suggestions']);
  });

  for (final dark in [false, true]) {
    testWidgets('receive stock document ${dark ? 'dark' : 'light'}',
        (tester) async {
      useWindow(tester, dark ? _sizes['1093']! : _sizes['1366']!);
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(const _ReceiveHarness(), dark: dark, boundary: key),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await saveShot(
        tester,
        key,
        'build/shots/stock-receive-${dark ? 'dark-1093' : 'light-1366'}.png',
      );
    });
  }

  testWidgets('receive stock empty document teaches the scan flow',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(const _ReceiveHarness(withRows: false), boundary: key),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Scan each item'), findsOneWidget);
    await saveShot(
        tester, key, 'build/shots/stock-receive-empty-light-1366.png');
  });

  testWidgets('Enter flows quantity -> price -> next line, then back to scan',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    String? scanned;
    var saved = 0;
    await tester.pumpWidget(_app(_ReceiveHarness(
      onScan: (v) => scanned = v,
      onSave: () => saved++,
    )));
    await tester.pumpAndSettle();
    final state =
        tester.state<_ReceiveHarnessState>(find.byType(_ReceiveHarness));

    // The scan box has the cursor on open; Enter reports the code.
    expect(state.scanFocus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField).at(2), '6001234555555');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(scanned, '6001234555555');

    final qty0 = state.lines[0][2] as FocusNode;
    final cost0 = state.lines[0][3] as FocusNode;
    final qty1 = state.lines[1][2] as FocusNode;
    qty0.requestFocus();
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(cost0.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(qty1.hasFocus, isTrue);

    // The last line's price returns the cursor to the scan box.
    final cost3 = state.lines[3][3] as FocusNode;
    cost3.requestFocus();
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(state.scanFocus.hasFocus, isTrue);

    // Ctrl+Enter saves the delivery.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(saved, 1);
  });

  testWidgets('Esc closes the stock inspector', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Page(items: _items(), selectedId: 'p8')));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopInspector), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('On the shelf'), findsNothing);
  });
}
