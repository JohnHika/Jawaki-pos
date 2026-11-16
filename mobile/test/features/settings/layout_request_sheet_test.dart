import 'package:dio/dio.dart';
import 'package:axon_pos/features/settings/presentation/providers/layout_requests_provider.dart';
import 'package:axon_pos/features/settings/presentation/widgets/layout_business_type_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends LayoutRequestsApi {
  _FakeApi() : super(Dio());

  String? toProfileId;
  String? reason;

  @override
  Future<LayoutChangeRequest> create({
    required String toProfileId,
    List<String> additionalProfileIds = const [],
    required String reason,
  }) async {
    this.toProfileId = toProfileId;
    this.reason = reason;
    return LayoutChangeRequest(
      id: 'r1',
      toProfileId: toProfileId,
      additionalProfileIds: additionalProfileIds,
      reason: reason,
      status: 'PENDING',
    );
  }
}

Future<void> _open(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [layoutRequestsApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showLayoutChangeRequestSheet(
                  context,
                  currentProfileId: 'general',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reason box comes first and Send stays tappable', (tester) async {
    final api = _FakeApi();
    await _open(tester, api);

    final reasonTop = tester.getTopLeft(find.text('What do you need changed?')).dy;
    final chipsTop = tester.getTopLeft(find.text('Closest match (optional)')).dy;
    expect(reasonTop, lessThan(chipsTop));

    final send = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(send.onPressed, isNotNull);
  });

  testWidgets('tapping Send with no reason says what is missing', (tester) async {
    final api = _FakeApi();
    await _open(tester, api);

    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(find.text('Tell us what you need before sending.'), findsOneWidget);
    expect(api.reason, isNull);

    await tester.enterText(find.byType(TextField), 'too short');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 10 characters'), findsOneWidget);
    expect(api.reason, isNull);
  });

  testWidgets('a written reason alone sends as a custom layout', (tester) async {
    final api = _FakeApi();
    await _open(tester, api);

    await tester.enterText(
        find.byType(TextField), 'We are adding a food counter next to the shop');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(api.toProfileId, 'custom');
    expect(api.reason, 'We are adding a food counter next to the shop');
  });
}
