import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/providers/api_provider.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/inventory/presentation/screens/batch_receive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi implements ApiClient {
  @override
  Future<Map<String, dynamic>> getProduct(String id) async => {
        'name': 'Maize flour',
        'unit': 'piece',
        'pricingTiers': [
          {'unit': 'box', 'quantityPerUnit': 12},
        ],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(720, 1280); // 360dp wide at 2x
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
    child: const MaterialApp(
      home: BatchReceiveScreen(productId: 'p1', productName: 'Maize flour'),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapAddBatch(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('add-batch')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // Bring it well clear of the bottom edge before tapping.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-batch')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows quantity, unit, shortcuts and a pinned button',
      (tester) async {
    await _pump(tester);

    expect(find.text('Quantity received'), findsOneWidget);
    expect(find.text('Unit'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-5')), findsOneWidget);
    expect(find.text('Receive Stock'), findsWidgets);
    expect(find.byType(GradientButton), findsOneWidget);
  });

  testWidgets('shortcuts fill the quantity and the summary follows',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('quick-10')));
    await tester.tap(find.byKey(const ValueKey('quick-5')));
    await tester.pump();

    expect(find.text('15'), findsOneWidget);
    expect(find.byKey(const ValueKey('receive-summary')), findsOneWidget);
    expect(find.textContaining('Adding 15 pieces'), findsOneWidget);
  });

  testWidgets('a second batch changes the button and the list grows',
      (tester) async {
    await _pump(tester);

    await _tapAddBatch(tester);

    expect(find.text('Receive 2 Batches'), findsOneWidget);
    expect(find.text('Batch 2'), findsOneWidget);
  });

  testWidgets('receiving with no quantity says what is missing', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(GradientButton));
    await tester.pump();

    expect(find.text('Enter how many'), findsOneWidget);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    await _pump(tester, textScale: 1.3);

    await tester.tap(find.byKey(const ValueKey('quick-50')));
    await tester.pump();
    await _tapAddBatch(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Receive 2 Batches'), findsOneWidget);
  });
}
