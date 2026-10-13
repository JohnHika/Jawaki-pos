import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/sales/presentation/providers/sales_provider.dart';

void main() {
  group('receiptHeaderName', () {
    test('uses the business and branch when both are known', () {
      expect(
        receiptHeaderName({
          'tenant': {'name': 'Mama Njeri Supplies'},
          'branchName': 'Main',
        }),
        'Mama Njeri Supplies - Main',
      );
    });

    test('does not repeat a branch named like the business', () {
      expect(
        receiptHeaderName({'tenantName': 'Kamau Stores', 'branchName': 'kamau stores'}),
        'Kamau Stores',
      );
    });

    test('drops the branch when the line would overflow a 58mm receipt', () {
      expect(
        receiptHeaderName({
          'companyName': 'Mama Njeri General Supplies Ltd',
          'branchName': 'Tom Mboya Street',
        }),
        'Mama Njeri General Supplies Ltd',
      );
    });

    test('falls back to the branch, then to null (caller shows a default)', () {
      expect(receiptHeaderName({'branchName': 'Main Shop'}), 'Main Shop');
      expect(receiptHeaderName({'name': 'x'}), isNull);
      expect(receiptHeaderName(null), isNull);
    });
  });
}
