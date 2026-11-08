import 'package:axon_pos/features/expenses/presentation/widgets/add_expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
  }

  testWidgets('Add expense asks for the amount and what it was for',
      (tester) async {
    phoneSize(tester);
    NewExpense? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showAddExpenseSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Future<void> tapVisible(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    final save = find.text('Save expense');
    await tapVisible(save);
    expect(find.text('Enter how much was paid.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1,250');
    await tapVisible(save);
    expect(find.text('Choose what the money was for.'), findsOneWidget);

    await tapVisible(find.text('Other'));
    await tapVisible(save);
    expect(find.text('Say what it was for in the note.'), findsOneWidget);

    await tapVisible(find.text('Rent'));
    await tapVisible(find.text('M-Pesa'));
    await tapVisible(save);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.amount, 1250.0);
    expect(result!.category, 'Rent');
    expect(result!.method, 'MPESA');
    expect(result!.note, isNull);
  });
}
