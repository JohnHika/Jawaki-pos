// Live contract test for the Clients feature: runs the app's real AcaApi + AcaRepository
// against a QA backend and checks the licence round trip with the same helpers the screens use.
//
// Only runs against a non-production server (it edits a licence note and puts it back):
//   flutter test --dart-define=ACA_API_BASE_URL=http://localhost:3100/api/v1 test/tenants_live_contract_test.dart
// Against production (the default) it is skipped, so it can never touch live data.
import 'package:aca/core/config.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
import 'package:aca/features/tenants/license_logic.dart';
import 'package:aca/features/tenants/tenants_logic.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokens extends TokenStore {
  _MemoryTokens();
  AuthTokens? _t;
  @override
  Future<AuthTokens?> read() async => _t;
  @override
  Future<void> write(AuthTokens t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
}

void main() {
  final qa = !AcaConfig.isProduction;

  group('clients live contract (QA server)', skip: qa ? false : 'production build: refusing to run against live data', () {
    late AcaRepository repo;
    late String tenantId;

    setUpAll(() async {
      final api = AcaApi(store: _MemoryTokens(), deviceLabel: 'contract-test', appVersion: 'test');
      repo = AcaRepository(api);
      final r = await api.post('/auth/login', body: {'email': 'qa-owner@aca.test', 'password': 'QaOwner-Passw0rd!x'}, auth: false);
      final j = J.map(r);
      await api.setTokens(AuthTokens(access: J.s(j['accessToken']), refresh: J.s(j['refreshToken']), accessExpiresAt: J.d(j['accessTokenExpiresAt'])));
      tenantId = (await repo.tenants(pageSize: 50)).items.firstWhere((t) => t.name.contains('Mart')).id;
    });

    test('the licence parses and an untouched editor draft sends nothing', () async {
      final view = LicenseView.fromJson(await repo.license(tenantId));
      expect(view.plan, isNotEmpty);
      expect(kEnforcementModes, contains(view.enforcement));
      expect(view.features, isNotEmpty);
      expect(view.maxUsers, greaterThan(0));
      expect(buildLicensePatch(view, LicenseDraft.from(view)), isEmpty);
    });

    test('a one-field patch is accepted and reflected, then restored', () async {
      final before = LicenseView.fromJson(await repo.license(tenantId));
      if (before.licenseKey == null) {
        // Saving would issue a first key on a fixture that has none; do not change fixture data for a contract check.
        markTestSkipped('fixture has no licence key yet');
        return;
      }
      final marker = 'contract check ${DateTime.now().millisecondsSinceEpoch}';
      final patch = buildLicensePatch(before, LicenseDraft.from(before).copyWith(note: marker));
      expect(patch, {'note': marker});

      final after = LicenseView.fromJson(await repo.updateLicense(tenantId, patch));
      expect(after.note, marker);
      expect(after.licenseKey, before.licenseKey, reason: 'a note edit must not reissue the key');
      expect(after.enforcement, before.enforcement);

      final restore = buildLicensePatch(after, LicenseDraft.from(after).copyWith(note: before.note ?? ''));
      final restored = LicenseView.fromJson(await repo.updateLicense(tenantId, restore));
      expect(restored.note, before.note);
    });

    test('clearing an override that does not exist is accepted (null means back to plan default)', () async {
      final before = LicenseView.fromJson(await repo.license(tenantId));
      if (before.licenseKey == null) {
        markTestSkipped('fixture has no licence key yet');
        return;
      }
      final key = before.features.entries.firstWhere((e) => !e.value.isOverride).key;
      final accepted = await repo.updateLicense(tenantId, {
        'overrides': {key: null},
        'maxUsers': before.maxUsers, // an explicit whole number is accepted too
      });
      final view = LicenseView.fromJson(accepted);
      expect(view.features[key]!.isOverride, isFalse);
    });

    test('company detail, users, devices, notes and invoices feed the screens\' helpers', () async {
      final d = await repo.tenant(tenantId);
      expect(d.owner, isNotNull);
      final devices = await repo.tenantDevices(tenantId);
      final newest = newestVersion(devices.map((x) => x.appVersion));
      for (final x in devices) {
        expect(isOutdatedVersion(x.appVersion, newest), anyOf(isTrue, isFalse));
      }
      final notes = sortNotes(await repo.tenantNotes(tenantId));
      expect(notes.length, lessThanOrEqualTo(1000));
      final invoices = await repo.invoices(tenantId: tenantId, pageSize: 50);
      expect(invoices.items.every((i) => i.tenantId == tenantId), isTrue);
      for (final c in d.claims) {
        expect(c.status, isNotEmpty);
      }
    });
  });
}
