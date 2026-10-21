// Render + interaction checks for the Billing tab against an in-memory
// repository (no network). Verifies the screen builds without overflow at
// 360 dp with a 1.3 font scale, and that the mark-paid flows call the
// repository with the right arguments and respect permissions.
import 'package:aca/core/permissions.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
import 'package:aca/features/billing/billing_screen.dart';
import 'package:aca/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokens extends TokenStore {
  _MemoryTokens();
  @override
  Future<AuthTokens?> read() async => null;
  @override
  Future<void> write(AuthTokens t) async {}
  @override
  Future<void> clear() async {}
}

Map<String, dynamic> _invoice(
  String id, {
  String status = 'PENDING',
  String amount = '3200',
  String plan = 'CORE',
  String? provider,
  String? reference,
  String tenant = 'Fixture Pharmacy',
  String? paidAt,
}) =>
    {
      'id': id,
      'tenantId': 'tenant-$id',
      'tenantName': tenant,
      'plan': plan,
      'amount': amount,
      'currency': 'KES',
      'status': status,
      'provider': provider,
      'reference': reference,
      'periodStart': '2026-10-09T10:00:00Z',
      'periodEnd': '2026-11-08T10:00:00Z',
      'paidAt': paidAt,
      'createdAt': '2026-10-09T10:00:00Z',
    };

class _FakeRepo extends AcaRepository {
  _FakeRepo({required this.invoiceRows, required this.claimRows}) : super(AcaApi(store: _MemoryTokens()));

  final List<Map<String, dynamic>> invoiceRows;
  final List<Map<String, dynamic>> claimRows;
  final List<(String id, String? code)> markPaidCalls = [];
  final List<String?> statusRequests = [];

  @override
  Future<Paged<Invoice>> invoices({String? status, String? tenantId, int page = 1, int pageSize = 20}) async {
    statusRequests.add(status);
    final rows = invoiceRows.where((r) => status == null || r['status'] == status).toList();
    return Paged<Invoice>(
      items: rows.map(Invoice.fromJson).toList(),
      total: rows.length,
      page: 1,
      pageSize: pageSize,
      totalPages: 1,
    );
  }

  @override
  Future<List<Claim>> pendingClaims() async => claimRows.map(Claim.fromJson).toList();

  @override
  Future<void> markInvoicePaid(String invoiceId, {String? mpesaCode}) async {
    markPaidCalls.add((invoiceId, mpesaCode));
  }
}

StaffProfile _staff(List<String> permissions) => StaffProfile(
      id: 'me',
      email: 'me@example.test',
      name: 'Me',
      phone: null,
      role: 'FINANCE',
      status: 'ACTIVE',
      permissions: permissions,
      mustChangePassword: false,
      twoFactorEnabled: true,
      lastLoginAt: null,
      createdAt: null,
    );

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  required List<String> permissions,
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = SessionController(api: repo.api, repo: repo, prefs: prefs)..me = _staff(permissions);

  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AcaRepository>.value(value: repo),
        ChangeNotifierProvider<SessionController>.value(value: session),
      ],
      child: MaterialApp(
        theme: AcaTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const BillingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drags the open sheet until [target] is on screen.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(SingleChildScrollView).last;
  for (var i = 0; i < 20 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pump();
  }
  expect(target.hitTestable().evaluate(), isNotEmpty, reason: 'could not scroll $target into view');
}

void main() {
  final invoices = [
    _invoice('inv-credit',
        status: 'PAID',
        amount: '-100',
        plan: 'CREDIT',
        provider: 'CREDIT',
        reference: 'CREDIT:Outage goodwill',
        paidAt: '2026-10-20T10:00:00Z',
        tenant: 'A Very Long Company Name Trading As Fixture Supermarkets And Wholesale Limited'),
    _invoice('inv-paid',
        status: 'PAID', provider: 'PAYSTACK', reference: 'PSK-1', paidAt: '2026-10-16T10:00:00Z', tenant: 'Fixture Mart'),
    _invoice('inv-pending', status: 'PENDING', reference: 'REF-4'),
  ];
  final claims = [
    {
      'id': 'claim-1',
      'tenantId': 'tenant-inv-pending',
      'tenantName': 'Fixture Pharmacy',
      'invoiceId': 'inv-pending',
      'invoiceStatus': 'PENDING',
      'plan': 'CORE',
      'mpesaCode': 'ABC12DEF34',
      'amount': '3200',
      'currency': 'KES',
      'status': 'PENDING',
      'createdAt': '2026-10-21T08:00:00Z',
    },
    {
      'id': 'claim-2',
      'tenantId': 'tenant-inv-paid',
      'tenantName': 'Fixture Mart',
      'invoiceId': 'inv-paid',
      'invoiceStatus': 'PAID',
      'plan': 'CORE',
      'mpesaCode': 'ZZZ99YYY88',
      'amount': '3200',
      'currency': 'KES',
      'status': 'PENDING',
      'createdAt': '2026-10-20T08:00:00Z',
    },
  ];

  const manager = [Perm.billingView, Perm.billingManage, Perm.tenantsView];
  const viewer = [Perm.billingView];

  testWidgets('invoices render at 360dp / 1.3x font without overflow', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager, textScale: 1.3);

    expect(find.text('3 invoices'), findsOneWidget);
    expect(find.text('Credit'), findsOneWidget);
    expect(find.textContaining('Outage goodwill'), findsOneWidget);
    expect(find.text('−KES 100'), findsOneWidget);
    expect(find.text('Fixture Mart'), findsOneWidget);
    // One claim still needs action: the badge counts it, not the settled one.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('status chips filter on the server', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pending'));
    await tester.pumpAndSettle();

    expect(repo.statusRequests.last, 'PENDING');
    expect(find.text('1 pending invoice'), findsOneWidget);
    expect(find.text('Fixture Pharmacy'), findsOneWidget);
    expect(find.text('Fixture Mart'), findsNothing);
  });

  testWidgets('marking a pending invoice paid without a code', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager);

    await tester.tap(find.text('Fixture Pharmacy'));
    await tester.pumpAndSettle();
    expect(find.text('Open company'), findsOneWidget);
    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();

    expect(find.text('M-Pesa code (optional)'), findsOneWidget);
    expect(find.textContaining('reactivate'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid'));
    await tester.pumpAndSettle();

    expect(repo.markPaidCalls, [('inv-pending', null)]);
  });

  testWidgets('a malformed M-Pesa code blocks confirmation, a valid one is upper-cased', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager);

    await tester.tap(find.text('Fixture Pharmacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark as paid')).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'sbx12ab34cd');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid'));
    await tester.pumpAndSettle();

    expect(repo.markPaidCalls, [('inv-pending', 'SBX12AB34CD')]);
  });

  testWidgets('without billing.manage the invoice sheet is read-only', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: viewer);

    await tester.tap(find.text('Fixture Pharmacy'));
    await tester.pumpAndSettle();

    expect(find.text('REF-4'), findsWidgets);
    expect(find.text('Mark as paid'), findsNothing);
    expect(find.text('Open company'), findsNothing); // no tenants.view either
  });

  testWidgets('claims: code, help text, reconcile with confirmation', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager, textScale: 1.3);

    await tester.tap(find.text('Claims'));
    await tester.pumpAndSettle();

    expect(find.textContaining('A claim is an M-Pesa confirmation code'), findsOneWidget);
    expect(find.text('ABC12DEF34'), findsOneWidget);
    expect(find.text('Mark invoice paid with this code'), findsOneWidget);

    // The settled claim sits below the open one and offers no action.
    await tester.scrollUntilVisible(find.text('ZZZ99YYY88'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('already paid'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mark invoice paid with this code'), -300,
        scrollable: find.byType(Scrollable).last);

    await tester.tap(find.text('Mark invoice paid with this code'));
    await tester.pumpAndSettle();
    expect(find.text('Mark invoice as paid?'), findsOneWidget);
    await tester.tap(find.text('Yes, mark as paid'));
    await tester.pumpAndSettle();

    expect(repo.markPaidCalls, [('inv-pending', 'ABC12DEF34')]);
  });

  testWidgets('claims: read-only roles see the code but no action', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: viewer);

    await tester.tap(find.text('Claims'));
    await tester.pumpAndSettle();

    expect(find.text('ABC12DEF34'), findsOneWidget);
    expect(find.text('Mark invoice paid with this code'), findsNothing);
  });

  testWidgets('a credit shows its reason and offers no payment action', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager, textScale: 1.3);

    await tester.tap(find.textContaining('A Very Long Company Name'));
    await tester.pumpAndSettle();

    expect(find.text('Goodwill credit'), findsWidgets);
    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('Outage goodwill'), findsOneWidget);
    expect(find.text('Billing period'), findsNothing);
    expect(find.text('Mark as paid'), findsNothing);
  });

  testWidgets('the mark-paid sheet stays usable with the keyboard open at 1.3x font', (tester) async {
    final repo = _FakeRepo(invoiceRows: invoices, claimRows: claims);
    await _pump(tester, repo, permissions: manager, textScale: 1.3);

    await tester.tap(find.text('Fixture Pharmacy'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Mark as paid'));
    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await _reveal(tester, find.widgetWithText(FilledButton, 'Mark as paid'));
  });

  testWidgets('empty states explain themselves', (tester) async {
    final repo = _FakeRepo(invoiceRows: const [], claimRows: const []);
    await _pump(tester, repo, permissions: manager);

    expect(find.text('No invoices yet'), findsOneWidget);
    await tester.tap(find.text('Claims'));
    await tester.pumpAndSettle();
    expect(find.text('No claims waiting'), findsOneWidget);
    expect(find.textContaining('A claim is an M-Pesa confirmation code'), findsOneWidget);
  });
}
