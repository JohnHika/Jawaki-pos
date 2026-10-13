import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/sales/domain/receipt_search.dart';

bool _match(
  String query, {
  String saleId = 'abcd1234-0000-4000-8000-000000000000',
  String receiptNumber = 'RCP-2026-0042',
  String paymentMethod = 'MPESA',
  String? name = 'Wanjiru Kamau',
  String? phone = '+254712345678',
}) =>
    receiptMatchesQuery(
      saleId: saleId,
      receiptNumber: receiptNumber,
      paymentMethod: paymentMethod,
      customerName: name,
      customerPhone: phone,
      query: query,
    );

void main() {
  group('receiptMatchesQuery', () {
    test('an empty query matches everything', () {
      expect(_match(''), isTrue);
      expect(_match('   '), isTrue);
    });

    test('matches the short code shown on the card, with or without #', () {
      expect(_match('#ABCD1234'), isTrue);
      expect(_match('abcd'), isTrue);
    });

    test('matches receipt number, customer name and payment method', () {
      expect(_match('0042'), isTrue);
      expect(_match('wanjiru'), isTrue);
      expect(_match('KAMAU'), isTrue);
      expect(_match('mpesa'), isTrue);
    });

    test('matches phone numbers across local and international formats', () {
      expect(_match('0712 345 678'), isTrue);
      expect(_match('0712345'), isTrue);
      expect(_match('254712'), isTrue);
      expect(_match('+254 712'), isTrue);
      expect(_match('2547'), isTrue);
      expect(_match('712345678'), isTrue);
    });

    test('does not match a different customer or number', () {
      expect(_match('otieno'), isFalse);
      expect(_match('0799'), isFalse);
      expect(_match('0042', receiptNumber: 'RCP-1', saleId: 'zzzzzzzz'), isFalse);
    });

    test('ignores phone matching for tiny digit fragments', () {
      expect(_match('71', name: null, receiptNumber: 'X', saleId: 'zzzzzzzz'),
          isFalse);
    });

    test('handles a sale with no customer', () {
      expect(_match('0712', name: null, phone: null), isFalse);
      expect(_match('rcp', name: null, phone: null), isTrue);
    });
  });
}
