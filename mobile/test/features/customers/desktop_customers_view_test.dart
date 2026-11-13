import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/customers/presentation/desktop/desktop_customer_profile.dart';
import 'package:axon_pos/features/customers/presentation/desktop/desktop_customers_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

const _people = [
  'Wanjiru Mini Mart',
  'John Kamau',
  'Aisha Omar',
  'Peter Otieno',
  'Mama Njeri Groceries and General Hardware Supplies Limited',
  'Grace Wambui',
  'Hassan Abdi',
  'Faith Chebet',
  'Kevin Mutua',
  'Lucy Akinyi',
];

List<Map<String, dynamic>> _customers([int count = 40]) => [
      for (var i = 0; i < count; i++)
        {
          'id': 'c$i',
          'name': i == 4
              ? _people[4]
              : '${_people[i % _people.length]}${i >= _people.length ? ' ${i ~/ _people.length + 1}' : ''}',
          'phone':
              '07${10 + i % 80} ${100 + i * 7 % 900} ${100 + i * 13 % 900}',
          'location': i.isEven ? 'Kawangware' : 'Githurai 45',
          'balance': i % 3 == 0 ? 1500.0 + i * 230 : 0.0,
          'totalSpent': 12000.0 + i * 1800,
          'totalPurchases': 3 + i,
          'loyaltyPoints': i * 4,
        },
    ];

final _purchases = [
  for (var i = 0; i < 9; i++)
    {
      'id': 's$i',
      'receiptNumber': 'R-${2040 + i}',
      'total': 480.0 + i * 135,
      'paymentMethod': i % 3 == 0 ? 'cash' : (i % 3 == 1 ? 'mpesa' : 'credit'),
      'createdAt': DateTime(2026, 11, 9 - i, 14, 20).toIso8601String(),
    },
];

final _installments = [
  {
    'id': 'i1',
    'amount': 2000.0,
    'dueDate': DateTime(2026, 11, 3).toIso8601String(),
    'status': 'pending',
    'note': 'After month-end pay',
  },
  {
    'id': 'i2',
    'amount': 1500.0,
    'dueDate': DateTime(2099, 12, 1).toIso8601String(),
    'status': 'pending',
    'note': '',
  },
  {
    'id': 'i3',
    'amount': 800.0,
    'dueDate': DateTime(2026, 10, 12).toIso8601String(),
    'status': 'paid',
    'note': 'Cash at the shop',
  },
];

Widget _profile(Map<String, dynamic> c, {VoidCallback? onStartSale}) =>
    DesktopCustomerProfile(
      customer: c,
      customerLabel: 'Customer',
      purchases: _purchases,
      topProducts: const [
        {'productName': 'Sugar 2kg', 'timesBought': 12},
        {'productName': 'Cooking oil 1L', 'timesBought': 9},
        {'productName': 'Maize flour 2kg', 'timesBought': 7},
      ],
      installments: _installments,
      canManageReceivables: true,
      unscheduledBalance: 900,
      onStartSale: onStartSale ?? () {},
      onAddDueDate: () {},
      onRecordInstallment: (_) {},
      onCancelInstallment: (_) {},
      onOpenReceipt: (_) {},
      creditCard: Container(
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Credit limit card'),
      ),
      statementButton: OutlinedButton(
        onPressed: () {},
        child: const Text('Send statement'),
      ),
    );

class _Harness extends StatefulWidget {
  const _Harness({
    required this.customers,
    this.selectedId,
    this.initialQuery = '',
    this.onAdd,
    this.onStartSale,
  });

  final List<Map<String, dynamic>> customers;
  final String? selectedId;
  final String initialQuery;
  final VoidCallback? onAdd;
  final VoidCallback? onStartSale;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final TextEditingController _search =
      TextEditingController(text: widget.initialQuery);
  String? _selected;
  bool _owes = false;

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
    final q = _search.text.toLowerCase();
    var rows = widget.customers.where((c) {
      if (_owes && ((c['balance'] as num?) ?? 0) <= 0) return false;
      if (q.isEmpty) return true;
      return c['name'].toString().toLowerCase().contains(q) ||
          c['phone'].toString().contains(q);
    }).toList();
    final selected = _selected ?? (rows.isEmpty ? null : rows.first['id']);
    final selectedRow = widget.customers
        .where((c) => c['id'] == selected)
        .cast<Map<String, dynamic>?>()
        .firstOrNull;
    return Scaffold(
      body: DesktopCustomersView(
        title: 'Customers',
        singular: 'Customer',
        plural: 'Customers',
        customers: rows,
        searchController: _search,
        onSearchChanged: (_) => setState(() {}),
        owesOnly: _owes,
        onOwesOnly: (v) => setState(() => _owes = v),
        selectedId: selected?.toString(),
        onSelect: (id) => setState(() => _selected = id),
        detail: selectedRow == null
            ? null
            : _profile(selectedRow, onStartSale: widget.onStartSale),
        overdueCount: 2,
        onShowOverdue: () => setState(() => _owes = true),
        onAdd: widget.onAdd ?? () {},
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
  '1920': Size(1688, 1012),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in {
      '1366': _sizes['1366']!,
      '1093': _sizes['1093']!,
    }.entries) {
      testWidgets(
        'customers list and profile ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          useWindow(tester, entry.value);
          final key = GlobalKey();
          await tester.pumpWidget(_app(
            _Harness(customers: _customers(), selectedId: 'c3'),
            dark: dark,
            boundary: key,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await saveShot(
            tester,
            key,
            'build/shots/people-customers-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );
        },
      );
    }
  }

  testWidgets('customers at 1920 light', (tester) async {
    useWindow(tester, _sizes['1920']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      _Harness(customers: _customers(), selectedId: 'c4'),
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await saveShot(tester, key, 'build/shots/people-customers-light-1920.png');
  });

  testWidgets('sales and payment schedule tabs', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      _Harness(customers: _customers(), selectedId: 'c3'),
      boundary: key,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales').first);
    await tester.pumpAndSettle();
    expect(find.text('R-2040'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/people-sales-light-1366.png');
    await tester.tap(find.text('Payment schedule').first);
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Record'), findsWidgets);
    await saveShot(tester, key, 'build/shots/people-schedule-light-1366.png');
  });

  testWidgets('empty list teaches the page', (tester) async {
    for (final dark in [false, true]) {
      useWindow(tester, _sizes['1366']!);
      final key = GlobalKey();
      await tester.pumpWidget(_app(
        const _Harness(customers: []),
        dark: dark,
        boundary: key,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No customers yet'), findsOneWidget);
      expect(find.text('Pick a customer'), findsOneWidget);
      await saveShot(
        tester,
        key,
        'build/shots/people-empty-${dark ? 'dark' : 'light'}-1366.png',
      );
    }
  });

  testWidgets('a search with no match says so', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      _Harness(customers: _customers(), initialQuery: 'zzqx'),
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(find.text('No customer called "zzqx"'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/people-noresults-light-1366.png');
  });

  testWidgets('clicking a row swaps the profile without leaving the page',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(customers: _customers())));
    await tester.pumpAndSettle();
    expect(find.text('Wanjiru Mini Mart'), findsWidgets);
    await tester.tap(find.text('Aisha Omar').first);
    await tester.pumpAndSettle();
    // The name now also appears in the profile header at 20px.
    final headers = tester
        .widgetList<Text>(find.text('Aisha Omar'))
        .where((t) => t.style?.fontSize == 20);
    expect(headers.length, 1);
  });

  testWidgets('arrow keys move down the list', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(customers: _customers())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('John Kamau').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final headers = tester
        .widgetList<Text>(find.text('Aisha Omar'))
        .where((t) => t.style?.fontSize == 20);
    expect(headers.length, 1);
  });

  testWidgets('Owes money narrows the list and Start sale is wired',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    var started = 0;
    await tester.pumpWidget(_app(
      _Harness(customers: _customers(), onStartSale: () => started++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owes money').first);
    await tester.pumpAndSettle();
    // c0, c3, ... every third of 40 = 14 customers owe money.
    expect(find.text('14 customers'), findsOneWidget);
    await tester.tap(find.text('Start sale'));
    expect(started, 1);
  });

  testWidgets('Ctrl+N asks to add a customer', (tester) async {
    useWindow(tester, _sizes['1366']!);
    var added = 0;
    await tester.pumpWidget(
      _app(_Harness(customers: _customers(), onAdd: () => added++)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(added, 1);
  });
}
