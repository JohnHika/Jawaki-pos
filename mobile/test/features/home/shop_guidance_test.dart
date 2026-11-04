import 'dart:convert';

import 'package:axon_pos/features/home/domain/shop_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

({String method, String? reference, double total, String status}) sale(
  String method,
  double total, {
  String? reference,
  String status = 'COMPLETED',
}) =>
    (method: method, reference: reference, total: total, status: status);

void main() {
  group('splitTakings', () {
    test('groups cash, recorded, credit and other', () {
      final split = splitTakings([
        sale('CASH', 100),
        sale('cash', 50),
        sale('MPESA_RECORDED', 200),
        sale('BANK_RECORDED', 300),
        sale('CREDIT', 70),
        sale('MPESA', 40),
      ]);
      expect(split.cash, 150);
      expect(split.recorded, 500);
      expect(split.credit, 70);
      expect(split.other, 40);
      expect(split.total, 760);
      expect(split.recordedCount, 2);
    });

    test('leaves out voided and refunded sales', () {
      final split = splitTakings([
        sale('CASH', 100),
        sale('CASH', 999, status: 'VOIDED'),
        sale('MPESA_RECORDED', 500, status: 'refunded'),
      ]);
      expect(split.total, 100);
      expect(split.recordedCount, 0);
    });

    test('divides a split sale by its parts', () {
      final split = splitTakings([
        sale(
          'SPLIT',
          500,
          reference: jsonEncode([
            {'method': 'CASH', 'amount': 200},
            {'method': 'MPESA_RECORDED', 'amount': 300},
          ]),
        ),
      ]);
      expect(split.cash, 200);
      expect(split.recorded, 300);
      expect(split.recordedCount, 1);
    });

    test('a split that cannot be read still keeps the total', () {
      final split = splitTakings([
        sale('SPLIT', 500, reference: 'not json'),
        sale('SPLIT', 400, reference: jsonEncode([
          {'method': 'CASH', 'amount': 100},
        ])),
      ]);
      expect(split.other, 900);
      expect(split.total, 900);
    });

    test('ignores sales with no usable amount', () {
      final split = splitTakings([
        sale('CASH', 0),
        sale('CASH', double.nan),
        sale('CASH', -5),
      ]);
      expect(split.total, 0);
    });
  });

  group('tipsForProfile', () {
    test('every known shop type gets at least two suggestions', () {
      for (final id in [
        'general_retail', 'grocery', 'cafe_takeaway', 'bakery_food_counter',
        'market_stall', 'fashion', 'electronics', 'hardware', 'beauty',
        'wholesale', 'stationery', 'auto_parts', 'pharmacy_retail', 'agrovet',
        'butchery', 'beverages', 'bookshop', 'kamukunji_counter',
        'service_counter',
      ]) {
        expect(tipsForProfile(id).length, greaterThanOrEqualTo(2), reason: id);
      }
    });

    test('an unknown or custom layout falls back to general suggestions', () {
      expect(tipsForProfile('custom').length, 2);
      expect(tipsForProfile('something_new').length, 2);
    });

    test('a pharmacy is told about expiry, a butchery about weight', () {
      expect(tipsForProfile('pharmacy_retail').first.title, contains('expiry'));
      expect(tipsForProfile('butchery').first.title, contains('weight'));
    });

    test('every suggestion opens an app route', () {
      for (final tip in [
        ...tipsForProfile('grocery'),
        ...tipsForProfile('hardware'),
        ...tipsForProfile('pharmacy_retail'),
      ]) {
        expect(tip.path, startsWith('/'));
        expect(tip.action, isNotEmpty);
      }
    });
  });

  test('what is new is never empty and uses plain words', () {
    expect(kWhatsNew, isNotEmpty);
    for (final item in kWhatsNew) {
      expect(item.title, isNotEmpty);
      expect(item.body, isNotEmpty);
    }
  });
}
