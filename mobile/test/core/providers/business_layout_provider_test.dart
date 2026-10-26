import 'package:flutter_test/flutter_test.dart';

import 'package:axon_pos/core/providers/business_layout_provider.dart';

void main() {
  group('businessLayoutFromUser', () {
    test('applies bookshop language and suggested work areas', () {
      final layout = businessLayoutFromUser({
        'tenant': {
          'settings': {
            'businessLayout': {'profileId': 'bookshop'},
          },
        },
      });

      expect(layout.productSingular, 'Book');
      expect(layout.productsLabel, 'Books');
      expect(layout.productCodeLabel, 'ISBN / barcode (optional)');
      expect(layout.productCodeHint, 'Enter the ISBN or scan code');
      expect(layout.actionLabel('/products', 'Products'), 'Books');
      expect(layout.priorityPaths, contains('/products'));
      expect(layout.priorityPaths, contains('/customers'));
    });

    test('round-trips custom action labels and ignores unknown paths', () {
      final layout = businessLayoutFromUser({
        'tenant': {
          'settings': {
            'businessLayout': {
              'profileId': 'kamukunji_counter',
              'priorityPaths': ['/finance', '/products', '/not-a-screen'],
              'actionLabels': {
                '/products': 'Stock desk',
                '/not-a-screen': 'Hidden screen',
                '/finance': 'Cash book',
              },
            },
          },
        },
      });

      expect(layout.productsLabel, 'Stock items');
      expect(layout.priorityPaths, ['/finance', '/products']);
      expect(layout.actionLabel('/products', 'Products'), 'Stock desk');
      expect(layout.actionLabel('/finance', 'Finance'), 'Cash book');
      expect(layout.actionLabels.containsKey('/not-a-screen'), isFalse);

      final restored = businessLayoutFromUser({
        'tenant': {
          'settings': {'businessLayout': layout.toJson()},
        },
      });
      expect(restored.actionLabels, layout.actionLabels);
      expect(restored.priorityPaths, layout.priorityPaths);
    });

    test('falls back safely for old or unknown profile settings', () {
      final old = businessLayoutFromUser({
        'tenant': {'settings': <String, dynamic>{}},
      });
      final unknown = businessLayoutFromUser({
        'tenant': {
          'settings': {
            'businessLayout': {'profileId': 'unknown-profile'},
          },
        },
      });

      expect(old.profileId, 'general_retail');
      expect(unknown.profileId, 'general_retail');
      expect(old.productsLabel, 'Products');
    });
  });
}
