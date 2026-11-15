import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/features/settings/presentation/providers/layout_requests_provider.dart';
import 'package:axon_pos/features/settings/presentation/widgets/layout_business_type_card.dart';
import 'package:axon_pos/features/settings/presentation/widgets/layout_live_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _user({
  String activation = 'ACTIVE',
  String? profile = 'bookshop',
  Map<String, dynamic>? approval,
}) =>
    {
      'tenant': {
        'activationStatus': activation,
        'settings': {
          if (profile != null) 'businessLayout': {'profileId': profile},
          if (approval != null) 'approvedProfileChange': approval,
        },
      },
    };

LayoutChangeRequest _request(String status, {String to = 'cafe_takeaway', String? note}) =>
    LayoutChangeRequest(
      id: 'r1',
      toProfileId: to,
      additionalProfileIds: const [],
      reason: 'Opening a food counter',
      status: status,
      decisionNote: note,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

void main() {
  group('businessTypeLockFor', () {
    test('a paid shop with a layout is locked', () {
      expect(businessTypeLockFor(_user(), isLocalWorkspace: false).locked, isTrue);
    });

    test('a shop still on setup, or with no layout yet, is free', () {
      expect(businessTypeLockFor(_user(activation: 'PENDING'), isLocalWorkspace: false).locked, isFalse);
      expect(businessTypeLockFor(_user(profile: null), isLocalWorkspace: false).locked, isFalse);
    });

    test('a device-only shop is never locked', () {
      expect(businessTypeLockFor(_user(), isLocalWorkspace: true).locked, isFalse);
    });

    test('reads an approved change', () {
      final lock = businessTypeLockFor(
        _user(approval: {'profileId': 'cafe_takeaway', 'additionalProfileIds': ['grocery']}),
        isLocalWorkspace: false,
      );
      expect(lock.hasApproval, isTrue);
      expect(lock.approvedProfileId, 'cafe_takeaway');
      expect(lock.approvedAdditionalProfileIds, ['grocery']);
    });
  });

  group('LayoutBusinessTypeCard', () {
    final layout = businessLayoutFromUser(_user());

    Widget host(Widget child, {double width = 360}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
            ),
          ),
        );

    Widget card({
      bool locked = true,
      List<LayoutChangeRequest> requests = const [],
      List<String>? taps,
    }) =>
        LayoutBusinessTypeCard(
          layout: layout,
          locked: locked,
          requests: requests,
          canManage: true,
          onRequestChange: () => taps?.add('request'),
          onApply: (_) => taps?.add('apply'),
          onCancel: (_) => taps?.add('cancel'),
          onAddStore: () => taps?.add('store'),
        );

    testWidgets('a locked shop can ask for a change or add a store', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(card(taps: taps)));
      await tester.pumpAndSettle();

      expect(find.text('YOUR BUSINESS TYPE'), findsOneWidget);
      expect(find.text('Request a change'), findsOneWidget);
      await tester.tap(find.text('Request a change'));
      await tester.tap(find.text('Add a store'));
      expect(taps, ['request', 'store']);
    });

    testWidgets('a shop still choosing sees no request buttons', (tester) async {
      await tester.pumpWidget(host(card(locked: false)));
      await tester.pumpAndSettle();
      expect(find.text('Request a change'), findsNothing);
    });

    testWidgets('a waiting request can be withdrawn', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(card(requests: [_request('PENDING')], taps: taps)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Waiting for review'), findsOneWidget);
      expect(find.text('Request a change'), findsNothing);
      await tester.tap(find.text('Withdraw request'));
      expect(taps, ['cancel']);
    });

    testWidgets('an approved change is applied by the owner', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(
          host(card(requests: [_request('APPROVED', note: 'Welcome aboard')], taps: taps)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Approved:'), findsOneWidget);
      await tester.tap(find.textContaining('Switch to'));
      expect(taps, ['apply']);
    });

    testWidgets('a declined request shows the reply and allows a new one', (tester) async {
      await tester.pumpWidget(
          host(card(requests: [_request('REJECTED', note: 'Add a store instead')])));
      await tester.pumpAndSettle();
      expect(find.text('Add a store instead'), findsOneWidget);
      expect(find.text('Request a change'), findsOneWidget);
    });

    testWidgets('fits a narrow phone and a wide tablet without overflowing', (tester) async {
      for (final width in [300.0, 360.0, 720.0]) {
        await tester.pumpWidget(host(card(requests: [_request('PENDING')]), width: width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'overflow at $width');
      }
    });
  });

  group('LayoutLivePreview', () {
    testWidgets('draws as a phone and as a tablet', (tester) async {
      final layout = businessLayoutFromUser(_user(profile: 'bakery_food_counter'));
      for (final wide in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: LayoutLivePreview(layout: layout, wide: wide))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LayoutLivePreview), findsOneWidget);
      }
    });
  });

  test('Bakery & food counter has its own colour and selling points', () {
    final preset = businessLayoutPreset('bakery_food_counter');
    expect(preset.accent, isNotNull);
    expect(preset.highlights, isNotEmpty);
  });
}
