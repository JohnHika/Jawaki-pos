import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart' hide CartItem;
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/responsive/device_class.dart';
import 'package:axon_pos/core/responsive/two_pane.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/payment_provider.dart';
import 'package:axon_pos/features/sales/presentation/screens/pos_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ticket = ValueKey('sell-ticket-pane');

Map<String, dynamic> _product(String id, String name, {double price = 100}) => {
      'id': id,
      'name': name,
      'sku': 'SKU-$id',
      'price': price,
      'unit': 'piece',
      'stock': 20,
      'trackInventory': true,
      'pricingTiers': const <Map<String, dynamic>>[],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TwoPanePlan', () {
    test('the ticket gets a third of the page, kept between 300 and 420', () {
      final mid = TwoPanePlan.compute(size: const Size(1000, 700));
      expect(mid.axis, Axis.horizontal);
      expect(mid.secondary, 360);
      expect(mid.primary, 640);
      expect(mid.atFold, isFalse);

      expect(TwoPanePlan.compute(size: const Size(560, 700)).secondary, 300);
      expect(TwoPanePlan.compute(size: const Size(1600, 900)).secondary, 420);
    });

    test('a vertical fold puts the panes on either side of it', () {
      final plan = TwoPanePlan.compute(
        size: const Size(800, 900),
        fold: const FoldInfo(
          bounds: Rect.fromLTWH(400, 0, 0, 900),
          posture: FoldPosture.flat,
        ),
      );
      expect(plan.atFold, isTrue);
      expect(plan.primary, 400);
      expect(plan.secondary, 400);
      expect(plan.gap, 0);
    });

    test('a wide hinge leaves its width empty between the panes', () {
      final plan = TwoPanePlan.compute(
        size: const Size(804, 900),
        fold: const FoldInfo(
          bounds: Rect.fromLTWH(360, 0, 84, 900),
          posture: FoldPosture.book,
        ),
      );
      expect(plan.primary, 360);
      expect(plan.gap, 84);
      expect(plan.secondary, 360);
    });

    test('a fold too near an edge is ignored', () {
      final plan = TwoPanePlan.compute(
        size: const Size(800, 900),
        fold: const FoldInfo(
          bounds: Rect.fromLTWH(100, 0, 0, 900),
          posture: FoldPosture.flat,
        ),
      );
      expect(plan.atFold, isFalse);
      expect(plan.secondary, closeTo(300, 0.001));
    });

    test('the fold is read relative to where the page starts (a side rail)', () {
      final plan = TwoPanePlan.compute(
        size: const Size(728, 900),
        origin: const Offset(72, 56),
        fold: const FoldInfo(
          bounds: Rect.fromLTWH(472, 0, 0, 956),
          posture: FoldPosture.flat,
        ),
      );
      expect(plan.atFold, isTrue);
      expect(plan.primary, 400);
      expect(plan.secondary, 328);
    });

    test('a half-open laptop posture stacks browse over sell', () {
      final plan = TwoPanePlan.compute(
        size: const Size(800, 844),
        origin: const Offset(0, 56),
        fold: const FoldInfo(
          bounds: Rect.fromLTWH(0, 440, 800, 20),
          posture: FoldPosture.tabletop,
        ),
      );
      expect(plan.axis, Axis.vertical);
      expect(plan.atFold, isTrue);
      expect(plan.primary, 384);
      expect(plan.gap, 20);
      expect(plan.secondary, 844 - 384 - 20);
    });

    test('a page too short for a stacked split keeps its side-by-side layout',
        () {
      final plan = TwoPanePlan.compute(
        size: const Size(800, 400),
        fold: const FoldInfo(
          bounds: Rect.fromLTWH(0, 200, 800, 20),
          posture: FoldPosture.tabletop,
        ),
      );
      expect(plan.axis, Axis.horizontal);
      expect(plan.atFold, isFalse);
    });
  });

  group('FoldInfo', () {
    test('reads a vertical hinge and ignores cut-outs', () {
      final info = FoldInfo.fromFeatures(const [
        DisplayFeature(
          bounds: Rect.fromLTWH(10, 0, 30, 40),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
        DisplayFeature(
          bounds: Rect.fromLTWH(400, 0, 20, 900),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ]);
      expect(info.hasFold, isTrue);
      expect(info.isVertical, isTrue);
      expect(info.posture, FoldPosture.book);
      expect(FoldInfo.fromFeatures(const []).hasFold, isFalse);
    });

    test('a horizontal half-open fold is tabletop; flat is flat', () {
      expect(
        FoldInfo.fromFeatures(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 400, 800, 0),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]).posture,
        FoldPosture.tabletop,
      );
      expect(
        FoldInfo.fromFeatures(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(400, 0, 0, 800),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ]).posture,
        FoldPosture.flat,
      );
    });
  });

  group('Sell on phone, tablet and foldable', () {
    late _Harness harness;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // A tablet or phone, not a Windows computer, whatever runs the tests.
      DesktopLayout.debugIsDesktopPlatform = false;
    });

    tearDown(() async {
      DesktopLayout.debugIsDesktopPlatform = null;
      await harness.dispose();
    });

    void sizeTo(WidgetTester tester, double width, double height) {
      tester.view.physicalSize = Size(width * 2, height * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }

    testWidgets('a phone keeps one column and the Review sale bar',
        (tester) async {
      sizeTo(tester, 390, 844);
      harness = await _Harness.pump(tester);

      expect(find.byKey(_ticket), findsNothing);
      await tester.tap(find.byKey(const ValueKey('quick-add')).first);
      await tester.pumpAndSettle();

      expect(harness.cart.state.items, hasLength(1));
      expect(find.text('Review sale'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      (name: 'tablet landscape', w: 1024.0, h: 768.0),
      (name: 'tablet portrait', w: 800.0, h: 1280.0),
      (name: 'foldable opened up', w: 840.0, h: 900.0),
      (name: 'small tablet', w: 600.0, h: 960.0),
    ]) {
      testWidgets('${size.name} (${size.w.toInt()}x${size.h.toInt()}) shows the '
          'products beside the sale ticket', (tester) async {
        sizeTo(tester, size.w, size.h);
        harness = await _Harness.pump(tester);

        expect(find.byKey(_ticket), findsOneWidget);
        expect(find.text('Nothing in this sale yet'), findsOneWidget);
        expect(find.text('Review sale'), findsNothing);
        final ticket = tester.getRect(find.byKey(_ticket));
        final firstProduct = tester.getRect(find.text('Maize flour').first);
        expect(firstProduct.right, lessThanOrEqualTo(ticket.left + 0.5),
            reason: 'the products are on the left, the ticket on the right');
        expect(ticket.width, inInclusiveRange(280, 420));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a foldable folded shut (cover screen) is a phone',
        (tester) async {
      sizeTo(tester, 360, 800);
      harness = await _Harness.pump(tester);

      expect(find.byKey(_ticket), findsNothing);
      expect(find.text('Maize flour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap on a product lands in the ticket with a visible check',
        (tester) async {
      sizeTo(tester, 1024, 768);
      harness = await _Harness.pump(tester);

      await tester.tap(find.byKey(const ValueKey('quick-add')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.cart.state.itemCount, 1);
      expect(
        find.descendant(
          of: find.byKey(_ticket),
          matching: find.text('Maize flour'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ticket-count'))).data,
        '1 item',
      );
      expect(
        find.descendant(
          of: find.byKey(_ticket),
          matching: find.byKey(const ValueKey('alive-done')),
        ),
        findsOneWidget,
        reason: 'the header icon turns into a check when something is added',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.descendant(
          of: find.byKey(_ticket),
          matching: find.byKey(const ValueKey('alive-done')),
        ),
        findsNothing,
        reason: 'and goes back to the receipt icon a moment later',
      );
    });

    testWidgets('the ticket changes the sale: more, then clear is offered',
        (tester) async {
      sizeTo(tester, 1024, 768);
      harness = await _Harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey('quick-add')).first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.descendant(
        of: find.byKey(_ticket),
        matching: find.bySemanticsLabel('Increase quantity'),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(harness.cart.state.itemCount, 2);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ticket-count'))).data,
        '2 items',
      );
      expect(find.byTooltip('Clear sale'), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-hold')), findsOneWidget);
    });

    testWidgets('the sale and the search survive the screen changing shape',
        (tester) async {
      sizeTo(tester, 840, 900);
      harness = await _Harness.pump(tester);
      await tester.enterText(find.byType(TextField), 'maize');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('quick-add')).first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(_ticket), findsOneWidget);

      // The foldable is folded shut: the ticket collapses into the bar.
      sizeTo(tester, 360, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(_ticket), findsNothing);
      expect(harness.cart.state.itemCount, 1);
      expect(find.text('Review sale'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'maize',
          reason: 'the product browser keeps what was typed');

      // ...and opened again: the ticket is back with the same sale in it.
      sizeTo(tester, 840, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(_ticket), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_ticket),
          matching: find.text('Maize flour'),
        ),
        findsOneWidget,
      );
      expect(harness.cart.state.itemCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an opened foldable puts the products and the ticket on '
        'either side of the hinge', (tester) async {
      sizeTo(tester, 840, 900);
      // A 12 px hinge down the middle (the window reports logical pixels).
      tester.view.displayFeatures = [
        const DisplayFeature(
          bounds: Rect.fromLTWH(414, 0, 12, 900),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      harness = await _Harness.pump(tester);
      await tester.pumpAndSettle();

      final ticket = tester.getRect(find.byKey(_ticket));
      expect(ticket.left, closeTo(426, 1), reason: 'starts after the hinge');
      expect(ticket.right, closeTo(840, 1));
      final products = tester.getRect(find.text('Maize flour').first);
      expect(products.right, lessThanOrEqualTo(414 + 1),
          reason: 'nothing is drawn under the hinge');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a foldable half open like a laptop browses above, sells below',
        (tester) async {
      sizeTo(tester, 800, 900);
      tester.view.displayFeatures = [
        const DisplayFeature(
          bounds: Rect.fromLTWH(0, 440, 800, 20),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      harness = await _Harness.pump(tester);
      await tester.pumpAndSettle();

      final ticket = tester.getRect(find.byKey(_ticket));
      expect(ticket.top, closeTo(460, 1), reason: 'below the hinge');
      expect(ticket.width, closeTo(800, 1));
      final products = tester.getRect(find.text('Maize flour').first);
      expect(products.bottom, lessThanOrEqualTo(440 + 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ticket wears the shop profile colour', (tester) async {
      sizeTo(tester, 1024, 768);
      harness = await _Harness.pump(
        tester,
        layoutUser: const {
          'tenant': {
            'settings': {
              'businessLayout': {'profileId': 'kamukunji_counter'},
            },
          },
        },
      );
      await tester.tap(find.byKey(const ValueKey('quick-add')).first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final accent =
          businessLayoutFromUser(const {
        'tenant': {
          'settings': {
            'businessLayout': {'profileId': 'kamukunji_counter'},
          },
        },
      }).preset.accent;
      expect(accent, isNotNull);
      final charge = tester.widget<FilledButton>(
        find.byKey(const ValueKey('ticket-charge')),
      );
      expect(charge.style!.backgroundColor!.resolve(const {}), accent);
    });

    testWidgets('a phone held on its side gets two panes too', (tester) async {
      sizeTo(tester, 844, 390);
      harness = await _Harness.pump(tester);

      expect(find.byKey(_ticket), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The Sell screen with an in-memory shop: three products, a cart, no network.
class _Harness {
  _Harness._(this.cart, this._close, this._closeConnectivity);

  final CartNotifier cart;
  final Future<void> Function() _close;
  final Future<void> Function() _closeConnectivity;

  static Future<_Harness> pump(
    WidgetTester tester, {
    Map<String, dynamic>? layoutUser,
  }) async {
    getIt.pushNewScope();
    final auth = _TestAuth();
    getIt.registerSingleton<AuthService>(auth);
    final storage = _TestStorage();
    final database = _TestDatabase(storage);
    final connectivity = _TestConnectivity();
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<StorageService>(storage);
    getIt.registerSingleton<ConnectivityService>(connectivity);
    final cart = CartNotifier(
      stockValidator: (_, quantity) async => {
        'available': true,
        'message': 'ok',
        'currentStock': 999,
      },
    );
    final products = [
      _product('1', 'Maize flour'),
      _product('2', 'Sugar 1kg', price: 180),
      _product('3', 'Cooking oil', price: 350),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cartProvider.overrideWith((ref) => cart),
        paymentProvider.overrideWith((ref) => _TestPayments()),
        permissionsProvider.overrideWithValue(
          RolePermissions(const ['sales.create', 'sales.discount']),
        ),
        businessLayoutProvider
            .overrideWithValue(businessLayoutFromUser(layoutUser)),
        notificationInboxProvider.overrideWith((ref) => _TestInbox()),
        filteredProductsProvider
            .overrideWith((ref, params) => Stream.value(products)),
        categoriesProvider.overrideWith((ref) async => const []),
        favoriteProductsProvider.overrideWith((ref) async => const []),
        favoritesProvider
            .overrideWith((ref) => FavoritesNotifier.emptyForTesting()),
        parkedSalesProvider.overrideWith((ref) => ParkedSalesNotifier(
              storage: storage,
              tenantId: null,
              branchId: null,
              isLocalWorkspace: true,
            )),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const POSScreen()),
    ));
    await tester.pumpAndSettle();
    return _Harness._(cart, () async {
      await database.close();
      await getIt.popScope();
      await auth.close();
    }, connectivity.close);
  }

  Future<void> dispose() async {
    await _closeConnectivity();
    await _close();
  }
}

class _TestDatabase extends AppDatabase {
  _TestDatabase(StorageService storage)
      : super.forTesting(NativeDatabase.memory(), storage);
}

class _TestAuth implements AuthService {
  final _status = StreamController<AuthStatus>.broadcast();

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => true;
  @override
  double get taxRatePercent => 0;
  @override
  bool get showTaxOnReceipt => false;
  @override
  Map<String, dynamic>? get currentUser => const {
        'authMode': 'local',
        'tenantId': 'tenant-1',
        'branchId': 'branch-1',
        'permissions': ['sales.create'],
      };
  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;
  Future<void> close() => _status.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestStorage implements StorageService {
  @override
  Future<String?> getSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async =>
      null;
  @override
  String? getHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) =>
      null;
  @override
  Future<void> saveSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
    required String snapshot,
  }) async {}
  @override
  Future<void> saveHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
    required String snapshot,
  }) async {}
  @override
  Future<void> clearLegacyHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async {}
  @override
  String? getRecordedPaymentRulesJson() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestConnectivity implements ConnectivityService {
  final _status = StreamController<ConnectionStatus>.broadcast();
  @override
  ConnectionStatus get currentStatus => ConnectionStatus.online;
  @override
  Stream<ConnectionStatus> get statusStream => _status.stream;
  Future<void> close() => _status.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPayments extends StateNotifier<PaymentState>
    implements PaymentNotifier {
  _TestPayments() : super(const PaymentState());
  @override
  bool get hasUnresolvedMerchantPayment => state.hasUnresolvedMerchantPayment;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _TestInbox() : super(const NotificationInboxState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
