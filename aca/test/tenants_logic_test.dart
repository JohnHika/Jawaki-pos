import 'package:aca/core/permissions.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/tenants/license_logic.dart';
import 'package:aca/features/tenants/tenants_logic.dart';
import 'package:flutter_test/flutter_test.dart';

LicenseView licenseFixture({
  String enforcement = 'off',
  Map<String, dynamic>? features,
  Map<String, dynamic>? limits,
  String? validUntil,
  String? note,
  String? licenseKey,
}) =>
    LicenseView.fromJson({
      'plan': 'CORE',
      'enforcement': enforcement,
      'features': features ??
          {
            'analytics': {'allowed': true, 'source': 'plan'},
            'customReports': {'allowed': false, 'source': 'plan'},
            'aiAssistant': {'allowed': true, 'source': 'override'},
            'multiCurrency': {'allowed': false, 'source': 'override'},
          },
      'limits': limits ?? {'maxBranches': 3, 'maxUsers': 10},
      'validUntil': validUntil,
      'expired': false,
      'licenseKey': licenseKey,
      'note': note,
      'unknownPlan': false,
    });

void main() {
  group('status filter mapping', () {
    test('normalises whatever the caller passes', () {
      expect(normalizeStatus('past_due'), 'PAST_DUE');
      expect(normalizeStatus(' Past due '), 'PAST_DUE');
      expect(normalizeStatus('ACTIVE'), 'ACTIVE');
      expect(normalizeStatus('cancelled'), 'CANCELLED');
      expect(normalizeStatus('DELETED'), isNull);
      expect(normalizeStatus(''), isNull);
      expect(normalizeStatus(null), isNull);
    });

    test('finds the chip to select', () {
      expect(statusFilterIndex(null), 0);
      expect(statusFilterIndex('ACTIVE'), 1);
      expect(statusFilterIndex('suspended'), 4);
      expect(statusFilterIndex('nonsense'), 0);
      expect(statusFilterLabel('PAST_DUE'), 'Past due');
      expect(kStatusFilters.first.value, isNull);
      expect(kStatusFilters.map((f) => f.label), ['All', 'Active', 'Trial', 'Past due', 'Suspended', 'Cancelled']);
    });

    test('count wording', () {
      expect(companyCountLabel(27), '27 companies');
      expect(companyCountLabel(1), '1 company');
      expect(companyCountLabel(0), '0 companies');
      expect(companyCountLabel(3, filtered: true), '3 companies found');
      expect(plural(2, 'user'), '2 users');
      expect(plural(1, 'branch', 'branches'), '1 branch');
    });
  });

  group('app versions', () {
    test('compare numerically, not alphabetically', () {
      expect(compareVersions('1.0.9', '1.0.74'), -1);
      expect(compareVersions('1.0.74', '1.0.9'), 1);
      expect(compareVersions('1.0.74', '1.0.74'), 0);
      expect(compareVersions('v1.2', '1.2.0'), 0);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
      expect(compareVersions('1.0.74+3', '1.0.74+10'), -1);
    });

    test('newest ignores blanks and unknown', () {
      expect(newestVersion(['1.0.70', null, '1.0.74', '', 'unknown', '1.0.9']), '1.0.74');
      expect(newestVersion([null, '']), isNull);
      expect(newestVersion(const []), isNull);
    });

    test('outdated only when known and older than the newest', () {
      expect(isOutdatedVersion('1.0.70', '1.0.74'), isTrue);
      expect(isOutdatedVersion('1.0.74', '1.0.74'), isFalse);
      expect(isOutdatedVersion('1.0.75', '1.0.74'), isFalse);
      expect(isOutdatedVersion(null, '1.0.74'), isFalse);
      expect(isOutdatedVersion('unknown', '1.0.74'), isFalse);
      expect(isOutdatedVersion('1.0.70', null), isFalse);
    });
  });

  group('subscription end', () {
    final now = DateTime(2026, 10, 21, 10);
    test('tone: overdue is danger, last week is a warning', () {
      expect(endTone(DateTime(2026, 10, 18), now: now), Tone.danger);
      expect(endTone(DateTime(2026, 10, 20, 23), now: now), Tone.danger);
      expect(endTone(DateTime(2026, 10, 21, 23), now: now), Tone.warning); // ends today
      expect(endTone(DateTime(2026, 10, 28), now: now), Tone.warning);
      expect(endTone(DateTime(2026, 10, 29), now: now), Tone.neutral);
      expect(endTone(null, now: now), Tone.neutral);
    });

    test('extending counts from the current end, or from now when lapsed', () {
      expect(projectedPeriodEnd(DateTime(2026, 11, 1), 7, now: now), DateTime(2026, 11, 8));
      expect(projectedPeriodEnd(DateTime(2026, 10, 1), 7, now: now), DateTime(2026, 10, 28, 10));
      expect(projectedPeriodEnd(null, 30, now: now), DateTime(2026, 11, 20, 10));
    });

    test('extend days accepts 1..365 only', () {
      expect(parseExtendDays('7'), 7);
      expect(parseExtendDays(' 365 '), 365);
      expect(parseExtendDays('1'), 1);
      expect(parseExtendDays('0'), isNull);
      expect(parseExtendDays('366'), isNull);
      expect(parseExtendDays('1.5'), isNull);
      expect(parseExtendDays('abc'), isNull);
      expect(parseExtendDays(''), isNull);
    });

    test('credit amount parsing', () {
      expect(parseKesAmount('1,500'), 1500);
      expect(parseKesAmount('250.505'), 250.51);
      expect(parseKesAmount(' 1 '), 1);
      expect(parseKesAmount('0.5'), isNull);
      expect(parseKesAmount('-20'), isNull);
      expect(parseKesAmount('abc'), isNull);
      expect(parseKesAmount(''), isNull);
    });

    test('seat wording', () {
      expect(seatsLabel(2, 10), '2 of 10');
      expect(seatsLabel(2, kUnlimitedSeats), '2 (no limit)');
      expect(seatsFull(3, 3), isTrue);
      expect(seatsFull(2, 3), isFalse);
      expect(seatsFull(500, kUnlimitedSeats), isFalse);
    });
  });

  group('lists', () {
    TenantNote note(String id, {bool pinned = false, int minute = 0}) => TenantNote(
          id: id,
          tenantId: 't',
          authorEmail: 'a@b.c',
          body: id,
          pinned: pinned,
          createdAt: DateTime(2026, 10, 21, 10, minute),
        );

    test('notes: pinned first, newest first inside each group', () {
      final sorted = sortNotes([note('old', minute: 1), note('new', minute: 9), note('pinOld', pinned: true, minute: 2), note('pinNew', pinned: true, minute: 8)]);
      expect(sorted.map((n) => n.id).toList(), ['pinNew', 'pinOld', 'new', 'old']);
    });

    test('mergePage drops rows that already arrived', () {
      final merged = mergePage<String>(['a', 'b'], ['b', 'c', 'c', 'd'], (s) => s);
      expect(merged, ['a', 'b', 'c', 'd']);
    });
  });

  group('wording and tones', () {
    test('credit reference', () {
      Invoice inv(String? ref) => Invoice.fromJson({'id': 'i', 'amount': '-100', 'reference': ref});
      expect(creditReason(inv('CREDIT:Downtime in October')), 'Downtime in October');
      expect(creditReason(inv('credit:  spaced ')), 'spaced');
      expect(creditReason(inv('CREDIT:')), isNull);
      expect(creditReason(inv('QA-INV-1')), isNull);
      expect(creditReason(inv(null)), isNull);
    });

    test('provider labels', () {
      expect(providerLabel('MPESA'), 'M-Pesa');
      expect(providerLabel('PAYSTACK'), 'Paystack');
      expect(providerLabel('CREDIT'), 'Credit');
      expect(providerLabel('BANK_TRANSFER'), 'Bank transfer');
      expect(providerLabel(null), '—');
    });

    test('tones', () {
      expect(invoiceTone('PAID'), Tone.success);
      expect(invoiceTone('PENDING'), Tone.warning);
      expect(activationTone('PAID'), Tone.success);
      expect(activationTone('PENDING'), Tone.warning);
      expect(activationTone(null), Tone.neutral);
      expect(companyRoleTone('ADMIN'), Tone.brand);
      expect(companyRoleTone('CASHIER'), Tone.neutral);
    });
  });

  group('which actions a role sees', () {
    bool Function(String) can(Set<String> perms) => perms.contains;

    test('a role with nothing sees nothing (the button is hidden)', () {
      expect(availableActions(can: can({}), subscriptionStatus: 'ACTIVE', isActive: true), isEmpty);
      expect(availableActions(can: can({Perm.tenantsView, Perm.billingView}), subscriptionStatus: 'ACTIVE', isActive: true), isEmpty);
    });

    test('everything for a full role, in menu order', () {
      final all = {Perm.tenantsManage, Perm.tenantsSuspend, Perm.billingManage, Perm.tenantsSecurity};
      expect(availableActions(can: can(all), subscriptionStatus: 'ACTIVE', isActive: true), [
        TenantAction.extend,
        TenantAction.suspend,
        TenantAction.credit,
        TenantAction.forceLogout,
        TenantAction.lockOut,
      ]);
    });

    test('suspend/reactivate and lock/lift follow the current state', () {
      final all = {Perm.tenantsSuspend, Perm.tenantsSecurity};
      expect(availableActions(can: can(all), subscriptionStatus: 'SUSPENDED', isActive: false), [
        TenantAction.reactivate,
        TenantAction.forceLogout,
        TenantAction.liftLockout,
      ]);
      expect(availableActions(can: can({Perm.tenantsSuspend}), subscriptionStatus: 'CANCELLED', isActive: true), [TenantAction.reactivate]);
      expect(availableActions(can: can({Perm.tenantsSuspend}), subscriptionStatus: 'PAST_DUE', isActive: true), [TenantAction.suspend]);
      expect(availableActions(can: can({Perm.tenantsSuspend}), subscriptionStatus: null, isActive: true), [TenantAction.suspend]);
    });

    test('each action needs its own permission', () {
      expect(availableActions(can: can({Perm.tenantsManage}), subscriptionStatus: 'ACTIVE', isActive: true), [TenantAction.extend]);
      expect(availableActions(can: can({Perm.billingManage}), subscriptionStatus: 'ACTIVE', isActive: true), [TenantAction.credit]);
      expect(availableActions(can: can({Perm.tenantsSecurity}), subscriptionStatus: 'ACTIVE', isActive: true), [TenantAction.forceLogout, TenantAction.lockOut]);
    });
  });

  group('licence parsing', () {
    test('reads the resolved licence the server returns', () {
      final v = licenseFixture(enforcement: 'warn', validUntil: '2027-01-01T00:00:00.000Z', note: 'hi', licenseKey: 'AXON-AAAA-BBBB-CCCC');
      expect(v.plan, 'CORE');
      expect(v.enforcement, 'warn');
      expect(v.features.keys.toList(), ['analytics', 'customReports', 'aiAssistant', 'multiCurrency']);
      expect(v.features['analytics']!.choice, FeatureChoice.planDefault);
      expect(v.features['aiAssistant']!.choice, FeatureChoice.grant);
      expect(v.features['multiCurrency']!.choice, FeatureChoice.revoke);
      expect(v.maxBranches, 3);
      expect(v.maxUsers, 10);
      expect(v.validUntil, DateTime.utc(2027, 1, 1));
      expect(v.licenseKey, 'AXON-AAAA-BBBB-CCCC');
      expect(v.featureStatus('analytics'), 'in plan');
      expect(v.featureStatus('customReports'), 'not in plan');
      expect(v.featureStatus('aiAssistant'), 'granted');
      expect(v.featureStatus('multiCurrency'), 'revoked');
    });

    test('survives an empty or garbled payload', () {
      final v = LicenseView.fromJson({'enforcement': 'sideways'});
      expect(v.enforcement, 'off');
      expect(v.features, isEmpty);
      expect(v.validUntil, isNull);
      expect(v.licenseKey, isNull);
    });

    test('unlimited seat limits are shown as an empty field', () {
      final v = licenseFixture(limits: {'maxBranches': 999999, 'maxUsers': 999999});
      expect(v.editableMaxBranches, isNull);
      expect(LicenseDraft.from(v).maxUsers, isNull);
      expect(buildLicensePatch(v, LicenseDraft.from(v)), isEmpty);
    });

    test('module labels', () {
      expect(featureLabel('aiAssistant'), 'Axon AI assistant');
      expect(featureLabel('multiCurrency'), 'Multi-currency');
      expect(featureLabel('someNewModule'), 'Some new module');
    });
  });

  group('licence patch diffing', () {
    test('an untouched draft sends nothing', () {
      final v = licenseFixture(validUntil: '2027-01-01T00:00:00.000Z', note: 'keep', licenseKey: 'AXON-X');
      final patch = buildLicensePatch(v, LicenseDraft.from(v));
      expect(patch, isEmpty);
      expect(licenseChangeCount(patch), 0);
    });

    test('sends only the enforcement when only that changed', () {
      final v = licenseFixture();
      final d = LicenseDraft.from(v).copyWith(enforcement: 'enforce');
      expect(buildLicensePatch(v, d), {'enforcement': 'enforce'});
    });

    test('overrides: grant=true, revoke=false, plan default=null, unchanged omitted', () {
      final v = licenseFixture();
      final choices = Map<String, FeatureChoice>.from(LicenseDraft.from(v).choices)
        ..['analytics'] = FeatureChoice.revoke // plan default -> revoke
        ..['customReports'] = FeatureChoice.grant // plan default -> grant
        ..['aiAssistant'] = FeatureChoice.planDefault; // granted -> clear override
      // multiCurrency stays revoked: must not appear.
      final patch = buildLicensePatch(v, LicenseDraft.from(v).copyWith(choices: choices));
      expect(patch, {
        'overrides': {'analytics': false, 'customReports': true, 'aiAssistant': null}
      });
      expect((patch['overrides'] as Map).containsKey('multiCurrency'), isFalse);
      expect(licenseChangeCount(patch), 3);
    });

    test('valid-until: set, change, clear, untouched', () {
      final none = licenseFixture();
      final set = LicenseDraft.from(none).copyWith(validUntil: DateTime.utc(2027, 3, 31, 20, 59, 59));
      expect(buildLicensePatch(none, set), {'validUntil': '2027-03-31T20:59:59.000Z'});

      final has = licenseFixture(validUntil: '2027-01-01T00:00:00.000Z');
      expect(buildLicensePatch(has, LicenseDraft.from(has)), isEmpty);
      final cleared = LicenseDraft.from(has).copyWith(clearValidUntil: true);
      final patch = buildLicensePatch(has, cleared);
      expect(patch.containsKey('validUntil'), isTrue);
      expect(patch['validUntil'], isNull); // null clears it on the server
    });

    test('limits: change, clear to null, untouched', () {
      final v = licenseFixture();
      expect(buildLicensePatch(v, LicenseDraft.from(v).copyWith(maxUsers: 25)), {'maxUsers': 25});
      final cleared = buildLicensePatch(v, LicenseDraft.from(v).copyWith(clearMaxBranches: true));
      expect(cleared, {'maxBranches': null});
      expect(cleared.containsKey('maxBranches'), isTrue);
      expect(buildLicensePatch(v, LicenseDraft.from(v).copyWith(maxUsers: 10)), isEmpty);
    });

    test('note: trimmed, blank means clear, whitespace-only change is ignored', () {
      final v = licenseFixture(note: 'Setup fee outstanding');
      expect(buildLicensePatch(v, LicenseDraft.from(v).copyWith(note: '  Setup fee outstanding  ')), isEmpty);
      expect(buildLicensePatch(v, LicenseDraft.from(v).copyWith(note: 'Paid in full')), {'note': 'Paid in full'});
      expect(buildLicensePatch(v, LicenseDraft.from(v).copyWith(note: '   ')), {'note': null});
      final bare = licenseFixture();
      expect(buildLicensePatch(bare, LicenseDraft.from(bare).copyWith(note: '')), isEmpty);
    });

    test('reissue key is only sent when switched on', () {
      final v = licenseFixture(licenseKey: 'AXON-X');
      expect(buildLicensePatch(v, LicenseDraft.from(v)), isEmpty);
      expect(buildLicensePatch(v, LicenseDraft.from(v).copyWith(reissueKey: true)), {'reissueKey': true});
    });

    test('several edits at once are all (and only) included', () {
      final v = licenseFixture(licenseKey: 'AXON-X');
      final d = LicenseDraft.from(v).copyWith(
        enforcement: 'warn',
        maxBranches: 5,
        note: 'Upgraded',
        choices: {...LicenseDraft.from(v).choices, 'customReports': FeatureChoice.grant},
      );
      final patch = buildLicensePatch(v, d);
      expect(patch.keys.toSet(), {'enforcement', 'maxBranches', 'note', 'overrides'});
      expect(licenseChangeCount(patch), 4);
    });

    test('limit text parsing', () {
      expect(parseLimit('').value, isNull);
      expect(parseLimit('').valid, isTrue);
      expect(parseLimit(' 12 ').value, 12);
      expect(parseLimit('0').valid, isFalse);
      expect(parseLimit('-3').valid, isFalse);
      expect(parseLimit('2.5').valid, isFalse);
      expect(parseLimit('abc').valid, isFalse);
    });

    test('enforcement wording', () {
      expect(enforcementLabel('off'), 'Off');
      expect(enforcementLabel('warn'), 'Warn');
      expect(enforcementLabel('enforce'), 'Enforce');
      for (final m in kEnforcementModes) {
        expect(enforcementExplain(m), isNotEmpty);
      }
    });
  });
}
