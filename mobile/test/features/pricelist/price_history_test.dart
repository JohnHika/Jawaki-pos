import 'package:axon_pos/features/pricelist/domain/price_freshness.dart';
import 'package:axon_pos/features/pricelist/domain/price_history.dart';
import 'package:axon_pos/features/pricelist/domain/price_list_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day1 = DateTime(2026, 11, 10, 9);
  final day3 = DateTime(2026, 11, 12, 9);

  group('PriceHistory', () {
    test('the first price seen is a starting point, not a move', () {
      final history = PriceHistory.empty.update({'a': 100}, day1);
      expect(history.entries['a']!.price, 100);
      expect(history.changeFor('a', 100, day1), isNull);
    });

    test('a different price later is recorded as a move with the old price', () {
      final first = PriceHistory.empty.update({'a': 100}, day1);
      final next = first.update({'a': 115}, day3);
      final change = next.changeFor('a', 115, day3)!;
      expect(change.previous, 100);
      expect(change.current, 115);
      expect(change.direction, PriceDirection.up);
      expect(priceChangeLabel(change, priceKes), 'Up KES 15');

      final down = next.update({'a': 90}, day3).changeFor('a', 90, day3)!;
      expect(down.direction, PriceDirection.down);
      expect(priceChangeLabel(down, priceKes), 'Down KES 25');
    });

    test('the same prices return the same object so nothing is saved again', () {
      final first = PriceHistory.empty.update({'a': 100}, day1);
      expect(identical(first.update({'a': 100}, day3), first), isTrue);
    });

    test('a move stops showing after a week or when the price moved again', () {
      final moved = PriceHistory.empty
          .update({'a': 100}, day1)
          .update({'a': 120}, day1);
      expect(moved.changeFor('a', 120, day1.add(const Duration(days: 6))),
          isNotNull);
      expect(moved.changeFor('a', 120, day1.add(const Duration(days: 8))),
          isNull);
      // The price on screen is no longer the one the move ended on.
      expect(moved.changeFor('a', 130, day1), isNull);
    });

    test('products missing from a short read keep their history', () {
      final history = PriceHistory.empty
          .update({'a': 100, 'b': 50}, day1)
          .update({'a': 100}, day3);
      expect(history.entries.containsKey('b'), isTrue);
      expect(PriceHistory.empty.update({}, day1).isEmpty, isTrue);
    });

    test('survives being saved and read back', () {
      final history = PriceHistory.empty
          .update({'a': 100, 'b': 5}, day1)
          .update({'a': 110, 'b': 5}, day3);
      final copy = PriceHistory.fromJson(history.toJson());
      expect(copy.changeFor('a', 110, day3)!.previous, 100);
      expect(copy.changeFor('b', 5, day3), isNull);
      expect(PriceHistory.fromJson('nonsense').isEmpty, isTrue);
    });
  });

  group('priceFreshnessLabel', () {
    final now = DateTime(2026, 11, 15, 12);

    test('says how long ago in plain words', () {
      expect(priceFreshnessLabel(null, now), 'Not updated yet');
      expect(priceFreshnessLabel(now, now), 'Updated just now');
      expect(priceFreshnessLabel(now.subtract(const Duration(seconds: 30)), now),
          'Updated just now');
      expect(priceFreshnessLabel(now.subtract(const Duration(minutes: 5)), now),
          'Updated 5 min ago');
      expect(priceFreshnessLabel(now.subtract(const Duration(hours: 3)), now),
          'Updated 3 h ago');
      expect(priceFreshnessLabel(DateTime(2026, 11, 14, 8), now),
          'Updated yesterday');
      expect(priceFreshnessLabel(DateTime(2026, 11, 12, 18), now),
          'Updated 3 days ago');
      expect(priceFreshnessLabel(DateTime(2026, 11, 1, 18), now),
          'Updated 1 Nov');
    });

    test('a clock set slightly behind never says a negative age', () {
      expect(priceFreshnessLabel(now.add(const Duration(minutes: 2)), now),
          'Updated just now');
    });

    test('priceChangeWhen', () {
      expect(priceChangeWhen(now, now), 'today');
      expect(priceChangeWhen(DateTime(2026, 11, 14, 23), now), 'yesterday');
      expect(priceChangeWhen(DateTime(2026, 11, 12), now), '3 days ago');
    });
  });
}
