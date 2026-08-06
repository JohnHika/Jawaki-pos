import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:axon_pos/features/team/data/services/invitation_cache_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;

  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InvitationCacheService service;
  late String tempDir;

  setUp(() async {
    tempDir = path.join(
      Directory.systemTemp.path,
      'axon_pos_invitation_cache_test_${DateTime.now().millisecondsSinceEpoch}',
    );
    await Directory(tempDir).create(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await Hive.initFlutter(tempDir);
    service = InvitationCacheService();
    await service.initialize();
  });

  tearDown(() async {
    await service.dispose();
    try {
      await Directory(tempDir).delete(recursive: true);
    } catch (_) {}
  });

  test('returns null when cache is empty', () {
    expect(service.getInvitations(), isNull);
  });

  test('round-trips a list of invitations', () async {
    final invitations = [
      {
        'id': 'inv-1',
        'email': 'a@example.com',
        'firstName': 'Alice',
        'lastName': '',
        'status': 'PENDING',
        'role': {'id': 'r1', 'name': 'Cashier'},
        'branch': {'id': 'b1', 'name': 'Main'},
        'createdBy': {'id': 'u1', 'firstName': 'Admin', 'lastName': ''},
        'createdAt': '2026-08-06T10:00:00.000Z',
        'expiresAt': '2026-08-06T11:00:00.000Z',
      },
      {
        'id': 'inv-2',
        'email': 'b@example.com',
        'firstName': 'Bob',
        'lastName': 'Smith',
        'status': 'ACCEPTED',
        'role': {'id': 'r2', 'name': 'Manager'},
        'branch': {'id': 'b2', 'name': 'Warehouse'},
        'createdBy': {'id': 'u1', 'firstName': 'Admin', 'lastName': ''},
        'createdAt': '2026-08-05T10:00:00.000Z',
        'acceptedAt': '2026-08-05T10:30:00.000Z',
        'expiresAt': '2026-08-05T11:00:00.000Z',
      },
    ];

    await service.saveInvitations(invitations);
    final cached = service.getInvitations();

    expect(cached, isNotNull);
    expect(cached!.length, 2);
    expect(cached.first['id'], 'inv-1');
    expect(cached.last['status'], 'ACCEPTED');
    expect((cached.first['role'] as Map)['name'], 'Cashier');
  });

  test('invalidate clears the cache', () async {
    await service.saveInvitations([
      {'id': 'inv-1', 'email': 'a@example.com'},
    ]);
    expect(service.getInvitations(), isNotNull);

    await service.invalidate();
    expect(service.getInvitations(), isNull);
  });
}
