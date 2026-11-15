import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/settings/presentation/providers/layout_requests_provider.dart';
import 'package:axon_pos/features/settings/presentation/screens/business_layout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _CloudAuth extends Fake implements AuthService {
  @override
  bool get isLocalWorkspace => false;
}

Map<String, dynamic> _owner({String activation = 'ACTIVE', String? profile = 'bookshop'}) => {
      'role': 'ADMIN',
      'permissions': ['*'],
      'tenant': {
        'activationStatus': activation,
        'settings': {
          if (profile != null) 'businessLayout': {'version': 12, 'profileId': profile},
        },
      },
    };

void main() {
  setUp(() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<AuthService>()) getIt.unregister<AuthService>();
    getIt.registerSingleton<AuthService>(_CloudAuth());
  });

  tearDown(() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<AuthService>()) getIt.unregister<AuthService>();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required Map<String, dynamic> user,
    List<LayoutChangeRequest> requests = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          layoutRequestsProvider.overrideWith((ref) async => requests),
        ],
        child: const MaterialApp(home: BusinessLayoutScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone: a paid shop sees its locked business type, sections and save bar',
      (tester) async {
    await pump(tester, size: const Size(390, 844), user: _owner());

    expect(tester.takeException(), isNull);
    expect(find.text('YOUR BUSINESS TYPE'), findsOneWidget);
    expect(find.text('Request a change'), findsOneWidget);
    // The profile picker is not offered once the type is locked.
    expect(find.text('Find a shop type'), findsNothing);
    // The save bar is always on screen.
    expect(find.text('No changes yet'), findsOneWidget);
    expect(find.text('Save layout'), findsOneWidget);
    // Sections are collapsed except the first.
    await tester.scrollUntilVisible(find.text('Products'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Default selling unit'), findsNothing);
  });

  testWidgets('phone: opening a section reveals its editors', (tester) async {
    await pump(tester, size: const Size(390, 844), user: _owner());
    await tester.scrollUntilVisible(find.text('Products'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(find.text('Default selling unit'), findsOneWidget);
  });

  testWidgets('phone: a shop still setting up can choose any profile', (tester) async {
    await pump(tester, size: const Size(390, 844), user: _owner(activation: 'PENDING'));

    expect(find.text('Request a change'), findsNothing);
    expect(find.text('Find a shop type'), findsOneWidget);
  });

  testWidgets('choosing a profile counts as an unsaved change', (tester) async {
    await pump(tester, size: const Size(390, 844), user: _owner(activation: 'PENDING'));

    await tester.scrollUntilVisible(find.text('Bakery & food counter'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bakery & food counter'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unsaved: Business type'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('No changes yet'), findsOneWidget);
  });

  testWidgets('tablet: sections move to a left rail and the editor fills the right',
      (tester) async {
    await pump(tester, size: const Size(1024, 768), user: _owner());

    expect(tester.takeException(), isNull);
    expect(find.text('Business type'), findsWidgets);
    expect(find.text('Navigation'), findsOneWidget);

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(find.text('Default selling unit'), findsOneWidget);
    // Only the chosen section is shown on the right.
    expect(find.text('Request a change'), findsNothing);
  });

  testWidgets('small tablet width (640) still lays out without overflow', (tester) async {
    await pump(tester, size: const Size(640, 900), user: _owner());
    expect(tester.takeException(), isNull);
  });

  testWidgets('an approved change shows an Apply action', (tester) async {
    await pump(
      tester,
      size: const Size(390, 844),
      user: _owner(),
      requests: [
        LayoutChangeRequest(
          id: 'r1',
          toProfileId: 'bakery_food_counter',
          additionalProfileIds: const [],
          reason: 'Opening a food counter',
          status: 'APPROVED',
          createdAt: DateTime.now(),
        ),
      ],
    );
    expect(find.textContaining('Switch to Bakery'), findsOneWidget);
  });
}
