import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/team/presentation/screens/invite_staff_screen.dart';

/// A manual ApiClient spy that records calls and returns canned data.
class _SpyApiClient extends ApiClient {
  _SpyApiClient() : super(Dio());

  /// If set, getRoles/getBranches return this completer's future instead.
  Completer<List<dynamic>>? loadCompleter;

  List<Map<String, dynamic>> roles = [];
  List<Map<String, dynamic>> branches = [];
  Object? rolesError;
  Object? branchesError;
  Object? createError;
  Map<String, dynamic>? lastInvitationCall;

  @override
  Future<List<dynamic>> getRoles() async {
    if (loadCompleter != null) await loadCompleter!.future;
    if (rolesError != null) throw rolesError!;
    return roles;
  }

  @override
  Future<List<dynamic>> getBranches() async {
    if (loadCompleter != null) await loadCompleter!.future;
    if (branchesError != null) throw branchesError!;
    return branches;
  }

  @override
  Future<Map<String, dynamic>> createStaffInvitation({
    required String email,
    required String firstName,
    required String lastName,
    required String roleId,
    required String branchId,
  }) async {
    if (createError != null) throw createError!;
    lastInvitationCall = {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'roleId': roleId,
      'branchId': branchId,
    };
    return {};
  }
}

/// Helper: scroll down until [finder] is visible, then tap.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late _SpyApiClient spyApi;

  setUp(() {
    spyApi = _SpyApiClient();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) {
      getIt.unregister<ApiClient>();
    }
    getIt.registerSingleton<ApiClient>(spyApi);
  });

  tearDown(() {
    // Leave getIt as-is for other tests
  });

  GoRouter _router() => GoRouter(
        initialLocation: '/invite-staff',
        routes: [
          GoRoute(
            path: '/invite-staff',
            builder: (context, state) => const InviteStaffScreen(),
          ),
          GoRoute(
            path: '/owner-welcome',
            builder: (context, state) => const Scaffold(
              body: Text('Owner Welcome'),
            ),
          ),
        ],
      );

  group('InviteStaffScreen', () {
    testWidgets('shows loading indicator on init', (tester) async {
      spyApi.loadCompleter = Completer(); // never completes

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pump(); // Start the async load

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state when API fails', (tester) async {
      spyApi.rolesError = Exception('Network error');
      spyApi.branchesError = Exception('Network error');

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('Could not load roles and branches'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows empty state when no roles or branches', (tester) async {
      spyApi.roles = [];
      spyApi.branches = [];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('Setup required'), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
    });

    testWidgets('renders form with all fields after loading', (tester) async {
      spyApi.roles = [
        {'id': 'role-1', 'name': 'Cashier'},
        {'id': 'role-2', 'name': 'Manager'},
      ];
      spyApi.branches = [
        {'id': 'branch-1', 'name': 'Main Branch'},
        {'id': 'branch-2', 'name': 'Downtown'},
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Invite a team member'), findsOneWidget);

      // Form fields
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Last name'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);

      // Submit button
      expect(find.text('Send verified invitation'), findsOneWidget);
    });

    testWidgets('shows validation errors on empty submit', (tester) async {
      spyApi.roles = [
        {'id': 'role-1', 'name': 'Cashier'},
      ];
      spyApi.branches = [
        {'id': 'branch-1', 'name': 'Main Branch'},
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Scroll to submit button and tap
      await scrollAndTap(tester, find.text('Send verified invitation'));

      // Validation errors for first name, last name, email
      expect(find.text('Required'), findsNWidgets(3));
    });

    testWidgets('validates email format', (tester) async {
      spyApi.roles = [
        {'id': 'role-1', 'name': 'Cashier'},
      ];
      spyApi.branches = [
        {'id': 'branch-1', 'name': 'Main Branch'},
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Fill fields with invalid email
      await tester.enterText(
          find.byType(TextFormField).at(0), 'John');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Doe');
      await tester.enterText(
          find.byType(TextFormField).at(2), 'not-an-email');

      await scrollAndTap(tester, find.text('Send verified invitation'));

      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('calls API on valid submit and pops on success', (tester) async {
      spyApi.roles = [
        {'id': 'role-1', 'name': 'Cashier'},
      ];
      spyApi.branches = [
        {'id': 'branch-1', 'name': 'Main Branch'},
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Fill valid data
      await tester.enterText(
          find.byType(TextFormField).at(0), 'John');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Doe');
      await tester.enterText(
          find.byType(TextFormField).at(2), 'john@example.com');

      await scrollAndTap(tester, find.text('Send verified invitation'));

      // Verify the API was called with correct data
      expect(spyApi.lastInvitationCall, isNotNull);
      expect(spyApi.lastInvitationCall!['email'], 'john@example.com');
      expect(spyApi.lastInvitationCall!['firstName'], 'John');
      expect(spyApi.lastInvitationCall!['lastName'], 'Doe');
    });

    testWidgets('shows error snackbar on API failure', (tester) async {
      spyApi.roles = [
        {'id': 'role-1', 'name': 'Cashier'},
      ];
      spyApi.branches = [
        {'id': 'branch-1', 'name': 'Main Branch'},
      ];
      spyApi.createError = Exception('API error');

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).at(0), 'John');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Doe');
      await tester.enterText(
          find.byType(TextFormField).at(2), 'john@example.com');

      await scrollAndTap(tester, find.text('Send verified invitation'));

      expect(
        find.text(
          'We could not send the invitation. Check the details and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('dropdowns are populated with API data', (tester) async {
      spyApi.roles = [
        {'id': 'role-1', 'name': 'Cashier'},
        {'id': 'role-2', 'name': 'Manager'},
      ];
      spyApi.branches = [
        {'id': 'branch-1', 'name': 'Main Branch'},
        {'id': 'branch-2', 'name': 'Downtown'},
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Open role dropdown — scroll to it first
      await scrollAndTap(tester, find.text('Cashier'));
      await tester.pumpAndSettle();

      expect(find.text('Manager'), findsOneWidget);

      // Dismiss the dropdown by tapping elsewhere
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Open branch dropdown
      await scrollAndTap(tester, find.text('Main Branch'));
      await tester.pumpAndSettle();

      expect(find.text('Downtown'), findsOneWidget);
    });
  });
}
