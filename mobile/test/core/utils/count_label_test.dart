import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/utils/format.dart';

void main() {
  paymentLabelTests();
  test('countLabel agrees the word with the number', () {
    expect(countLabel(1, 'transaction'), '1 transaction');
    expect(countLabel(0, 'transaction'), '0 transactions');
    expect(countLabel(2, 'item'), '2 items');
    expect(countLabel('3', 'sale'), '3 sales');
    expect(countLabel(null, 'sale'), '0 sales');
    expect(countLabel(2, 'batch', plural: 'batches'), '2 batches');
    expect(countLabel(2.5, 'kg', plural: 'kg'), '2.5 kg');
  });
}

void paymentLabelTests() {
  test('paymentMethodLabel gives customer-facing names', () {
    expect(paymentMethodLabel('MPESA'), 'M-Pesa');
    expect(paymentMethodLabel('mpesa'), 'M-Pesa');
    expect(paymentMethodLabel('TOURISTTAP'), 'TouristTap');
    expect(paymentMethodLabel('CASH'), 'Cash');
    expect(paymentMethodLabel('BANK_TRANSFER'), 'Bank transfer');
    expect(paymentMethodLabel(''), 'Unknown');
    expect(paymentMethodLabel(null), 'Unknown');
  });
}
