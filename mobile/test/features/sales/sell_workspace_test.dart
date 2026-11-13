import 'dart:async';

import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/coupon_rules.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:axon_pos/features/sales/domain/recorded_payment.dart';
import 'package:axon_pos/features/sales/presentation/desktop/checkout_support.dart';
import 'package:axon_pos/features/sales/presentation/desktop/sell_catalog_pane.dart';
import 'package:axon_pos/features/sales/presentation/desktop/sell_ticket_panel.dart';
import 'package:axon_pos/features/sales/presentation/desktop/sell_workspace.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/payment_provider.dart';
import 'package:axon_pos/features/sales/presentation/widgets/record_payment_sheet.dart'
    show ApproverCheck;
import 'package:axon_pos/core/services/till_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';

// ─── Fakes ───

class _FakeAuth implements AuthService {
  @override
  double get taxRatePercent => 0;
  @override
  bool get showTaxOnReceipt => false;
  @override
  bool get isLocalWorkspace => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _FakeInbox() : super(const NotificationInboxState(unreadCount: 3));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePayments extends StateNotifier<PaymentState>
    implements PaymentNotifier {
  _FakePayments() : super(const PaymentState());

  final cashSales = <({double amount, double tendered})>[];
  final creditSales = <double>[];
  Future<String?> Function()? mpesaResult;
  var mpesaCalls = 0;

  @override
  bool get hasUnresolvedMerchantPayment => state.hasUnresolvedMerchantPayment;

  @override
  Future<String?> processCashPayment({
    required double amount,
    required double tenderedAmount,
    required List<CartItem> items,
    String? customerId,
    double discountAmount = 0,
    String? couponCode,
  }) async {
    cashSales.add((amount: amount, tendered: tenderedAmount));
    return 'sale-cash-1';
  }

  @override
  Future<String?> processCreditPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
    String? customerName,
    String? notes,
    double discountAmount = 0,
    String? couponCode,
  }) async {
    creditSales.add(amount);
    return 'sale-credit-1';
  }

  @override
  Future<String?> processMpesaPayment({
    required double amount,
    required String phoneNumber,
    required double discountAmount,
    required List<CartItem> items,
    String? customerId,
    String? couponCode,
  }) async {
    mpesaCalls++;
    state = const PaymentState(isProcessing: true);
    // The real notifier waits about 10 s before its first status check.
    await Future<void>.delayed(const Duration(seconds: 20));
    final result = await (mpesaResult?.call() ?? Future.value(null));
    if (result == null) {
      // Same shape as the real notifier after its 10 s check: still pending.
      state = const PaymentState(
        currentTransactionId: 'QGH7XK2LMN',
        hasUnresolvedMerchantPayment: true,
        error: 'Payment is still pending.',
      );
    } else {
      state = const PaymentState();
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHost implements SellCheckoutHost {
  Completer<List<Map<String, dynamic>>>? searchCompleter;
  Completer<String?>? customerPhoneCompleter;
  var customerPhoneCalls = 0;
  var searchCalls = 0;

  @override
  bool get isLocalWorkspace => false;
  @override
  RecordedPaymentRules get recordedRules => const RecordedPaymentRules();
  @override
  String get recorderId => 'u1';
  @override
  String get recorderName => 'Wanjiku Kamau';
  @override
  ApproverCheck get approverForPin => (pin) async => null;
  @override
  Future<Map<String, dynamic>?> loadPayoutAccount() async =>
      {'status': 'ACTIVE', 'paystackVerified': true};
  @override
  Future<String?> customerPhone(String customerId) {
    customerPhoneCalls++;
    return customerPhoneCompleter?.future ?? Future.value('0712345678');
  }

  @override
  Future<List<Map<String, dynamic>>> searchCustomers(String query) {
    searchCalls++;
    final pending = searchCompleter;
    if (pending != null) return pending.future;
    return Future.value([
      {'id': 'c1', 'name': 'Mama Njeri', 'phone': '0722000111', 'balance': 450},
      {'id': 'c2', 'name': 'Otieno Hardware', 'phone': '0733000222'},
    ]);
  }

  @override
  Future<bool> reviewSale(
    BuildContext context, {
    required List<GuardLine> lines,
    double cartDiscount = 0,
    double creditAmount = 0,
    String? customerId,
    String? customerName,
    bool includePricing = true,
  }) async =>
      true;
  @override
  Future<bool> recordCustomerPurchase(CartState cart) async => false;
}

class _SellPermissions extends StateNotifier<RolePermissions> {
  _SellPermissions(super.state);
}

final _sellPermissionsProvider =
    StateNotifierProvider<_SellPermissions, RolePermissions>(
  (ref) => _SellPermissions(RolePermissions(const [])),
);

// ─── Sample shop ───

Map<String, dynamic> _p(
  String id,
  String name,
  double price,
  num stock, {
  String? sku,
  bool tracked = true,
}) =>
    {
      'id': id,
      'name': name,
      'sku': sku ?? '60012340000$id',
      'price': price,
      'unit': 'piece',
      'stock': stock,
      'trackInventory': tracked,
      'allowFractions': false,
      'pricingTiers': const <Map<String, dynamic>>[],
    };

final _products = <Map<String, dynamic>>[
  _p('11', 'Sugar 2kg (Mumias)', 330, 48),
  _p('12', 'Fresh milk 500ml (Brookside)', 65, 6),
  _p('13', 'Cooking oil 1L (Elianto)', 310, 0),
  _p('14', 'Bread, white (Broadways)', 70, 22),
  _p('15', 'Airtime KES 100', 100, 0, tracked: false),
  _p('16', 'Maize flour 2kg (Jogoo)', 150, 31),
  _p('17', 'Royco mchuzi mix 200g', 45, 120),
  _p('18', 'Blue Band 500g', 215, 14),
  _p('19', 'Rice pishori 5kg', 890, 9),
  _p('20', 'Soda, Coca-Cola 500ml', 60, 96),
  _p('21', 'Tea leaves, Ketepa 250g', 120, 40),
  _p('22', 'Eggs, tray of 30', 520, 5),
  _p('23', 'Omo washing powder 1kg', 285, 18),
  _p('24', 'Mandazi, packet of 6', 60, 3),
];

class _Env {
  _Env({this.dark = false, this.view = 'list'});
  final bool dark;
  final String view;
  late CartNotifier cart;
  late _FakeHost host;
  late _SellPermissions permissions;
  final payments = _FakePayments();
  final sold = <CheckoutResult>[];
  final addProductCodes = <String>[];
  var holdCalls = 0;
  var heldSalesCalls = 0;
}

Future<Map<String, dynamic>> _anyStock(String id, double quantity) async {
  final product = _products.firstWhere((p) => p['id'] == id);
  final stock = (product['stock'] as num).toDouble();
  final tracked = product['trackInventory'] as bool;
  final ok = !tracked || stock >= quantity;
  return {
    'available': ok,
    'stockBlocked': !ok,
    'message': ok
        ? 'ok'
        : (stock <= 0
            ? 'Product is out of stock'
            : 'Insufficient stock available'),
    'currentStock': stock,
  };
}

const _navItems = <DesktopNavItem>[
  DesktopNavItem(
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    label: 'Home',
    path: '/dashboard',
    group: DesktopNavGroup.workspace,
  ),
  DesktopNavItem(
    icon: Icons.point_of_sale_outlined,
    activeIcon: Icons.point_of_sale_rounded,
    label: 'Sell',
    path: '/',
    group: DesktopNavGroup.workspace,
  ),
  DesktopNavItem(
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2_rounded,
    label: 'Products',
    path: '/products',
    group: DesktopNavGroup.stock,
  ),
  DesktopNavItem(
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long_rounded,
    label: 'Receipts',
    path: '/receipts',
    group: DesktopNavGroup.money,
  ),
  DesktopNavItem(
    icon: Icons.people_outlined,
    activeIcon: Icons.people_rounded,
    label: 'Customers',
    path: '/customers',
    group: DesktopNavGroup.people,
  ),
];

const _settings = DesktopNavItem(
  icon: Icons.settings_outlined,
  activeIcon: Icons.settings_rounded,
  label: 'Settings',
  path: '/settings',
  group: DesktopNavGroup.more,
);

Future<_Env> _pump(
  WidgetTester tester, {
  Size size = const Size(1366, 768),
  bool dark = false,
  String view = 'list',
  GlobalKey? boundary,
  bool startInPayment = false,
  int heldSalesCount = 0,
  List<dynamic> permissions = const [
    'sales.create',
    'sales.discount',
    'customers.view',
    'customers.create',
  ],
  void Function(_Env env)? beforePump,
}) async {
  SharedPreferences.setMockInitialValues({'sell_product_view': view});
  useWindow(tester, size);
  final env = _Env(dark: dark, view: view);
  env.cart = CartNotifier(stockValidator: _anyStock);
  env.host = _FakeHost();
  env.permissions = _SellPermissions(RolePermissions(permissions));
  beforePump?.call(env);
  DesktopStatusRegistry.entries.value = const [];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartProvider.overrideWith((ref) => env.cart),
        paymentProvider.overrideWith((ref) => env.payments),
        sellCheckoutHostProvider.overrideWithValue(env.host),
        permissionsProvider.overrideWith(
          (ref) => ref.watch(_sellPermissionsProvider),
        ),
        _sellPermissionsProvider.overrideWith((ref) => env.permissions),
        businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
        notificationInboxProvider.overrideWith((ref) => _FakeInbox()),
        filteredProductsProvider.overrideWith((ref, params) {
          final q = params.searchQuery?.toLowerCase();
          return Stream.value([
            for (final p in _products)
              if (q == null ||
                  (p['name'] as String).toLowerCase().contains(q) ||
                  (p['sku'] as String).toLowerCase().contains(q))
                p,
          ]);
        }),
        categoriesProvider.overrideWith(
          (ref) async => [
            for (final (id, name) in [
              ('c1', 'Groceries'),
              ('c2', 'Dairy'),
              ('c3', 'Bakery'),
              ('c4', 'Drinks'),
              ('c5', 'Household'),
              ('c6', 'Airtime'),
            ])
              {'id': id, 'name': name},
          ],
        ),
        favoriteProductsProvider.overrideWith((ref) async => const []),
        favoritesProvider.overrideWith(
          (ref) => FavoritesNotifier.emptyForTesting(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: ShotFrame(
          boundaryKey: boundary ?? GlobalKey(),
          child: DesktopShell(
            items: _navItems,
            settingsItem: _settings,
            location: '/',
            onNavigate: (_) {},
            companyName: 'Evisa Ventures',
            userName: 'Wanjiku Kamau',
            role: 'Cashier',
            version: '1.0.181',
            child: SellWorkspace(
              startInPayment: startInPayment,
              onSaleComplete: env.sold.add,
              onAddUnknownProduct: env.addProductCodes.add,
              heldSalesCount: heldSalesCount,
              onHoldSale: () => env.holdCalls++,
              onOpenHeldSales: () => env.heldSalesCalls++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return env;
}

Future<void> _fillTicket(_Env env, {int lines = 6}) async {
  const picks = ['11', '12', '14', '16', '18', '20', '21', '23'];
  for (var i = 0; i < lines; i++) {
    final p = _products.firstWhere((p) => p['id'] == picks[i]);
    await env.cart.addItem(
      productId: p['id'] as String,
      productName: p['name'] as String,
      sku: p['sku'] as String,
      unitPrice: (p['price'] as num).toDouble(),
      quantity: i == 0 ? 2 : (i == 3 ? 3 : 1),
      saleUnit: 'piece',
      saleQuantity: i == 0 ? 2 : (i == 3 ? 3 : 1),
      unitConversionFactor: 1,
    );
  }
}

Future<void> _scan(WidgetTester tester, String code) async {
  // Use timestamped hardware events rather than the tester's zero-timeStamp
  // key channel. ScanCapture intentionally falls back to wall time for those
  // events, which made this integration test depend on host load.
  var timeStamp = const Duration(milliseconds: 1);
  const interval = Duration(milliseconds: 8);
  const physicalKey = PhysicalKeyboardKey.keyA;
  for (final ch in code.split('')) {
    final logicalKey = LogicalKeyboardKey(ch.codeUnitAt(0));
    HardwareKeyboard.instance.handleKeyEvent(
      KeyDownEvent(
        physicalKey: physicalKey,
        logicalKey: logicalKey,
        character: ch,
        timeStamp: timeStamp,
      ),
    );
    timeStamp += interval;
    HardwareKeyboard.instance.handleKeyEvent(
      KeyUpEvent(
        physicalKey: physicalKey,
        logicalKey: logicalKey,
        timeStamp: timeStamp,
      ),
    );
    timeStamp += interval;
  }
  HardwareKeyboard.instance.handleKeyEvent(
    KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: timeStamp,
    ),
  );
  HardwareKeyboard.instance.handleKeyEvent(
    KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: timeStamp + interval,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _inPane(Finder f) =>
    find.descendant(of: find.byType(SellCatalogPane), matching: f);

void main() {
  setUpAll(loadShotFonts);

  // Shadow the suite-wide auth stub with one that knows the tax rate.
  setUp(() {
    getIt.pushNewScope();
    getIt.registerSingleton<AuthService>(_FakeAuth());
  });
  tearDown(() async {
    await getIt.popScope();
  });

  group('two-zone workspace', () {
    testWidgets('search, products and an always-visible ticket with Pay',
        (tester) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('sell-search')), findsOneWidget);
      expect(_inPane(find.text('Sugar 2kg (Mumias)')), findsOneWidget);
      expect(find.text('Ticket'), findsOneWidget);
      expect(find.text('Nothing on this ticket yet'), findsOneWidget);
      // Pay exists and is disabled on an empty ticket.
      final pay = find.byKey(const ValueKey('pay-button'));
      expect(pay, findsOneWidget);
      expect(find.text('Scanner ready'), findsOneWidget);
    });

    testWidgets('clicking a product adds it; the total and Pay follow',
        (tester) async {
      final env = await _pump(tester);
      await tester.tap(_inPane(find.text('Sugar 2kg (Mumias)')));
      await tester.pumpAndSettle();
      await tester.tap(_inPane(find.text('Sugar 2kg (Mumias)')));
      await tester.pumpAndSettle();
      expect(env.cart.state.items.single.quantity, 2);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ticket-total'))).data,
        'KES 660',
      );
      expect(find.text('Pay KES 660'), findsOneWidget);
      expect(find.text('2 on ticket'), findsOneWidget);
    });

    testWidgets('type, Enter adds the first match; arrows move the highlight',
        (tester) async {
      final env = await _pump(tester);
      await tester.enterText(find.byKey(const ValueKey('sell-search')), 'mil');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(env.cart.state.items.single.productName, contains('Fresh milk'));
      // The search is cleared and still focused for the next item.
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sell-search')))
            .controller!
            .text,
        isEmpty,
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // Down, Down from nothing highlights row 0 then row 1 (Fresh milk).
      expect(env.cart.state.items.length, 1);
      expect(env.cart.state.items.single.quantity, 2);
    });

    testWidgets('out of stock is marked and refused with a visible reason',
        (tester) async {
      final env = await _pump(tester);
      expect(_inPane(find.text('Out of stock')), findsOneWidget);
      await tester.tap(_inPane(find.text('Cooking oil 1L (Elianto)')));
      await tester.pumpAndSettle();
      expect(env.cart.state.items, isEmpty);
      expect(find.textContaining('out of stock'), findsWidgets);
    });

    testWidgets('list or tiles, remembered', (tester) async {
      await _pump(tester);
      await tester.tap(find.byTooltip('Tiles'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sell_product_view'), 'grid');
      expect(find.byType(GridView), findsOneWidget);
    });
  });

  group('ticket keyboard and steppers', () {
    testWidgets('+ and - on the stepper, typing a quantity, remove',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 2);
      await tester.pumpAndSettle();
      expect(env.cart.state.items.length, 2);

      await tester.tap(find.byTooltip('One more (+)').first);
      await tester.pumpAndSettle();
      expect(env.cart.state.items.first.quantity, 3);

      await tester.tap(find.byKey(const ValueKey('line-qty')).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('line-qty-field')), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(env.cart.state.items.first.quantity, 5);

      await tester.tap(
        find.descendant(
          of: find.byType(SellTicketPanel),
          matching: find.text(env.cart.state.items.last.productName),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(env.cart.state.items.length, 1);
    });

    testWidgets('Up/Down select a line and +/- change it (Ctrl+3 focus)',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 3);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      // Selection starts on the last line; Up moves to the middle one.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(env.cart.state.items[1].quantity, 2);
      expect(env.cart.state.items[0].quantity, 2);
      expect(env.cart.state.items[2].quantity, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('F8 asks first and Enter keeps the ticket', (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 2);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pumpAndSettle();
      expect(find.text('Void this ticket?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Void this ticket?'), findsNothing);
      expect(env.cart.state.items.length, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('void-confirm')));
      await tester.pumpAndSettle();
      expect(env.cart.state.items, isEmpty);
    });

    testWidgets('F7 opens the discount and applies it', (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('discount-field')), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(env.cart.state.discountPercent, 10);
      expect(find.text('Discount 10%'), findsOneWidget);
    });

    testWidgets(
        'a cashier without sales.discount cannot apply a manual discount',
        (tester) async {
      final env = await _pump(tester, permissions: const ['sales.create']);
      await _fillTicket(env, lines: 1);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('discount-field')), findsNothing);
      expect(env.cart.state.manualDiscount, 0);
      expect(
        find.text('You do not have permission to apply discounts.'),
        findsOneWidget,
      );
    });

    testWidgets('F3 picks a customer, F1 shows the shortcuts', (tester) async {
      final env = await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.text('Mama Njeri'), findsOneWidget);
      await tester.tap(find.text('Mama Njeri'));
      await tester.pumpAndSettle();
      expect(env.cart.state.customerName, 'Mama Njeri');

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('F9'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsNothing);
    });

    testWidgets(
        'Sell does not reveal saved customer PII without customers.view',
        (tester) async {
      await _pump(
        tester,
        permissions: const ['sales.create', 'customers.create'],
        beforePump: (env) =>
            env.cart.setCustomer('c1', customerName: 'Mama Njeri'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();

      expect(find.text('Mama Njeri'), findsNothing);
      expect(find.text('0722000111'), findsNothing);
      expect(find.text('Owes KES 450'), findsNothing);
      expect(find.text('Walk-in customer'), findsWidgets);
    });

    testWidgets('Sell still shows saved customers with customers.view',
        (tester) async {
      final env = await _pump(tester, permissions: const [
        'sales.create',
        'customers.view',
      ]);

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();

      expect(find.text('Mama Njeri'), findsOneWidget);
      expect(find.text('0722000111'), findsOneWidget);
      expect(find.text('Owes KES 450'), findsOneWidget);
      await tester.tap(find.text('Mama Njeri'));
      await tester.pumpAndSettle();
      expect(env.cart.state.customerName, 'Mama Njeri');
    });

    testWidgets(
        'desktop customer picker clears PII and drops late results when customers.view is revoked',
        (tester) async {
      final env = await _pump(tester);
      final pending = Completer<List<Map<String, dynamic>>>();
      env.host.searchCompleter = pending;

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      expect(env.host.searchCalls, 1);

      env.permissions.state =
          RolePermissions(const ['sales.create', 'customers.create']);
      await tester.pump();

      pending.complete([
        {
          'id': 'c1',
          'name': 'Mama Njeri',
          'phone': '0722000111',
          'balance': 450,
        },
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Mama Njeri'), findsNothing);
      expect(find.text('0722000111'), findsNothing);
      expect(env.cart.state.customerId, isNull);
      expect(env.cart.state.customerName, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('barcode scanner', () {
    testWidgets('a scan adds the product, whichever field has focus',
        (tester) async {
      final env = await _pump(tester);
      await _scan(tester, '6001234000011');
      expect(env.cart.state.items.single.productName, 'Sugar 2kg (Mumias)');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sell-search')))
            .controller!
            .text,
        isEmpty,
      );
      // A second scan of the same code within 300 ms is one more, not a line.
      await _scan(tester, '6001234000011');
      expect(env.cart.state.items.single.quantity, 2);
    });

    testWidgets('an unknown barcode shows a banner, never silence',
        (tester) async {
      final env = await _pump(tester);
      await _scan(tester, '9999999999999');
      expect(env.cart.state.items, isEmpty);
      expect(find.text('Barcode 9999999999999 not found.'), findsOneWidget);
      expect(find.text('Add product'), findsOneWidget);
      expect(find.text('Search by name'), findsOneWidget);
      await tester.tap(find.text('Add product'));
      await tester.pump();
      expect(env.addProductCodes, ['9999999999999']);
    });

    testWidgets('the status bar shows the scanner and flashes on a scan',
        (tester) async {
      await _pump(tester);
      expect(find.text('Scanner ready'), findsOneWidget);
      await _scan(tester, '6001234000011');
      await tester.pump();
      expect(find.textContaining('Scanned 6001234000011'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Scanner ready'), findsOneWidget);
    });

    testWidgets('leaving the page removes the scanner readout', (tester) async {
      await _pump(tester);
      expect(
        DesktopStatusRegistry.entries.value.any((e) => e.id == 'scanner'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      expect(
        DesktopStatusRegistry.entries.value.any((e) => e.id == 'scanner'),
        isFalse,
      );
    });
  });

  group('payment in place', () {
    testWidgets('a pre-discounted cart cannot be saved without sales.discount',
        (tester) async {
      final env = await _pump(tester, permissions: const ['sales.create']);
      await _fillTicket(env, lines: 1);
      env.cart.setDiscountPercent(10);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();

      expect(env.payments.cashSales, isEmpty);
      expect(env.sold, isEmpty);
      expect(env.cart.state.manualDiscount, greaterThan(0));
      expect(
        find.text('You do not have permission to apply discounts.'),
        findsOneWidget,
      );
    });

    testWidgets('a manager can save a manually discounted sale',
        (tester) async {
      final env = await _pump(tester, permissions: const [
        'sales.create',
        'sales.discount',
      ]);
      await _fillTicket(env, lines: 1);
      env.cart.setDiscountPercent(10);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();

      expect(env.payments.cashSales.single.amount, 594);
      expect(env.sold.single.status, CheckoutStatus.sold);
      expect(env.cart.state.items, isEmpty);
    });

    testWidgets(
        'a manually discounted line cannot be saved without sales.discount',
        (tester) async {
      final env = await _pump(tester, permissions: const ['sales.create']);
      await _fillTicket(env, lines: 1);
      expect(env.cart.updateItemDiscount('11', 66).success, isTrue);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();

      expect(env.payments.cashSales, isEmpty);
      expect(env.sold, isEmpty);
      expect(env.cart.state.items.single.discount, 66);
      expect(
        find.text('You do not have permission to apply discounts.'),
        findsOneWidget,
      );
    });

    testWidgets('an approved coupon still saves without sales.discount',
        (tester) async {
      final env = await _pump(tester, permissions: const ['sales.create']);
      await _fillTicket(env, lines: 1);
      env.cart.applyCoupon(const Coupon(
        code: 'OWNER10',
        kind: CouponKind.percent,
        value: 10,
      ));
      expect(env.cart.state.manualDiscount, 0);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();

      expect(env.payments.cashSales.single.amount, 594);
      expect(env.sold.single.status, CheckoutStatus.sold);
      expect(env.cart.state.items, isEmpty);
    });

    testWidgets('F9 swaps the ticket for the payment panel; Esc comes back',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 2);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-due')), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-button')), findsNothing);
      expect(find.text('Back to ticket'), findsOneWidget);
      // The products stay on the left.
      expect(find.byKey(const ValueKey('sell-search')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-due')), findsNothing);
    });

    testWidgets('cash: exact by default, chips, change due, then complete',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 2); // 2 x 330 + 65 = 725
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('cash-field'));
      expect(tester.widget<TextField>(field).controller!.text, '725');
      expect(find.text('Exact'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-remaining')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cash-chip-1000')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('payment-change'))).data,
        'KES 275',
      );

      // Short cash is refused with a reason and the button is off.
      await tester.enterText(field, '500');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cash-short')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();
      expect(env.payments.cashSales, isEmpty);

      await tester.enterText(field, '1000');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(env.payments.cashSales.single, (amount: 725.0, tendered: 1000.0));
      expect(env.sold.single.saleId, 'sale-cash-1');
      expect(env.sold.single.changeDue, 275);
      expect(env.cart.state.items, isEmpty);
    });

    testWidgets('Ctrl+number chooses how they pay; credit needs a customer',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      // Focus is in the cash field, so plain digits type; Ctrl+3 switches.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Choose customer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mama Njeri'));
      await tester.pumpAndSettle();
      expect(env.cart.state.customerName, 'Mama Njeri');
      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pumpAndSettle();
      expect(env.payments.creditSales, [660.0]);
      expect(env.sold.single.saleId, 'sale-credit-1');
    });

    testWidgets(
        'M-Pesa: waiting, then "not confirmed" (never "failed"), no auto-resend',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 1);
      env.cart.setCustomer('c1', customerName: 'Mama Njeri');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      await tester.tap(find.text('M-Pesa'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('mpesa-phone')))
            .controller!
            .text,
        '0712345678',
      );

      await tester.tap(find.byKey(const ValueKey('payment-primary')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('mpesa-waiting')), findsOneWidget);
      expect(
          find.textContaining('Request sent to 0712 *** 678'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.textContaining('Still waiting'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const ValueKey('mpesa-pending')), findsOneWidget);
      expect(find.text('Not confirmed yet'), findsOneWidget);
      expect(find.textContaining('failed'), findsNothing);
      expect(find.text('Check again'), findsOneWidget);
      // Nothing re-sends by itself.
      await tester.pump(const Duration(seconds: 90));
      expect(env.payments.mpesaCalls, 1);
      // The other methods stay locked until it is settled.
      await tester.tap(find.text('Cash'));
      await tester.pump();
      expect(find.byKey(const ValueKey('mpesa-pending')), findsOneWidget);
    });

    testWidgets(
        'desktop payment panel discards a late customer phone after customers.view is revoked',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 1);
      env.cart.setCustomer('c1', customerName: 'Mama Njeri');
      env.host.customerPhoneCompleter = Completer<String?>();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      await tester.tap(find.text('M-Pesa'));
      await tester.pump();
      expect(env.host.customerPhoneCalls, 1);

      env.permissions.state =
          RolePermissions(const ['sales.create', 'customers.create']);
      await tester.pump();
      env.host.customerPhoneCompleter!.complete('0712345678');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('mpesa-phone')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('held sales', () {
    testWidgets('the ticket can hold a sale and open saved sales',
        (tester) async {
      final env = await _pump(tester, heldSalesCount: 2);
      await _fillTicket(env, lines: 1);
      await tester.pumpAndSettle();

      final hold = find.byTooltip('Hold sale (Ctrl+H)');
      final recall = find.byTooltip('Held sales (2) (Ctrl+Shift+H)');
      expect(hold, findsOneWidget);
      expect(recall, findsOneWidget);

      await tester.tap(recall);
      await tester.tap(hold);
      expect(env.heldSalesCalls, 1);
      expect(env.holdCalls, 1);
    });

    testWidgets('shortcut help describes holding and recalling sales',
        (tester) async {
      await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();

      expect(find.text('Hold the current sale'), findsOneWidget);
      expect(find.text('Open held sales'), findsOneWidget);
    });

    testWidgets('Ctrl+H holds and Ctrl+Shift+H opens held sales',
        (tester) async {
      final env = await _pump(tester);
      await _fillTicket(env, lines: 1);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(env.holdCalls, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(env.heldSalesCalls, 1);
    });
  });

  group('layout budget', () {
    testWidgets('at 1093x566 with 6 lines Pay stays on screen', (tester) async {
      final env = await _pump(tester, size: const Size(1093, 566));
      await _fillTicket(env);
      await tester.pumpAndSettle();
      final pay = tester.getRect(find.byKey(const ValueKey('pay-button')));
      expect(pay.bottom, lessThanOrEqualTo(566 - 24));
      expect(pay.height, 56);
      // The ticket is 340 wide below 1200.
      final panel = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('pay-button')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(panel.width, lessThanOrEqualTo(340));
      expect(tester.takeException(), isNull);
    });

    testWidgets('payment panel keeps its button visible at 1093x566',
        (tester) async {
      final env = await _pump(tester, size: const Size(1093, 566));
      await _fillTicket(env);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      final primary =
          tester.getRect(find.byKey(const ValueKey('payment-primary')));
      expect(primary.bottom, lessThanOrEqualTo(566 - 24));
      expect(tester.takeException(), isNull);
    });
  });

  // ─── Pictures for review ───

  const sizes = {
    '1366x768': Size(1366, 768),
    '1093x566': Size(1093, 566),
    '1920x1080': Size(1920, 1080),
  };

  for (final dark in [false, true]) {
    for (final entry in sizes.entries) {
      final tag = '${dark ? 'dark' : 'light'}-${entry.key}';
      final big = entry.key == '1920x1080';

      testWidgets('shot ticket with 6 lines $tag', (tester) async {
        final key = GlobalKey();
        final env =
            await _pump(tester, size: entry.value, dark: dark, boundary: key);
        await _fillTicket(env);
        await tester.pumpAndSettle();
        await saveShot(tester, key, 'build/shots/sell-ticket-$tag.png');
        expect(tester.takeException(), isNull);
      });

      if (big) continue;

      testWidgets('shot empty ticket $tag', (tester) async {
        final key = GlobalKey();
        await _pump(tester, size: entry.value, dark: dark, boundary: key);
        await tester.pumpAndSettle();
        await saveShot(tester, key, 'build/shots/sell-empty-$tag.png');
      });

      testWidgets('shot tiles with out of stock $tag', (tester) async {
        final key = GlobalKey();
        final env = await _pump(tester,
            size: entry.value, dark: dark, view: 'grid', boundary: key);
        await _fillTicket(env, lines: 3);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await saveShot(tester, key, 'build/shots/sell-tiles-$tag.png');
      });

      testWidgets('shot unknown barcode $tag', (tester) async {
        final key = GlobalKey();
        final env =
            await _pump(tester, size: entry.value, dark: dark, boundary: key);
        await _fillTicket(env, lines: 3);
        await _scan(tester, '6009876543210');
        await tester.pumpAndSettle();
        await saveShot(
            tester, key, 'build/shots/sell-unknown-barcode-$tag.png');
      });

      testWidgets('shot payment cash $tag', (tester) async {
        final key = GlobalKey();
        final env =
            await _pump(tester, size: entry.value, dark: dark, boundary: key);
        await _fillTicket(env);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cash-chip-2000')));
        await tester.pumpAndSettle();
        await saveShot(tester, key, 'build/shots/sell-payment-cash-$tag.png');
      });

      testWidgets('shot payment mpesa waiting $tag', (tester) async {
        final key = GlobalKey();
        final env =
            await _pump(tester, size: entry.value, dark: dark, boundary: key);
        await _fillTicket(env);
        env.cart.setCustomer('c1', customerName: 'Mama Njeri');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pumpAndSettle();
        await tester.tap(find.text('M-Pesa'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('payment-primary')));
        await tester.pump(const Duration(seconds: 17));
        await saveShot(tester, key, 'build/shots/sell-payment-mpesa-$tag.png');
        // Let the fake request finish so no timer outlives the test.
        await tester.pump(const Duration(seconds: 6));
      });
    }
  }
}
