import 'package:axon_pos/core/utils/stock_quantity_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildStockQuantityPresentation', () {
    test('shows current stock in the last received packaging unit', () {
      final result = buildStockQuantityPresentation(
        baseQuantity: 240,
        baseUnit: 'piece',
        preferredUnit: 'dozen',
        unitsPerPreferredUnit: 12,
        lastReceivedQuantity: 20,
      );

      expect(result.primary, '20 dozen');
      expect(result.secondary, '240 piece');
      expect(result.lastReceived, 'Last received: 20 dozen');
    });

    test('keeps base unit when no packaging preference exists', () {
      final result = buildStockQuantityPresentation(
        baseQuantity: 7,
        baseUnit: 'piece',
      );

      expect(result.primary, '7 piece');
      expect(result.secondary, isNull);
      expect(result.lastReceived, isNull);
    });

    test('formats partial packaging quantities without rounding stock away',
        () {
      final result = buildStockQuantityPresentation(
        baseQuantity: 25,
        baseUnit: 'piece',
        preferredUnit: 'dozen',
        unitsPerPreferredUnit: 12,
      );

      expect(result.primary, '2.08 dozen');
      expect(result.secondary, '25 piece');
    });
  });

  group('parseReceivedStockNote', () {
    test('prefers aggregate receipt metadata shared across batch movements',
        () {
      final parsed = parseReceivedStockNote(
        '[Receipt metadata: quantity=20; unit=half%20dozen; unitsPerQuantity=6] '
        'Received 10 half dozen = 60 pieces',
      );

      expect(parsed?.quantity, 20);
      expect(parsed?.unit, 'half dozen');
      expect(parsed?.unitsPerQuantity, 6);
    });

    test('restores packaging metadata from a pulled stock movement', () {
      final result = parseReceivedStockNote(
        'Received 20 dozen = 240 piece. Supplier invoice 44',
      );

      expect(result, isNotNull);
      expect(result!.quantity, 20);
      expect(result.unit, 'dozen');
      expect(result.unitsPerQuantity, 12);
    });

    test('supports packaging unit names containing spaces', () {
      final result = parseReceivedStockNote(
        'Received 5 half dozen = 30 piece',
      );

      expect(result, isNotNull);
      expect(result!.quantity, 5);
      expect(result.unit, 'half dozen');
      expect(result.unitsPerQuantity, 6);
    });

    test('ignores unrelated movement notes', () {
      expect(parseReceivedStockNote('Sale from batch ABC-001'), isNull);
    });
  });
}
