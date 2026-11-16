import 'dart:convert';

import 'package:axon_pos/features/payments/domain/money_in_today.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sales and collections are added together by how they were paid', () {
    final result = moneyInToday(
      sales: [
        (method: 'CASH', total: 500.0, reference: null),
        (method: 'MPESA_RECORDED', total: 300.0, reference: null),
        (method: 'CREDIT', total: 900.0, reference: null),
      ],
      collections: [
        (method: 'CASH', amount: 200.0),
        (method: 'MPESA', amount: 1000.0),
      ],
    );

    expect(result.byMethod, {'Cash': 70000, 'M-Pesa': 130000});
    expect(result.fromSales, 800);
    expect(result.fromCollections, 1200);
    expect(result.total, 2000);
  });

  test('a split sale counts its cash and M-Pesa parts but not the credit part',
      () {
    final result = moneyInToday(
      sales: [
        (
          method: 'SPLIT',
          total: 1000.0,
          reference: jsonEncode([
            {'method': 'CASH', 'amount': 400},
            {'method': 'MPESA', 'amount': 100},
            {'method': 'CREDIT', 'amount': 500},
          ]),
        ),
      ],
      collections: const [],
    );

    expect(result.byMethod, {'Cash': 40000, 'M-Pesa': 10000});
    expect(result.total, 500);
  });

  test('nothing received shows as empty, and odd method names go to Other', () {
    expect(
      moneyInToday(sales: const [], collections: const []).isEmpty,
      isTrue,
    );
    final other = moneyInToday(
      sales: const [],
      collections: [(method: 'voucher', amount: 50.0)],
    );
    expect(other.byMethod, {'Other': 5000});
  });
}
