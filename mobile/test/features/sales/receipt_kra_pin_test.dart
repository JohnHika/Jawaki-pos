import 'package:axon_pos/features/sales/presentation/receipts_desktop/receipt_thermal_text.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _receipt({String? pin}) => {
      'branchName': 'Levisa Ventures',
      'branchAddress': 'Mathais Plaza, Nairobi',
      'branchPhone': '0712345678',
      if (pin != null) 'shopKraPin': pin,
      'items': <Map<String, dynamic>>[],
      'subtotal': 0,
      'tax': 0,
      'total': 0,
      'paymentMethod': 'CASH',
      'createdAt': DateTime(2026, 11, 16, 10).toIso8601String(),
    };

void main() {
  test('the shop KRA PIN prints under the phone when the receipt carries it',
      () {
    final text = renderThermalReceiptText(
      _receipt(pin: 'A123456789B'),
      fallbackNumber: 'ABCDEF12',
      showTax: false,
    );
    expect(text, contains('KRA PIN: A123456789B'));
  });

  test('without the PIN on the receipt, nothing about it is printed', () {
    final text = renderThermalReceiptText(
      _receipt(),
      fallbackNumber: 'ABCDEF12',
      showTax: false,
    );
    expect(text, isNot(contains('KRA')));
  });
}
