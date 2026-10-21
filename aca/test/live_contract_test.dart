// Live contract test: runs the app's real AcaApi + AcaRepository + models against a
// QA backend and checks that every endpoint parses.
//
// It only runs when the build is pointed at a non-production server:
//   flutter test --dart-define=ACA_API_BASE_URL=http://localhost:3100/api/v1 test/live_contract_test.dart
// Against production (the default) it is skipped, so it can never touch live data.
import 'package:aca/core/config.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
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

  group('live contract (QA server)', skip: qa ? false : 'production build: refusing to run against live data', () {
    late AcaApi api;
    late AcaRepository repo;

    setUpAll(() async {
      api = AcaApi(store: _MemoryTokens(), deviceLabel: 'contract-test', appVersion: 'test');
      repo = AcaRepository(api);
      final j = await api.postMap_('/auth/login', {'email': 'qa-owner@aca.test', 'password': 'QaOwner-Passw0rd!x'});
      await api.setTokens(AuthTokens(
        access: J.s(j['accessToken']),
        refresh: J.s(j['refreshToken']),
        accessExpiresAt: J.d(j['accessTokenExpiresAt']),
      ));
    });

    test('overview parses with real numbers', () async {
      final o = await repo.overview();
      expect(o.tenantTotal, greaterThan(0));
      expect(o.monthly.length, 6);
      expect(o.byStatus.keys, contains('ACTIVE'));
      expect(o.generatedAt, isNotNull);
    });

    test('tenants list, detail, users, devices, notes, license', () async {
      final page = await repo.tenants(pageSize: 50);
      expect(page.items, isNotEmpty);
      final t = page.items.firstWhere((x) => x.name.contains('Mart'));
      final d = await repo.tenant(t.id);
      expect(d.name, t.name);
      expect(d.userCount, greaterThan(0));
      expect(d.owner, isNotNull);
      expect((await repo.tenantUsers(t.id)), isNotEmpty);
      final devices = await repo.tenantDevices(t.id);
      expect(devices.first.appVersion, isNotNull);
      await repo.tenantNotes(t.id);
      final lic = await repo.license(t.id);
      expect(lic['enforcement'], isNotNull);
      expect(lic['features'], isA<Map>());
    });

    test('billing: invoices (decimal strings parse) and claims', () async {
      final inv = await repo.invoices(pageSize: 50);
      expect(inv.items, isNotEmpty);
      expect(inv.items.first.amount, isA<num>());
      expect(inv.items.first.tenantName, isNotNull);
      final claims = await repo.pendingClaims();
      expect(claims, isNotEmpty);
      expect(claims.first.mpesaCode, isNotEmpty);
    });

    test('team, roles, security overview, audit, sessions', () async {
      final team = await repo.team();
      expect(team.any((s) => s.role == 'OWNER'), isTrue);
      final roles = await repo.roles();
      expect(roles.length, 6);
      expect(roles.firstWhere((r) => r.role == 'OWNER').assignable, isTrue);
      final detail = await repo.staff(team.first.id);
      expect(detail.email, team.first.email);
      expect((await repo.staffSessions(team.first.id)), isNotEmpty);

      final sec = await repo.securityOverview();
      expect(sec.activeStaff, greaterThan(0));

      final audit = await repo.audit(pageSize: 10);
      expect(audit.items, isNotEmpty);
      expect(audit.items.first.action, isNotEmpty);

      final mine = await repo.mySessions();
      expect(mine.any((s) => s.current), isTrue);
    });

    test('a forbidden call surfaces as ApiException, not a crash', () async {
      final fresh = AcaApi(store: _MemoryTokens(), deviceLabel: 'contract-test', appVersion: 'test');
      expect(() => AcaRepository(fresh).overview(), throwsA(isA<ApiException>()));
    });
  });
}

extension on AcaApi {
  Future<Map<String, dynamic>> postMap_(String path, Map<String, dynamic> body) async {
    final r = await post(path, body: body, auth: false);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}
