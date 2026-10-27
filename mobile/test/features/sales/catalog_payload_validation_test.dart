import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _product({Object? pricingTiers = const []}) => {
      'id': 'product-1',
      'name': 'Tea',
      'sku': 'TEA-1',
      'price': 100,
      if (pricingTiers != _omitted) 'pricingTiers': pricingTiers,
    };

const _omitted = Object();

void main() {
  test('accepts products with an explicit empty tier list', () {
    final products = validateCatalogProductPayload([_product()]);

    expect(products, hasLength(1));
  });

  test('rejects a missing or non-list tier payload', () {
    expect(
      () => validateCatalogProductPayload([_product(pricingTiers: _omitted)]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateCatalogProductPayload([_product(pricingTiers: 'invalid')]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed tier rows instead of silently dropping them', () {
    expect(
      () => validateCatalogProductPayload([
        _product(pricingTiers: [
          {
            'unit': 'carton',
            'quantityPerUnit': 12,
            'price': 1000,
          },
          {
            'unit': 'dozen',
            'quantityPerUnit': 12,
          },
        ]),
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects non-positive quantities and out-of-range prices', () {
    for (final tier in [
      {'unit': 'carton', 'quantityPerUnit': 0, 'price': 1000},
      {'unit': 'carton', 'quantityPerUnit': 12, 'price': 10000001},
    ]) {
      expect(
        () => validateCatalogProductPayload([
          _product(pricingTiers: [tier])
        ]),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
