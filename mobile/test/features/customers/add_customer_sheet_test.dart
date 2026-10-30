import 'package:axon_pos/features/customers/presentation/widgets/add_customer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
        // Credit is permission-gated since a8bef26; these tests exercise the credit flow.
        body: AddCustomerForm(allowInitialCredit: true),
      ),
    ));
  await tester.pump();
}

void main() {
  testWidgets('shows only what is needed up front', (tester) async {
    await _pump(tester);

    expect(find.text('Customer or shop name'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Shop location (optional)'), findsOneWidget);
    // Credit and notes stay out of the way until asked for.
    expect(find.text('Amount owed'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);
    expect(find.text('Save Customer'), findsOneWidget);
  });

  testWidgets('saving an empty form says what is missing', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Save Customer'));
    await tester.pump();

    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter a phone number'), findsOneWidget);
  });

  testWidgets('a short phone number is rejected', (tester) async {
    await _pump(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Customer or shop name'), 'Wanjiru');
    await tester.enterText(find.byType(TextFormField).at(1), '0712');
    await tester.tap(find.text('Save Customer'));
    await tester.pump();

    expect(find.text('That looks too short for a phone number'), findsOneWidget);
    expect(find.text('Enter a name'), findsNothing);
  });

  testWidgets('phone field refuses letters', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextFormField).at(1), '07ab12 345x');
    await tester.pump();

    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).at(1)).controller!.text,
      '0712 345',
    );
  });

  testWidgets('turning credit on reveals the amount and due-date shortcuts',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('credit-switch')));
    await tester.pumpAndSettle();

    expect(find.text('Amount owed'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('In 1 week'), findsOneWidget);
    expect(find.text('In 2 weeks'), findsOneWidget);
    expect(find.text('Pick a date'), findsOneWidget);
  });

  testWidgets('on credit, an amount is required before saving', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('credit-switch')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Wanjiru');
    await tester.enterText(find.byType(TextFormField).at(1), '0712345678');
    await tester.ensureVisible(find.text('Save Customer'));
    await tester.tap(find.text('Save Customer'));
    await tester.pump();

    expect(find.text('Enter the amount they owe'), findsOneWidget);
  });

  testWidgets('choosing a due date shows it', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('credit-switch')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('In 1 week'));
    await tester.pump();

    expect(find.textContaining('Due '), findsOneWidget);
  });

  testWidgets('"Add a note" reveals the note field', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Add a note'));
    await tester.pump();

    expect(find.text('Note (optional)'), findsOneWidget);
    expect(find.text('Add a note'), findsNothing);
  });

  testWidgets('fits a narrow phone with large text, credit on', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _pump(tester);
    tester.view.physicalSize = const Size(720, 1280);

    await tester.tap(find.byKey(const ValueKey('credit-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save Customer'), findsOneWidget);
  });
}
