import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/theme/design_system.dart';

void main() {
  Future<double> opacityOf(WidgetTester tester, VoidCallback? onPressed) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GradientButton(label: 'Pay', onPressed: onPressed),
      ),
    ));
    final finder = find.ancestor(
      of: find.text('Pay'),
      matching: find.byType(Opacity),
    );
    if (finder.evaluate().isEmpty) return 1;
    return tester.widget<Opacity>(finder.first).opacity;
  }

  testWidgets('a button with no handler is dimmed', (tester) async {
    expect(await opacityOf(tester, null), lessThan(1));
  });

  testWidgets('a button with a handler is fully opaque', (tester) async {
    expect(await opacityOf(tester, () {}), 1);
  });
}
