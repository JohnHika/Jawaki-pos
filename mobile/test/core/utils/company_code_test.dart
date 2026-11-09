import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axon_pos/core/utils/company_code.dart';

void main() {
  const formatter = CompanyCodeFormatter();

  TextEditingValue type(String before, String typed) {
    final old = TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: before.length),
    );
    final next = before + typed;
    return formatter.formatEditUpdate(
      old,
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      ),
    );
  }

  test('a typed space shows as a hyphen', () {
    final value = type('levisa', ' ');
    expect(value.text, 'levisa-');
    expect(value.selection.baseOffset, 7);
    expect(type('levisa-', 'v').text, 'levisa-v');
  });

  test('a second space does not add a second hyphen', () {
    expect(type('levisa-', ' ').text, 'levisa-');
  });

  test('capitals become lowercase and symbols are dropped', () {
    expect(type('', 'Levisa Ventures!').text, 'levisa-ventures');
    expect(type('', ' Mama_Njeri  Shop').text, 'mama-njeri-shop');
  });

  test('normalize trims the ends and checks the shape', () {
    expect(CompanyCode.normalize('  Levisa Ventures  '), 'levisa-ventures');
    expect(CompanyCode.normalize('levisa-'), 'levisa');
    expect(CompanyCode.isValid('levisa-ventures'), isTrue);
    expect(CompanyCode.isValid('levisa ventures'), isFalse);
  });

  testWidgets('the company code field never shows a space', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextField(
          controller: controller,
          inputFormatters: const [CompanyCodeFormatter()],
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'levisa ventures');
    expect(controller.text, 'levisa-ventures');
  });
}
