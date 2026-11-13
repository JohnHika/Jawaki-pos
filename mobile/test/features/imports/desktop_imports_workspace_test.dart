import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/imports/domain/import_models.dart';
import 'package:axon_pos/features/imports/presentation/providers/imports_provider.dart';
import 'package:axon_pos/features/imports/presentation/screens/import_detail_screen.dart';
import 'package:axon_pos/features/imports/presentation/screens/imports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

const _containerId = 'container-2026-10';

const _summaries = <ImportSummary>[
  ImportSummary(
    id: _containerId,
    title: 'October kitchenware',
    status: 'IN_TRANSIT',
    currency: 'USD',
    reference: 'BOL-7821',
    origin: 'Guangzhou',
    goodsKes: 84000,
    costsKes: 16000,
    landedKes: 100000,
    outstandingKes: 42500,
    participantCount: 3,
  ),
  ImportSummary(
    id: 'container-2026-11',
    title: 'November textiles',
    status: 'PLANNED',
    currency: 'CNY',
    goodsKes: 32000,
    costsKes: 0,
    landedKes: 32000,
    outstandingKes: 32000,
    participantCount: 1,
  ),
];

final _detail = ImportDetail.fromJson({
  'id': _containerId,
  'title': 'October kitchenware',
  'status': 'IN_TRANSIT',
  'currency': 'USD',
  'fxRate': 150,
  'basisUsed': 'VALUE',
  'reference': 'BOL-7821',
  'origin': 'Guangzhou',
  'totals': {
    'goodsKes': 84000,
    'costsKes': 16000,
    'landedKes': 100000,
    'upliftPercent': 19,
  },
  'warnings': ['One line is not linked to a product.'],
  'items': [
    {
      'id': 'line-oil',
      'description': 'Cooking oil 5L',
      'quantity': 12,
      'unit': 'carton',
      'unitCost': 36,
      'landedUnitCostKes': 5400,
      'landedTotalKes': 64800,
      'goodsValueKes': 54000,
      'allocatedCostKes': 10800,
      'participantId': 'trader-self',
      'productId': 'product-oil',
      'receivedQty': 0,
    },
    {
      'id': 'line-cups',
      'description': 'Glass cups',
      'quantity': 24,
      'unit': 'piece',
      'unitCost': 2,
      'landedUnitCostKes': 250,
      'landedTotalKes': 6000,
      'goodsValueKes': 7200,
      'allocatedCostKes': 1200,
      'participantId': 'trader-asha',
      'productId': null,
      'receivedQty': 0,
    },
  ],
  'costs': [
    {
      'id': 'cost-freight',
      'type': 'FREIGHT',
      'label': 'Sea freight',
      'amount': 80,
      'currency': 'USD',
      'amountKes': 12000,
      'reference': 'FRT-080',
    },
  ],
  'participants': [
    {
      'id': 'trader-self',
      'name': 'Asha Market',
      'phone': '0712 000 111',
      'isSelf': true,
      'owesKes': 70000,
      'paidKes': 50000,
      'balanceKes': 20000,
      'status': 'PART_PAID',
    },
    {
      'id': 'trader-asha',
      'name': 'Njeri Stores',
      'isSelf': false,
      'owesKes': 30000,
      'paidKes': 0,
      'balanceKes': 30000,
      'status': 'OWES',
    },
  ],
  'payments': [
    {
      'id': 'payment-1',
      'participantId': 'trader-self',
      'amountKes': 50000,
      'method': 'MPESA',
      'reference': 'QX83R2KLMN',
      'paidAt': '2026-10-28T10:30:00.000Z',
    },
  ],
});

const _emptyDetail = ImportDetail(
  id: _containerId,
  title: 'Empty kitchenware',
  status: 'PLANNED',
  currency: 'USD',
  fxRate: 150,
  basisUsed: 'VALUE',
  goodsKes: 0,
  costsKes: 0,
  landedKes: 0,
  upliftPercent: 0,
  warnings: [],
  costs: [],
  items: [],
  participants: [],
  payments: [],
);

final _managerPermissions = RolePermissions([
  'imports.view',
  'imports.manage',
  'imports.receive',
  'imports.payments',
]);
final _viewerPermissions = RolePermissions(['imports.view']);

Widget _shellPage(Widget page, {GlobalKey? boundary, bool desktop = true}) {
  final child =
      boundary == null ? page : ShotFrame(boundaryKey: boundary, child: page);
  return desktop ? DesktopScope(sidebarCollapsed: true, child: child) : child;
}

GoRouter _router({bool desktop = true, GlobalKey? boundary}) => GoRouter(
      initialLocation: '/containers',
      routes: [
        GoRoute(
          path: '/containers',
          builder: (context, state) => _shellPage(
            const ImportsScreen(),
            boundary: boundary,
            desktop: desktop,
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => _shellPage(
                ImportDetailScreen(importId: state.pathParameters['id']!),
                boundary: boundary,
                desktop: desktop,
              ),
            ),
          ],
        ),
      ],
    );

Widget _app(
  GoRouter router, {
  bool dark = false,
  bool desktop = true,
  RolePermissions? permissions,
  ImportDetail? detail,
  List<ImportSummary>? summaries,
  Object? importsError,
}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return ProviderScope(
    overrides: [
      importsProvider.overrideWith((ref) async {
        final error = importsError;
        if (error != null) throw error;
        return summaries ?? _summaries;
      }),
      importDetailProvider(_containerId)
          .overrideWith((ref) async => detail ?? _detail),
      permissionsProvider.overrideWithValue(permissions ?? _managerPermissions),
      businessLayoutProvider
          .overrideWith((ref) => businessLayoutFromUser(null)),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: desktop ? DesktopTheme.of(base) : base,
      routerConfig: router,
    ),
  );
}

Finder _tableText<T>(String text) => find.descendant(
      of: find.byType(DesktopDataTable<T>),
      matching: find.text(text),
    );

void main() {
  setUpAll(loadShotFonts);
  setUp(() {
    DesktopLayout.debugIsDesktopPlatform = true;
  });
  tearDown(() {
    DesktopLayout.debugIsDesktopPlatform = null;
  });

  for (final dark in [false, true]) {
    for (final entry in desktopSizes.entries) {
      testWidgets(
        'desktop Imports list and inspector ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          useWindow(tester, entry.value);
          final boundary = GlobalKey();
          final router = _router(boundary: boundary);
          addTearDown(router.dispose);

          await tester.pumpWidget(_app(router, dark: dark));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(DesktopPageHeader), findsOneWidget);
          expect(find.byType(DesktopDataTable<ImportSummary>), findsOneWidget);
          expect(find.byType(FloatingActionButton), findsNothing);
          expect(find.byType(RefreshIndicator), findsNothing);
          expect(
              _tableText<ImportSummary>('October kitchenware'), findsOneWidget);
          expect(
              _tableText<ImportSummary>('November textiles'), findsOneWidget);
          expect(_tableText<ImportSummary>('KES 100,000'), findsOneWidget);

          await tester.tap(_tableText<ImportSummary>('October kitchenware'));
          await tester.pumpAndSettle();

          expect(find.byType(DesktopInspector), findsOneWidget);
          expect(find.textContaining('BOL-7821'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(DesktopInspector),
              matching: find.text('KES 42,500'),
            ),
            findsOneWidget,
          );
          expect(find.text('Open container'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await saveShot(
            tester,
            boundary,
            'build/shots/imports-desktop-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );
        },
      );
    }
  }

  testWidgets('empty desktop Imports explains how to start a container',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, summaries: const []));
    await tester.pumpAndSettle();

    expect(find.text('No containers yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('imports-create')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Imports search has a useful no-results state',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zebra');
    await tester.pumpAndSettle();

    expect(find.text('No containers match "zebra"'), findsOneWidget);
    expect(_tableText<ImportSummary>('October kitchenware'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Imports error state offers a retry', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(router, importsError: StateError('server unavailable')),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load containers"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a selected container shows desktop goods and costs',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await tester.tap(_tableText<ImportSummary>('October kitchenware'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open container'));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopPageHeader), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Cooking oil 5L'), findsOneWidget);
    expect(find.text('Glass cups'), findsOneWidget);
    expect(find.text('Sea freight'), findsOneWidget);
    expect(find.text('Njeri Stores'), findsOneWidget);
    expect(find.text('KES 100,000'), findsOneWidget);
    expect(find.byType(DesktopDataTable<ImportItemRow>), findsOneWidget);
    expect(find.byType(DesktopDataTable<ImportCostRow>), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Traders sharing this container'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('desktop-import-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopDataTable<ImportParticipantRow>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view-only users cannot remove a container participant',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, permissions: _viewerPermissions));
    await tester.pumpAndSettle();

    await tester.tap(_tableText<ImportSummary>('October kitchenware'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open container'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Traders sharing this container'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('desktop-import-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove Njeri Stores'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty goods and costs have room for their empty states',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, detail: _emptyDetail));
    await tester.pumpAndSettle();

    await tester.tap(_tableText<ImportSummary>('October kitchenware'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open container'));
    await tester.pumpAndSettle();
    expect(find.text('No goods recorded'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No costs recorded'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('desktop-import-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('No costs recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Import forms open in adaptive side panels',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await tester.tap(_tableText<ImportSummary>('October kitchenware'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open container'));
    await tester.pumpAndSettle();
    final addCost = find.byKey(const ValueKey('desktop-import-add-cost'));
    await tester.ensureVisible(addCost);
    await tester.pumpAndSettle();
    await tester.tap(addCost);
    await tester.pumpAndSettle();

    expect(find.text('Add a cost'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone Imports list keeps its existing cards and bottom action',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final router = _router(desktop: false);
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, desktop: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DesktopPageHeader), findsNothing);
    expect(find.byType(DesktopDataTable<ImportSummary>), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('October kitchenware'), findsOneWidget);
  });

  testWidgets('phone Import detail keeps its app bar and refresh behavior',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final router = _router(desktop: false);
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, desktop: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('October kitchenware'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(DesktopDataTable<ImportItemRow>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
