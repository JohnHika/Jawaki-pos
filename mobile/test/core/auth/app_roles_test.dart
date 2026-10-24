import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/auth/app_roles.dart';

void main() {
  group('RolePermissions navigation', () {
    test('only users who can create sales see the POS tab', () {
      expect(RolePermissions(const ['sales.create']).canSeePOS, isTrue);
      expect(RolePermissions(const ['sales.view']).canSeePOS, isFalse);
      expect(RolePermissions(const []).canSeePOS, isFalse);
    });

    test('payment and customer entries follow their view permissions', () {
      expect(
        RolePermissions(const ['payments.view_status']).canSeePayments,
        isTrue,
      );
      expect(RolePermissions(const []).canSeePayments, isFalse);
      expect(RolePermissions(const ['customers.view']).canSeeCustomers, isTrue);
      expect(RolePermissions(const []).canSeeCustomers, isFalse);
    });

    test('staff invitations require create permission separately from user view', () {
      expect(RolePermissions(const ['users.view']).canManageUsers, isTrue);
      expect(RolePermissions(const ['users.view']).canInviteStaff, isFalse);
      expect(RolePermissions(const ['users.create']).canInviteStaff, isTrue);
    });

    test('users without POS land on a permitted work surface', () {
      expect(
        RolePermissions(const ['products.view']).homePath,
        '/products',
      );
      expect(RolePermissions(const ['sales.view']).homePath, '/receipts');
      expect(RolePermissions(const []).homePath, '/settings');
    });
  });
}
