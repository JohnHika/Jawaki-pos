import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/services/storage_service.dart';

void main() {
  group('pending merchant M-Pesa storage key', () {
    const defaultTenantId = 'shop/one';
    const defaultBranchId = 'branch:main';
    const defaultUserId = 'cashier@example.test';

    String keyFor({
      String tenantId = defaultTenantId,
      String branchId = defaultBranchId,
      String userId = defaultUserId,
    }) =>
        StorageService.pendingMerchantMpesaKey(
          tenantId: tenantId,
          branchId: branchId,
          userId: userId,
        );

    test('is stable for the same cashier and business location', () {
      expect(keyFor(), keyFor());
    });

    test('isolates records by tenant, branch, and cashier', () {
      final base = keyFor();
      expect(keyFor(tenantId: 'shop/two'), isNot(base));
      expect(keyFor(branchId: 'branch:other'), isNot(base));
      expect(keyFor(userId: 'another-cashier'), isNot(base));
    });

    test('encodes scope values so delimiters cannot collide', () {
      expect(keyFor(), isNot(keyFor(tenantId: 'shop', branchId: 'one')));
      expect(keyFor(), contains('shop%2Fone'));
      expect(keyFor(), contains('branch%3Amain'));
    });
  });
}
