import 'package:aca/core/permissions.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/features/tenants/license_logic.dart' show FeatureChoice;
import 'package:aca/features/tenants/tenant_changes.dart';
import 'package:aca/features/tenants/tenant_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tenants_screen_test.dart'
    show
        FakeRepo,
        TestEnv,
        deviceJson,
        detailJson,
        harness,
        licenseJson,
        makeEnv,
        noteJson,
        settle,
        usePhone,
        userJson;

void main() {
  late TestEnv env;

  FakeRepo repo() => env.repo;

  Future<void> open(WidgetTester tester, {double scale = 1.0}) async {
    usePhone(tester, scale: scale);
    await tester.pumpWidget(harness(env, const TenantDetailScreen(tenantId: 'tenant-1', tenantName: 'Mart Fixture')));
    await settle(tester);
  }

  Future<void> goToTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.widgetWithText(Tab, label));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(Tab, label));
    await settle(tester);
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Actions'));
    await settle(tester);
  }

  Future<void> chooseAction(WidgetTester tester, String title) async {
    await openActions(tester);
    await tester.tap(find.text(title));
    await settle(tester);
  }

  /// Scrolls the vertical list that is currently on screen until [finder] is visible.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.descendant(of: find.byType(ListView).hitTestable().first, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(finder, 250, scrollable: list, maxScrolls: 40);
    await settle(tester);
  }

  setUp(() async {
    env = await makeEnv();
    repo().detail = detailJson();
    repo().users = [userJson('u1', 'Owen', sessions: 1), userJson('u2', 'Cathy', role: 'CASHIER')];
    repo().devices = [deviceJson('d1', 'Till 1', '1.0.74'), deviceJson('d2', 'Till 2', '1.0.70')];
    repo().notes = [noteJson('n1', 'Prefers calls after 5pm', minutesAgo: 1), noteJson('n2', 'Pinned: contract signed', pinned: true, minutesAgo: 90)];
  });

  group('header and Overview tab', () {
    testWidgets('shows who the company is, the subscription and the licence at 360 dp / 1.3x text', (tester) async {
      await open(tester);

      expect(find.text('Mart Fixture'), findsWidgets);
      for (final label in ['Overview', 'People', 'Devices', 'Billing', 'Notes']) {
        expect(find.widgetWithText(Tab, label), findsOneWidget, reason: label);
      }
      expect(find.text('owner@mart.test'), findsOneWidget);
      expect(find.text('+254 700 000111'), findsOneWidget);

      await reveal(tester, find.text('Payment provider'));
      expect(find.text('Paystack'), findsOneWidget);
      await reveal(tester, find.text('Branches'));
      // Seat usage uses the licence limits (the plan's allowance), not the raw company columns.
      expect(find.text('2 of 10'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);

      await reveal(tester, find.text('Edit licence'));
      expect(find.text('AXON-ABCD-EFGH-JKLM'), findsOneWidget);
      expect(find.text('Not enforced'), findsOneWidget);
      expect(find.textContaining('Sales analytics'), findsOneWidget);
      expect(find.text('Audit trail for this company'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed company load shows the error with retry', (tester) async {
      repo().detailError = ApiException(500, 'The server fell over');
      await open(tester);
      expect(find.text('The server fell over'), findsOneWidget);
      repo().detailError = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('owner@mart.test'), findsOneWidget);
    });

    testWidgets('a locked-out company shows the red banner and can be unlocked', (tester) async {
      repo().detail = detailJson(isActive: false);
      await open(tester);
      expect(find.text('This company is locked out — nobody can sign in'), findsOneWidget);
      expect(find.text('Locked out'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, 'Lift lockout'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Resolved with the owner');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lift lockout'));
      await settle(tester);

      expect(repo().log, contains('lift:tenant-1:Resolved with the owner'));
    });

    testWidgets('a read-only role sees no banner action, no actions menu, no edit and no extra tabs', (tester) async {
      env = await makeEnv(perms: [Perm.tenantsView]);
      env.repo.detail = detailJson(isActive: false);
      await open(tester);

      expect(find.text('This company is locked out — nobody can sign in'), findsOneWidget);
      expect(find.text('Lift lockout'), findsNothing);
      expect(find.byTooltip('Actions'), findsNothing);
      expect(find.widgetWithText(Tab, 'People'), findsNothing);
      expect(find.widgetWithText(Tab, 'Devices'), findsNothing);
      expect(find.widgetWithText(Tab, 'Billing'), findsNothing);
      expect(find.widgetWithText(Tab, 'Notes'), findsOneWidget);
      await reveal(tester, find.text('MODULES'));
      expect(find.text('Edit licence'), findsNothing);
      expect(find.text('Audit trail for this company'), findsNothing);
    });

    testWidgets('licence load failing (403) is contained to its card', (tester) async {
      repo().licenseError = ApiException(403, 'No', code: 'MISSING_PERMISSION');
      await open(tester);
      expect(find.text('owner@mart.test'), findsOneWidget);
      await reveal(tester, find.text('Not allowed for your role'));
      expect(find.text('Not allowed for your role'), findsOneWidget);
    });
  });

  group('actions menu', () {
    testWidgets('lists every action for a full role', (tester) async {
      await open(tester);
      await openActions(tester);
      for (final t in ['Extend subscription', 'Suspend', 'Issue credit', 'Force sign-out of every user', 'Lock company out']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Reactivate'), findsNothing);
      expect(find.text('Lift lockout'), findsNothing);
    });

    testWidgets('shows only what the role can do and hides the button when nothing is allowed', (tester) async {
      env = await makeEnv(perms: [Perm.tenantsView, Perm.tenantsManage]);
      env.repo.detail = detailJson();
      await open(tester);
      await openActions(tester);
      expect(find.text('Extend subscription'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Issue credit'), findsNothing);
      expect(find.text('Lock company out'), findsNothing);
    });

    testWidgets('labels follow the state: Reactivate for a suspended company, Lift lockout when locked', (tester) async {
      repo().detail = detailJson(status: 'SUSPENDED', isActive: false);
      await open(tester);
      await openActions(tester);
      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Lift lockout'), findsWidgets);
      expect(find.text('Lock company out'), findsNothing);
    });

    testWidgets('extend: quick chip, shows the new end date, calls the API and refreshes lists', (tester) async {
      var bumped = 0;
      void onBump() => bumped++;
      tenantChanges.addListener(onBump);
      addTearDown(() => tenantChanges.removeListener(onBump));

      await open(tester);
      await chooseAction(tester, 'Extend subscription');
      expect(find.widgetWithText(FilledButton, 'Choose how long'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '14 days'));
      await tester.pump();
      expect(find.textContaining('New end date:'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Extend by 14 days'));
      await settle(tester);

      expect(repo().log, contains('extend:tenant-1:14'));
      expect(find.textContaining('Now ends 1 Dec 2026'), findsOneWidget);
      expect(bumped, greaterThan(0));
    });

    testWidgets('extend: a custom value outside 1–365 cannot be submitted', (tester) async {
      await open(tester);
      await chooseAction(tester, 'Extend subscription');
      await tester.enterText(find.byType(TextField), '400');
      await tester.pump();
      expect(find.text('Enter a whole number from 1 to 365'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Choose how long')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '365');
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Extend by 365 days'), findsOneWidget);
    });

    testWidgets('suspend asks first, then suspends', (tester) async {
      await open(tester);
      await chooseAction(tester, 'Suspend');
      expect(find.text('Suspend Mart Fixture?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(repo().log, isEmpty);

      await chooseAction(tester, 'Suspend');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend company'));
      await settle(tester);
      expect(repo().log, ['suspend:tenant-1']);
    });

    testWidgets('credit: needs an amount and a reason, confirms, then issues', (tester) async {
      await open(tester);
      await chooseAction(tester, 'Issue credit');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Review credit')).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1,500');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed, isNull, reason: 'a reason is required');
      await tester.enterText(find.widgetWithText(TextField, 'Reason (required)'), 'October downtime');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Review KES 1,500 credit'));
      await settle(tester);

      expect(find.text('Issue KES 1,500 credit?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Issue credit'));
      await settle(tester);
      expect(repo().log, ['credit:tenant-1:1500:October downtime']);
    });

    testWidgets('credit: amounts under KES 1 are refused', (tester) async {
      await open(tester);
      await chooseAction(tester, 'Issue credit');
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '0.5');
      await tester.pump();
      expect(find.text('Enter at least KES 1'), findsOneWidget);
    });

    testWidgets('force sign-out confirms and reports how many sessions ended', (tester) async {
      await open(tester);
      await chooseAction(tester, 'Force sign-out of every user');
      expect(find.text('Sign everyone out?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign everyone out'));
      await settle(tester);
      expect(repo().log, ['forceLogout:tenant-1']);
      expect(find.text('Signed out 3 sessions'), findsOneWidget);
    });

    testWidgets('lock out: optional reason, destructive button, calls the API', (tester) async {
      await open(tester);
      await chooseAction(tester, 'Lock company out');
      expect(find.text('Lock Mart Fixture out?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Fraud suspected');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lock company out'));
      await settle(tester);
      expect(repo().log, ['lockout:tenant-1:Fraud suspected']);
    });

    testWidgets('a rejected action shows the server message and changes nothing on screen', (tester) async {
      final failing = _FailingRepo(env.api);
      env = TestEnv(env.api, failing, env.session);
      failing.detail = detailJson();
      await open(tester);
      await chooseAction(tester, 'Suspend');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend company'));
      await settle(tester);
      expect(find.text('Your role cannot suspend companies'), findsOneWidget);
    });
  });

  group('People tab', () {
    testWidgets('lists the company users with role, state, last sign-in and sessions', (tester) async {
      await open(tester);
      await goToTab(tester, 'People');
      expect(find.text('2 people · 2 active'), findsOneWidget);
      expect(find.text('Owen Fixture'), findsOneWidget);
      expect(find.text('owen@mart.test'), findsOneWidget);
      expect(find.text('1 active session'), findsOneWidget);
      expect(find.text('Cashier'), findsOneWidget);
      expect(find.textContaining('Last sign-in 3 h ago'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 403 renders the not-allowed state', (tester) async {
      repo().usersError = ApiException(403, 'Forbidden', code: 'MISSING_PERMISSION');
      await open(tester);
      await goToTab(tester, 'People');
      expect(find.text('Not allowed for your role'), findsOneWidget);
    });

    testWidgets('deactivate a user from the sheet (with confirmation)', (tester) async {
      await open(tester);
      await goToTab(tester, 'People');
      await tester.tap(find.text('Cathy Fixture'));
      await settle(tester);
      expect(find.text('Sign out of all devices'), findsNothing);
      expect(find.text('Not signed in anywhere'), findsOneWidget);
      await tester.tap(find.text('Deactivate user'));
      await settle(tester);
      expect(find.text('Deactivate Cathy Fixture?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate user'));
      await settle(tester);
      expect(repo().log, ['userActive:u2:false']);
    });

    testWidgets('sign a user out of all devices', (tester) async {
      await open(tester);
      await goToTab(tester, 'People');
      await tester.tap(find.text('Owen Fixture'));
      await settle(tester);
      await tester.tap(find.text('Sign out of all devices'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out of all devices'));
      await settle(tester);
      expect(repo().log, ['revokeUser:u1']);
      expect(find.text('Signed out 2 sessions'), findsOneWidget);
    });

    testWidgets('a deactivated user can be reactivated', (tester) async {
      repo().users = [userJson('u3', 'Dina', isActive: false)];
      await open(tester);
      await goToTab(tester, 'People');
      await tester.tap(find.text('Dina Fixture'));
      await settle(tester);
      expect(find.text('Reactivate user'), findsOneWidget);
      await tester.tap(find.text('Reactivate user'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Reactivate user'));
      await settle(tester);
      expect(repo().log, ['userActive:u3:true']);
    });

    testWidgets('a role without tenants.security can only read the account', (tester) async {
      env = await makeEnv(perms: [Perm.tenantsView, Perm.tenantsUsers]);
      env.repo.detail = detailJson();
      env.repo.users = [userJson('u3', 'Dina')];
      await open(tester);
      await goToTab(tester, 'People');
      await tester.tap(find.text('Dina Fixture'));
      await settle(tester);
      expect(find.text('Deactivate user'), findsNothing);
      expect(find.text('Your role can look at this account but not change it.'), findsOneWidget);
    });

    testWidgets('empty company', (tester) async {
      repo().users = [];
      await open(tester);
      await goToTab(tester, 'People');
      expect(find.text('No people yet'), findsOneWidget);
    });
  });

  group('Devices tab', () {
    testWidgets('highlights versions older than the newest on that company\'s devices', (tester) async {
      await open(tester);
      await goToTab(tester, 'Devices');
      expect(find.textContaining('1 not on the newest app version (1.0.74)'), findsOneWidget);
      expect(find.text('App v1.0.74'), findsOneWidget);
      expect(find.text('App v1.0.70'), findsOneWidget);
      expect(find.text('Newest on this company\'s devices is v1.0.74'), findsOneWidget);
      expect(find.text('Main Branch'), findsWidgets);
      expect(find.text('SM-A15 · Android 14'), findsWidgets);
      expect(find.textContaining('Last sync 40 min ago'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an up-to-date fleet has no warning', (tester) async {
      repo().devices = [deviceJson('d1', 'Till 1', '1.0.74'), deviceJson('d2', 'Till 2', '1.0.74')];
      await open(tester);
      await goToTab(tester, 'Devices');
      expect(find.text('2 devices'), findsOneWidget);
      expect(find.textContaining('not on the newest'), findsNothing);
      expect(find.textContaining('Newest on this company'), findsNothing);
    });

    testWidgets('no devices has an empty state', (tester) async {
      repo().devices = [];
      await open(tester);
      await goToTab(tester, 'Devices');
      expect(find.text('No devices registered'), findsOneWidget);
    });
  });

  group('Billing tab', () {
    testWidgets('shows waiting M-Pesa claims and invoices with credit styling', (tester) async {
      repo().detail = detailJson(claims: [
        {
          'id': 'c1',
          'tenantId': 'tenant-1',
          'invoiceId': 'inv-9',
          'mpesaCode': 'SBX12AB34CD',
          'amount': '3200',
          'currency': 'KES',
          'status': 'PENDING',
          'createdAt': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
        },
        {
          'id': 'c2',
          'tenantId': 'tenant-1',
          'invoiceId': 'inv-8',
          'mpesaCode': 'DECIDED0001',
          'amount': '3200',
          'currency': 'KES',
          'status': 'APPROVED',
          'createdAt': '2026-10-01T10:00:00.000Z',
        },
      ]);
      await open(tester);
      await goToTab(tester, 'Billing');

      expect(find.text('M-PESA CLAIMS WAITING (1)'), findsOneWidget);
      expect(find.text('SBX12AB34CD'), findsOneWidget);
      expect(find.text('DECIDED0001'), findsNothing, reason: 'only PENDING claims are waiting');
      expect(find.text('Claimed 2 h ago'), findsOneWidget);
      await reveal(tester, find.text('Goodwill credit'));
      expect(find.text('Downtime in October'), findsOneWidget);
      expect(find.text('−KES 100'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"See all invoices" loads them in place, 50 at a time', (tester) async {
      repo().invoiceRows = [
        for (var i = 0; i < 4; i++)
          {
            'id': 'all-$i',
            'tenantId': 'tenant-1',
            'plan': 'CORE',
            'amount': '3200',
            'status': i == 0 ? 'PENDING' : 'PAID',
            'provider': 'MPESA',
            'reference': 'R$i',
            'createdAt': '2026-0${i + 1}-10T10:00:00.000Z',
            'paidAt': '2026-0${i + 1}-11T10:00:00.000Z',
          },
      ];
      await open(tester);
      await goToTab(tester, 'Billing');
      await reveal(tester, find.text('See all 4 invoices'));
      await tester.tap(find.text('See all 4 invoices'));
      await settle(tester);
      expect(repo().log, contains('invoices:tenant-1:1:50'));
      final list = find.descendant(of: find.byType(ListView).hitTestable().first, matching: find.byType(Scrollable)).first;
      await tester.drag(list, const Offset(0, 3000));
      await settle(tester);
      expect(find.text('ALL INVOICES (4)'), findsOneWidget);
      expect(find.text('See all 4 invoices'), findsNothing);
    });

    testWidgets('a company with no invoices says so', (tester) async {
      repo().detail = {...detailJson(invoiceCount: 0), 'last5Invoices': <dynamic>[]};
      await open(tester);
      await goToTab(tester, 'Billing');
      expect(find.text('No invoices yet'), findsOneWidget);
    });
  });

  group('Notes tab', () {
    testWidgets('pinned notes come first and carry a pin', (tester) async {
      await open(tester);
      await goToTab(tester, 'Notes');
      final pinned = tester.getTopLeft(find.text('Pinned: contract signed')).dy;
      final plain = tester.getTopLeft(find.text('Prefers calls after 5pm')).dy;
      expect(pinned, lessThan(plain));
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.textContaining('support@aca.test · 1 h ago'), findsOneWidget);
    });

    testWidgets('add a pinned note', (tester) async {
      await open(tester);
      await goToTab(tester, 'Notes');
      await tester.tap(find.text('Add note'));
      await settle(tester);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save note')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Owner travelling until Friday');
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);
      expect(repo().log, ['addNote:Owner travelling until Friday:true']);
    });

    testWidgets('delete asks first', (tester) async {
      await open(tester);
      await goToTab(tester, 'Notes');
      await tester.tap(find.byTooltip('Delete note').first);
      await settle(tester);
      expect(find.text('Delete this note?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete note'));
      await settle(tester);
      expect(repo().log, ['deleteNote:n2']);
    });

    testWidgets('without tenants.manage notes are read-only', (tester) async {
      env = await makeEnv(perms: [Perm.tenantsView]);
      env.repo.detail = detailJson();
      env.repo.notes = [noteJson('n1', 'Read me')];
      await open(tester);
      await goToTab(tester, 'Notes');
      expect(find.text('Read me'), findsOneWidget);
      expect(find.text('Add note'), findsNothing);
      expect(find.byTooltip('Delete note'), findsNothing);
    });

    testWidgets('no notes yet', (tester) async {
      repo().notes = [];
      await open(tester);
      await goToTab(tester, 'Notes');
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.text('Add note'), findsOneWidget);
    });
  });

  group('layout at 360 dp with 1.3x system text', () {
    Future<void> scrollDown(WidgetTester tester, {int steps = 6}) async {
      final list = find.descendant(of: find.byType(ListView).hitTestable().first, matching: find.byType(Scrollable)).first;
      for (var i = 0; i < steps; i++) {
        await tester.drag(list, const Offset(0, -450));
        await settle(tester);
      }
    }

    testWidgets('every tab fits, including a locked-out company with waiting claims', (tester) async {
      repo().detail = detailJson(isActive: false, status: 'SUSPENDED', claims: [
        {
          'id': 'c1',
          'tenantId': 'tenant-1',
          'invoiceId': 'inv-9',
          'mpesaCode': 'SBX12AB34CD',
          'amount': '3200',
          'currency': 'KES',
          'status': 'PENDING',
          'createdAt': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
        },
      ]);
      await open(tester, scale: 1.3);
      expect(tester.takeException(), isNull);
      await scrollDown(tester);
      expect(tester.takeException(), isNull);

      for (final tab in ['People', 'Devices', 'Billing', 'Notes']) {
        await goToTab(tester, tab);
        await scrollDown(tester, steps: 3);
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('the sheets fit', (tester) async {
      await open(tester, scale: 1.3);
      await openActions(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Extend subscription'));
      await settle(tester);
      expect(find.widgetWithText(FilledButton, 'Choose how long'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await settle(tester);

      await chooseAction(tester, 'Issue credit');
      expect(find.widgetWithText(FilledButton, 'Review credit'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);

      await goToTab(tester, 'Notes');
      await tester.tap(find.text('Add note'));
      await settle(tester);
      expect(find.widgetWithText(FilledButton, 'Save note'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);

      await goToTab(tester, 'People');
      await tester.tap(find.text('Owen Fixture'));
      await settle(tester);
      expect(find.text('Deactivate user'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the licence editor fits (enforce warning, all modules, limits, note and key)', (tester) async {
      repo().licenseData = licenseJson(enforcement: 'enforce');
      await open(tester, scale: 1.3);
      await reveal(tester, find.text('Edit licence'));
      await tester.tap(find.text('Edit licence'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await scrollDown(tester, steps: 10);
      expect(find.text('Issue a new licence key'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('licence editor', () {
    Future<void> openEditor(WidgetTester tester) async {
      await open(tester);
      await reveal(tester, find.text('Edit licence'));
      await tester.tap(find.text('Edit licence'));
      await settle(tester);
    }

    testWidgets('starts with nothing to save and explains each enforcement mode', (tester) async {
      await openEditor(tester);
      expect(find.text('No changes yet'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'No changes yet')).onPressed, isNull);
      expect(find.text('Nothing is blocked. The licence is only reported.'), findsOneWidget);

      await tester.tap(find.text('Warn'));
      await tester.pump();
      expect(find.textContaining('every would-be block is logged'), findsOneWidget);
      await tester.tap(find.text('Enforce'));
      await tester.pump();
      expect(find.textContaining('Enforce will lock every module this licence does not include'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sends only what changed (enforcement + a revoked and a cleared module)', (tester) async {
      repo().licenseData = licenseJson(features: {
        'analytics': {'allowed': true, 'source': 'plan'},
        'customReports': {'allowed': true, 'source': 'override'},
        'aiAssistant': {'allowed': false, 'source': 'plan'},
      });
      await openEditor(tester);

      await tester.tap(find.text('Warn'));
      await tester.pump();

      final modules = find.byType(SegmentedButton<FeatureChoice>);
      expect(modules, findsNWidgets(3));
      Finder option(int module, String label) => find.descendant(of: modules.at(module), matching: find.text(label));

      // analytics: plan default -> Revoke
      await tester.ensureVisible(option(0, 'Revoke'));
      await tester.tap(option(0, 'Revoke'));
      await tester.pump();
      // customReports (granted by hand): back to Plan default
      await tester.ensureVisible(option(1, 'Plan default'));
      await tester.tap(option(1, 'Plan default'));
      await tester.pump();

      expect(find.text('Save 3 changes'), findsOneWidget);
      await tester.tap(find.text('Save 3 changes'));
      await settle(tester);

      expect(repo().licensePatches, hasLength(1));
      expect(repo().licensePatches.single, {
        'enforcement': 'warn',
        'overrides': {'analytics': false, 'customReports': null},
      });
      expect(find.text('Licence updated'), findsOneWidget);
    });

    testWidgets('turning enforcement on asks for confirmation first', (tester) async {
      await openEditor(tester);
      await tester.tap(find.text('Enforce'));
      await tester.pump();
      await tester.tap(find.text('Save 1 change'));
      await settle(tester);
      expect(find.text('Turn on enforcement?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(repo().licensePatches, isEmpty);

      await tester.tap(find.text('Save 1 change'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Enforce licence'));
      await settle(tester);
      expect(repo().licensePatches.single, {'enforcement': 'enforce'});
    });

    testWidgets('limits and note: clearing a limit sends null, bad numbers block saving', (tester) async {
      await openEditor(tester);
      await reveal(tester, find.widgetWithText(TextField, 'Max branches'));
      await tester.enterText(find.widgetWithText(TextField, 'Max branches'), '');
      await tester.enterText(find.widgetWithText(TextField, 'Max users'), '25');
      await tester.pump();
      expect(find.text('Save 2 changes'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Max users'), '0');
      await tester.pump();
      expect(find.text('Use a whole number of 1 or more'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Max users'), '25');
      await reveal(tester, find.widgetWithText(TextField, 'Note (internal)'));
      await tester.enterText(find.widgetWithText(TextField, 'Note (internal)'), 'Upgraded after call');
      await tester.pump();
      await tester.tap(find.text('Save 3 changes'));
      await settle(tester);
      expect(repo().licensePatches.single, {'maxBranches': null, 'maxUsers': 25, 'note': 'Upgraded after call'});
    });

    testWidgets('valid-until: pick a date, send it, then clear it', (tester) async {
      await openEditor(tester);
      await reveal(tester, find.text('Pick a date'));
      expect(find.text('No expiry date'), findsOneWidget);
      await tester.tap(find.text('Pick a date'));
      await settle(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester);

      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('No expiry date'), findsNothing);
      await reveal(tester, find.text('Save 1 change'));
      await tester.tap(find.text('Save 1 change'));
      await settle(tester);
      final sent = repo().licensePatches.single['validUntil'];
      expect(sent, isA<String>());
      final when = DateTime.parse(sent as String);
      expect(when.isAfter(DateTime.now().add(const Duration(days: 25))), isTrue, reason: 'defaults to a month from now, end of that day');
    });

    testWidgets('valid-until: clearing an existing date sends null', (tester) async {
      repo().licenseData = {...licenseJson(), 'validUntil': '2027-06-30T20:59:59.000Z'};
      await openEditor(tester);
      await reveal(tester, find.text('Clear'));
      expect(find.text('Change date'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await settle(tester);
      final list = find.descendant(of: find.byType(ListView).hitTestable().first, matching: find.byType(Scrollable)).first;
      await tester.drag(list, const Offset(0, 300));
      await settle(tester);
      expect(find.text('No expiry date'), findsOneWidget);
      expect(find.text('Pick a date'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
      await tester.tap(find.text('Save 1 change'));
      await settle(tester);
      expect(repo().licensePatches.single, {'validUntil': null});
    });

    testWidgets('issue a new key switch is sent as reissueKey', (tester) async {
      await openEditor(tester);
      await reveal(tester, find.text('Issue a new licence key'));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Save 1 change'));
      await settle(tester);
      expect(repo().licensePatches.single, {'reissueKey': true});
    });

    testWidgets('backing out with unsaved edits asks before discarding', (tester) async {
      await openEditor(tester);
      await tester.tap(find.text('Warn'));
      await tester.pump();
      await tester.pageBack();
      await settle(tester);
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Edit licence'), findsWidgets);
      expect(find.text('Save 1 change'), findsOneWidget);
    });

    testWidgets('after saving, the licence card shows what the server returned', (tester) async {
      repo().licenseData = licenseJson();
      await openEditor(tester);
      repo().licenseData = {...licenseJson(enforcement: 'warn'), 'licenseKey': 'AXON-NEW1-NEW2-NEW3'};
      await tester.tap(find.text('Warn'));
      await tester.pump();
      await tester.tap(find.text('Save 1 change'));
      await settle(tester);
      expect(find.text('Edit licence'), findsOneWidget); // back on the company screen
      expect(find.text('Warn only'), findsOneWidget);
      expect(find.text('AXON-NEW1-NEW2-NEW3'), findsOneWidget);
    });
  });
}

/// A repository whose suspend call is rejected by the server.
class _FailingRepo extends FakeRepo {
  _FailingRepo(super.api);

  @override
  Future<void> suspendTenant(String id) async => throw ApiException(403, 'Your role cannot suspend companies', code: 'MISSING_PERMISSION');
}
