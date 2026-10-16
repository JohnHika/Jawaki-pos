import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all-caps supplier names are shown in normal capitalisation', () {
    expect(tidySupplierName('FRESH FARM DISTRIBUTORS'),
        'Fresh Farm Distributors');
    expect(tidySupplierName('Fresh Farm Distributors'),
        'Fresh Farm Distributors');
    expect(tidySupplierName('  KAMAU  &  SONS '), 'Kamau & Sons');
  });

  test('mixed-case and non-letter names are left alone', () {
    expect(tidySupplierName('iPhone Hub'), 'iPhone Hub');
    expect(tidySupplierName('254'), '254');
    expect(tidySupplierName(''), '');
  });
}
