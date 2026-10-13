import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/widgets/app_markdown.dart';

const _table = '''
| Action | Reason | Expected result |
|---|---|---|
| Restock **Coca-Cola 500ml** | Only 3 left and it sells 12 a day | No stock-outs this week |
| Review slow stock | Peanuts have not sold in 30 days | Cash freed up |
''';

void main() {
  group('parseMarkdownTable', () {
    test('splits header and body rows and drops the separator', () {
      final table = parseMarkdownTable(_table)!;
      expect(table.header, ['Action', 'Reason', 'Expected result']);
      expect(table.rows.length, 2);
      expect(table.rows.first.first, 'Restock **Coca-Cola 500ml**');
      expect(table.rows.last.last, 'Cash freed up');
    });

    test('handles alignment markers and tables without a header', () {
      final withAlign = parseMarkdownTable('| A | B |\n|:--|--:|\n| 1 | 2 |')!;
      expect(withAlign.header, ['A', 'B']);
      expect(withAlign.rows, [
        ['1', '2']
      ]);

      final noHeader = parseMarkdownTable('| 1 | 2 |\n| 3 | 4 |')!;
      expect(noHeader.header, isEmpty);
      expect(noHeader.rows.length, 2);
    });

    test('returns null when there is nothing to show', () {
      expect(parseMarkdownTable(''), isNull);
      expect(parseMarkdownTable('| A | B |\n|---|---|'), isNull);
      expect(parseMarkdownTable('no table here'), isNull);
    });
  });

  testWidgets('tables render stacked and fully visible on a phone-width screen',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AppMarkdown(_table))),
    ));
    await tester.pumpAndSettle();

    // Every field is on screen, not hidden in a sideways-scrolling grid.
    expect(find.textContaining('Only 3 left and it sells 12 a day'), findsOneWidget);
    expect(find.textContaining('No stock-outs this week'), findsOneWidget);
    expect(find.text('REASON'), findsNWidgets(2));
    expect(find.text('EXPECTED RESULT'), findsNWidgets(2));
    expect(find.byType(Table), findsNothing);
    expect(tester.takeException(), isNull);

    // Nothing is laid out wider than the 400px screen.
    for (final element in find.textContaining('Peanuts').evaluate()) {
      final box = element.renderObject! as RenderBox;
      expect(box.localToGlobal(Offset.zero).dx + box.size.width, lessThanOrEqualTo(400));
    }
  });
}
