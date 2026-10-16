// ignore_for_file: prefer_const_literals_to_create_immutables
import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientLicense', () {
    test('everything is available while the operator has enforcement off', () {
      final license = ClientLicense.fromMap({
        'enforced': false,
        'features': {'analytics': false, 'aiAssistant': false},
        'planFeatures': {'analytics': false, 'aiAssistant': false},
      });
      expect(license.allows(LicensedFeature.analytics), isTrue);
      expect(license.lockedFeatures, ['analytics', 'aiAssistant']);
    });

    test('locks only the modules the server says are not licensed', () {
      final license = ClientLicense.fromMap({
        'enforced': true,
        'features': {'analytics': true, 'customReports': false},
      });
      expect(license.allows(LicensedFeature.analytics), isTrue);
      expect(license.allows(LicensedFeature.customReports), isFalse);
      // A module the server never mentioned is not locked by guesswork.
      expect(license.allows('somethingNew'), isTrue);
    });

    test('an expired licence locks every module', () {
      final license = ClientLicense.fromMap({
        'enforced': true,
        'expired': true,
        'features': {'analytics': true},
      });
      expect(license.allows(LicensedFeature.analytics), isFalse);
    });

    test('survives a round trip through the offline cache', () {
      final original = ClientLicense.fromMap({
        'enforced': true,
        'features': {'analytics': true, 'aiAssistant': false},
        'planFeatures': {'analytics': true, 'aiAssistant': false},
        'limits': {'maxBranches': 3, 'maxUsers': 10},
        'licenseKey': 'AXON-ABCD-EFGH-JKLM',
      });
      final copy = ClientLicense.fromMap(original.toMap());
      expect(copy.allows(LicensedFeature.aiAssistant), isFalse);
      expect(copy.maxBranches, 3);
      expect(copy.maxUsers, 10);
      expect(copy.licenseKey, 'AXON-ABCD-EFGH-JKLM');
    });
  });

  group('BillingEntitlement.license', () {
    test('is parsed from the live entitlement', () {
      final e = BillingEntitlement.fromMap({
        'plan': 'CORE',
        'status': 'ACTIVE',
        'license': {
          'enforced': true,
          'features': {'aiAssistant': false},
        },
      });
      expect(e.allows(LicensedFeature.aiAssistant), isFalse);
      expect(e.allows(LicensedFeature.analytics), isTrue);
    });

    test('an older backend with no licence block locks nothing', () {
      final e =
          BillingEntitlement.fromMap({'plan': 'CORE', 'status': 'ACTIVE'});
      expect(e.license, isNull);
      expect(e.allows(LicensedFeature.aiAssistant), isTrue);
    });

    test('the signed offline token payload does not break parsing', () {
      // The offline token carries `features` as module flags, not seat limits.
      final e = BillingEntitlement.fromMap({
        'plan': 'CORE',
        'status': 'ACTIVE',
        'features': {'analytics': true, 'aiAssistant': false},
        'enforced': true,
      });
      expect(e.maxBranches, isNull);
      expect(e.license, isNull);
    });
  });
}
