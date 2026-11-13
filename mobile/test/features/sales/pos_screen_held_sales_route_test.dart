import 'dart:async';
import 'dart:convert';

import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/payment_provider.dart';
import 'package:axon_pos/features/sales/presentation/screens/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';

const _tenantId = 'test-tenant';
const _branchId = 'test-branch';
const _restoreWarning =
    'Held sales are readable, but another saved copy contains entries that could not be safely matched. Both copies were kept; do not clear app data.';

const _navItems = <DesktopNavItem>[
  DesktopNavItem(
    icon: Icons.point_of_sale_outlined,
    activeIcon: Icons.point_of_sale_rounded,
    label: 'Sell',
    path: '/',
    group: DesktopNavGroup.workspace,
  ),
];

const _settingsItem = DesktopNavItem(
  icon: Icons.settings_outlined,
  activeIcon: Icons.settings_rounded,
  label: 'Settings',
  path: '/settings',
  group: DesktopNavGroup.more,
);

void main() {
  setUpAll(loadShotFonts);

  testWidgets(
    'routed POS shows held-sale restore state and opens the provider-backed list',
    (tester) async {
      final secureRead = Completer<String?>();
      final storage = _MemoryStorage(
        pendingSecureRead: secureRead,
        legacySnapshot: _heldSalesSnapshot('legacy-copy', 'Older copy'),
      );
      final harness = await _pumpRoutedPos(tester, storage: storage);

      expect(tester.takeException(), isNull);
      expect(
        find.byTooltip('Held sales loading (Ctrl+Shift+H)'),
        findsOneWidget,
      );

      secureRead.complete(_heldSalesSnapshot('secure-sale', 'Prior sale'));
      await tester.pumpAndSettle();

      final providerContainer = ProviderScope.containerOf(
        tester.element(find.byType(POSScreen)),
      );
      expect(providerContainer.read(parkedSalesProvider), hasLength(1));
      expect(
        find.byTooltip('Held sales need attention (Ctrl+Shift+H)'),
        findsOneWidget,
      );
      expect(find.textContaining('another saved copy contains entries'),
          findsOneWidget);
      final heldButton = find.byTooltip(
        'Held sales need attention (Ctrl+Shift+H)',
      );
      final badge = tester.widget<Badge>(
        find.descendant(of: heldButton, matching: find.byType(Badge)),
      );
      expect((badge.label! as Text).data, '1');

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('Held sales'), findsOneWidget);
      expect(find.text('Held sale'), findsOneWidget);
      expect(find.text(_restoreWarning), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );

  testWidgets(
    'old held-sale customer labels and discard prompts are hidden without customers.view',
    (tester) async {
      final storage = _MemoryStorage()
        ..secureSnapshot = _heldSalesSnapshot('old-sale', 'Private Customer');
      final harness = await _pumpRoutedPos(tester, storage: storage);
      addTearDown(() async => harness.dispose(tester));

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Held sales (1) (Ctrl+Shift+H)'));
      await tester.pumpAndSettle();

      expect(find.text('Private Customer'), findsNothing);
      expect(find.text('Held sale'), findsOneWidget);
      expect(find.byTooltip('Resume held sale'), findsOneWidget);
      expect(find.byTooltip('Delete held sale'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete held sale'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Discard this held sale? This sale will be permanently removed.'),
        findsOneWidget,
      );
      expect(find.textContaining('Private Customer'), findsNothing);
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(POSScreen)),
      );
      expect(container.read(parkedSalesProvider), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held-sale discard confirmation remains generic even with customers.view',
    (tester) async {
      final storage = _MemoryStorage()
        ..secureSnapshot = _heldSalesSnapshot('old-sale', 'Private Customer');
      final harness = await _pumpRoutedPos(
        tester,
        storage: storage,
        permissions: const ['customers.view'],
      );
      addTearDown(() async => harness.dispose(tester));

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Held sales (1) (Ctrl+Shift+H)'));
      await tester.pumpAndSettle();
      expect(find.text('Private Customer'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete held sale'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Discard this held sale? This sale will be permanently removed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Discard "Private Customer"'), findsNothing);
    },
  );

  testWidgets(
      'routed POS hold control parks the current cart and updates count',
      (tester) async {
    final storage = _MemoryStorage();
    final cart = CartNotifier(
      stockValidator: (_, __) async => {
        'available': true,
        'stockBlocked': false,
        'message': 'ok',
        'currentStock': 10,
      },
    );
    await cart.addItem(
      productId: 'rice-1',
      productName: 'Rice 1kg',
      sku: 'RICE-1',
      unitPrice: 120,
      quantity: 1,
      saleUnit: 'piece',
      saleQuantity: 1,
      unitConversionFactor: 1,
    );
    final harness = await _pumpRoutedPos(
      tester,
      storage: storage,
      cart: cart,
    );

    expect(tester.takeException(), isNull);
    expect(cart.state.itemCount, 1);
    expect(find.byTooltip('Hold sale (Ctrl+H)'), findsOneWidget);

    await tester.tap(find.byTooltip('Hold sale (Ctrl+H)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final providerContainer = ProviderScope.containerOf(
      tester.element(find.byType(POSScreen)),
    );
    expect(cart.state.items, isEmpty);
    expect(providerContainer.read(parkedSalesProvider), hasLength(1));
    expect(storage.secureSnapshot, isNotNull);
    expect(
      (jsonDecode(storage.secureSnapshot!) as Map<String, dynamic>)['sales'],
      hasLength(1),
    );
    expect(find.text('Sale held'), findsOneWidget);
    expect(find.byTooltip('Held sales (1) (Ctrl+Shift+H)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });
}

Future<_PosHarness> _pumpRoutedPos(
  WidgetTester tester, {
  required _MemoryStorage storage,
  CartNotifier? cart,
  List<String> permissions = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  useWindow(tester, const Size(1366, 768));
  DesktopLayout.debugIsDesktopPlatform = true;

  final auth = _LocalAuthService(permissions: permissions);
  final connectivity = _TestConnectivity();
  final activeCart = cart ??
      CartNotifier(
        stockValidator: (_, __) async => {
          'available': true,
          'stockBlocked': false,
          'message': 'ok',
          'currentStock': 10,
        },
      );

  getIt.pushNewScope();
  getIt.registerSingleton<AuthService>(auth);
  getIt.registerSingleton<ConnectivityService>(connectivity);
  getIt.registerSingleton<StorageService>(storage);

  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => DesktopShell(
          items: _navItems,
          settingsItem: _settingsItem,
          location: state.uri.path,
          onNavigate: router.go,
          companyName: 'Test shop',
          userName: 'Test cashier',
          role: 'Cashier',
          version: 'test',
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/',
            name: 'pos',
            builder: (context, state) => const POSScreen(),
          ),
        ],
      ),
    ],
  );

  final harness = _PosHarness(
    router: router,
    auth: auth,
    connectivity: connectivity,
    cart: activeCart,
  );
  addTearDown(() async {
    await harness.dispose(tester);
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartProvider.overrideWith((ref) => activeCart),
        paymentProvider.overrideWith((ref) => _TestPayments()),
        businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
        notificationInboxProvider.overrideWith((ref) => _TestInbox()),
        filteredProductsProvider.overrideWith(
          (ref, params) => Stream.value(const <Map<String, dynamic>>[]),
        ),
        categoriesProvider.overrideWith(
          (ref) async => const <Map<String, dynamic>>[],
        ),
        favoriteProductsProvider.overrideWith(
          (ref) async => const <Map<String, dynamic>>[],
        ),
        favoritesProvider.overrideWith(
          (ref) => FavoritesNotifier.emptyForTesting(),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return harness;
}

String _heldSalesSnapshot(String id, String label) => jsonEncode({
      'version': 1,
      'tenantId': _tenantId,
      'branchId': _branchId,
      'sales': [
        {
          'id': id,
          'label': label,
          'parkedAt': DateTime.utc(2026, 11, 10).toIso8601String(),
          'cart': {
            'items': [
              {
                'id': '$id-line',
                'productId': 'rice-1',
                'productName': 'Rice 1kg',
                'sku': 'RICE-1',
                'quantity': 1,
                'unitPrice': 120,
                'discount': 0,
                'saleUnit': 'piece',
                'saleQuantity': 1,
                'unitConversionFactor': 1,
                'catalogUnitPrice': 120,
                'allowFractions': false,
              },
            ],
            'discountPercent': 0,
            'discountAmount': 0,
          },
        },
      ],
    });

class _PosHarness {
  _PosHarness({
    required this.router,
    required this.auth,
    required this.connectivity,
    required this.cart,
  });

  final GoRouter router;
  final _LocalAuthService auth;
  final _TestConnectivity connectivity;
  final CartNotifier cart;
  bool _disposed = false;

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await getIt.popScope();
    await auth.close();
    await connectivity.close();
    DesktopLayout.debugIsDesktopPlatform = null;
  }
}

class _LocalAuthService implements AuthService {
  _LocalAuthService({this.permissions = const []});

  final _status = StreamController<AuthStatus>.broadcast();
  final List<String> permissions;

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
  Map<String, dynamic>? get currentUser => <String, dynamic>{
        'authMode': 'local',
        'tenantId': _tenantId,
        'branchId': _branchId,
        'permissions': permissions,
      };
  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;

  Future<void> close() => _status.close();

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

class _MemoryStorage implements StorageService {
  _MemoryStorage({
    this.pendingSecureRead,
    this.legacySnapshot,
  });

  final Completer<String?>? pendingSecureRead;
  String? secureSnapshot;
  String? legacySnapshot;

  @override
  Future<String?> getSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) =>
      pendingSecureRead?.future ?? Future<String?>.value(secureSnapshot);

  @override
  String? getHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) =>
      legacySnapshot;

  @override
  Future<void> saveSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
    required String snapshot,
  }) async {
    secureSnapshot = snapshot;
  }

  @override
  Future<void> saveHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
    required String snapshot,
  }) async {
    legacySnapshot = snapshot;
  }

  @override
  Future<void> clearLegacyHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async {
    legacySnapshot = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPayments extends StateNotifier<PaymentState>
    implements PaymentNotifier {
  _TestPayments() : super(const PaymentState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _TestInbox() : super(const NotificationInboxState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
