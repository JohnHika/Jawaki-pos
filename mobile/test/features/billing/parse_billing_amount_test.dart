import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';

void main() {
  test('money sent as a string by the server no longer breaks the page', () {
    expect(parseBillingAmount('3200.00'), 3200);
    expect(parseBillingAmount(6500), 6500);
    expect(parseBillingAmount(null), 0);
    expect(parseBillingAmount('not a number'), 0);
  });
}
