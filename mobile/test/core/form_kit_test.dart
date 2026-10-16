import 'package:axon_pos/core/widgets/form_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kitCount', () {
    test('says one piece, many pieces, and leaves a plural unit alone', () {
      expect(kitCount(1, 'piece'), '1 piece');
      expect(kitCount(0, 'piece'), '0 pieces');
      expect(kitCount(24, 'piece'), '24 pieces');
      expect(kitCount(24, 'pieces'), '24 pieces');
      expect(kitCount(2.5, 'kg'), '2.5 kgs');
    });
  });

  group('kitAddToField', () {
    test('adds to a number, and treats a blank field as zero', () {
      final c = TextEditingController();
      kitAddToField(c, 5);
      expect(c.text, '5');
      kitAddToField(c, 10);
      expect(c.text, '15');
    });

    test('keeps a decimal that was typed and never shows 15.0', () {
      final c = TextEditingController(text: '2.5');
      kitAddToField(c, 5);
      expect(c.text, '7.5');
      kitAddToField(c, 1);
      expect(c.text, '8.5');
    });

    test('ignores junk in the field instead of crashing', () {
      final c = TextEditingController(text: 'abc');
      kitAddToField(c, 5);
      expect(c.text, '5');
    });
  });

  testWidgets('QuickAddChips reports the amount that was tapped', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuickAddChips(amounts: const [5, 10], onAdd: taps.add),
      ),
    ));
    await tester.tap(find.text('+10'));
    await tester.tap(find.text('+5'));
    expect(taps, [10, 5]);
  });

  testWidgets('ChoicePill is a button that says whether it is selected',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChoicePill(label: 'Urgent', selected: true, onTap: () => tapped++),
      ),
    ));
    await tester.tap(find.text('Urgent'));
    expect(tapped, 1);
    final semantics = tester.getSemantics(find.text('Urgent'));
    expect(semantics.label, 'Urgent');
  });

  testWidgets('PinnedActionBar shows its summary above the button',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PinnedActionBar(
          summary: Text('Adding 24 pieces'),
          child: Text('Save'),
        ),
      ),
    ));
    expect(find.text('Adding 24 pieces'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
