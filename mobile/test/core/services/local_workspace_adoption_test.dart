import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory secure storage so the stretched PIN verifier can round-trip in
/// tests without touching the host keystore.
class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      values[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(values);

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    values.clear();
  }
}

/// API client whose only job is to prove no network call happens during
/// local adoption and local sign-in.
class _NoNetworkApiClient extends ApiClient {
  int loginCalls = 0;

  _NoNetworkApiClient() : super(Dio());

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? tenantSlug,
    String? deviceId,
  }) async {
    loginCalls += 1;
    throw UnimplementedError('local flows must not hit the network');
  }

  @override
  Future<Map<String, dynamic>> loginWithPin({
    required String pin,
    String? deviceId,
    String? branchId,
  }) async {
    loginCalls += 1;
    throw UnimplementedError('local flows must not hit the network');
  }

  @override
  Future<void> logout({String? refreshToken, bool allDevices = false}) async {}

  @override
  Future<Map<String, dynamic>> registerDevice({
    required String branchId,
    required String deviceUuid,
    required String name,
    String? appVersion,
  }) async => {};
}

class _StubLocalAuth extends LocalAuthentication {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late AppDatabase database;
  late _NoNetworkApiClient api;
  late AuthService auth;

  // A cached cloud session shaped like the pre-local-first 1.0.172 login
  // response: no authMode, no local workspace on the device yet.
  Map<String, dynamic> cloudUser() => {
        'id': 'user-1',
        'email': 'owner@shop.co',
        'firstName': 'Test',
        'lastName': 'Owner',
        'name': 'Test Owner',
        'role': 'ADMIN',
        'permissions': ['*'],
        'tenantId': 'tenant-1',
        'tenantSlug': 'shop',
        'branchId': 'branch-1',
        'branchName': 'Main branch',
        'branches': [
          {
            'id': 'branch-1',
            'name': 'Main branch',
            'isPrimary': true,
            'isActive': true,
          }
        ],
        'tenant': {
          'id': 'tenant-1',
          'name': 'My Shop',
          'slug': 'shop',
          'activationStatus': 'ACTIVE',
          'settings': <String, dynamic>{},
          'isActive': true,
        },
      };

  setUp(() async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialize();
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    api = _NoNetworkApiClient();
    auth = AuthService(
      storage: storage,
      apiClient: api,
      database: database,
      localAuth: _StubLocalAuth(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCloudSession() async {
    const token = 'stale-cloud-token';
    await storage.saveAccessToken(token);
    await storage.saveRefreshToken('refresh-1');
    await storage.saveUser(cloudUser());
    await storage.saveTenantId('tenant-1');
    await storage.saveTenantSlug('shop');
    await storage.saveBranchId('branch-1');
    await storage.saveRememberedLogin(
      enabled: true,
      email: 'owner@shop.co',
      tenantSlug: 'shop',
    );
    auth.setSessionForTesting(cloudUser(), token);
  }

  group('stale cloud session + no saved workspace (fresh 1.0.173 upgrade)',
      () {
    test('requires adoption', () async {
      await seedCloudSession();
      expect(auth.isLocalWorkspace, isFalse);
      expect(auth.requiresLocalWorkspaceAdoption, isTrue);
    });

    test('adopt writes a local workspace and keeps the shop identity',
        () async {
      await seedCloudSession();

      await auth.adoptCurrentWorkspaceLocally(
        ownerPin: '123456',
        acceptedLocalDataNotice: true,
      );

      expect(auth.isLocalWorkspace, isTrue);
      expect(auth.requiresLocalWorkspaceAdoption, isFalse);
      expect(storage.hasLocalWorkspace(), isTrue);

      final workspace = storage.getLocalWorkspace()!;
      expect(workspace['tenant']['id'], 'tenant-1');
      expect(workspace['branch']['id'], 'branch-1');
      expect(workspace['user']['authMode'], 'local');
      expect(workspace['adoptedFromOnlineWorkspace'], isTrue);

      // Server credentials are gone after adoption.
      expect(await storage.getAccessToken(), isNull);
      expect(api.loginCalls, 0);

      // The owner PIN unlocks the workspace offline.
      expect(await storage.verifyLocalPin('123456'), isTrue);
      expect(await storage.verifyLocalPin('654321'), isFalse);
    });

    test('a failed adoption keeps the cloud session and stays retryable',
        () async {
      await seedCloudSession();

      await expectLater(
        auth.adoptCurrentWorkspaceLocally(
          ownerPin: '12',
          acceptedLocalDataNotice: true,
        ),
        throwsArgumentError,
      );
      await expectLater(
        auth.adoptCurrentWorkspaceLocally(
          ownerPin: '123456',
          acceptedLocalDataNotice: false,
        ),
        throwsStateError,
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.isLocalWorkspace, isFalse);
      expect(storage.hasLocalWorkspace(), isFalse);
    });
  });

  group('adoption identity recovery', () {
    test('fills a missing branch from storage when the user JSON is stale',
        () async {
      await seedCloudSession();
      // Simulate the cache missing the branches list but keeping the
      // branch id preference.
      final user = cloudUser()..remove('branches');
      await storage.saveUser(user);
      auth.setSessionForTesting(user, 'stale-cloud-token');

      await auth.adoptCurrentWorkspaceLocally(
        ownerPin: '123456',
        acceptedLocalDataNotice: true,
      );

      final workspace = storage.getLocalWorkspace()!;
      expect(workspace['branch']['id'], 'branch-1');
      expect(workspace['branch']['name'], 'Main branch');
    });

    test('continues over a partial workspace left by a failed adoption',
        () async {
      await seedCloudSession();
      // A previous attempt crashed after writing an empty-ish workspace
      // record for the same tenant.
      await storage.saveLocalWorkspace({
        'schemaVersion': 1,
        'createdAt': '2026-10-30T00:00:00Z',
        'tenant': {'id': 'tenant-1', 'name': 'My Shop'},
        'branch': {'id': 'branch-1'},
        'user': <String, dynamic>{},
      });

      await auth.adoptCurrentWorkspaceLocally(
        ownerPin: '123456',
        acceptedLocalDataNotice: true,
      );

      final workspace = storage.getLocalWorkspace()!;
      expect(workspace['user']['authMode'], 'local');
      expect(workspace['user']['id'], 'user-1');
      expect(auth.isLocalWorkspace, isTrue);
    });

    test('refuses to adopt over a different shop workspace', () async {
      await seedCloudSession();
      await storage.saveLocalWorkspace({
        'schemaVersion': 1,
        'tenant': {'id': 'other-tenant'},
        'branch': <String, dynamic>{},
        'user': <String, dynamic>{},
      });

      await expectLater(
        auth.adoptCurrentWorkspaceLocally(
          ownerPin: '123456',
          acceptedLocalDataNotice: true,
        ),
        throwsStateError,
      );
    });
  });

  group('stale cloud session + saved workspace (the loop case)', () {
    setUp(() async {
      await seedCloudSession();
      await storage.saveLocalWorkspace({
        'schemaVersion': 1,
        'createdAt': '2026-10-30T00:00:00Z',
        'tenant': {
          'id': 'tenant-1',
          'name': 'My Shop',
          'slug': 'shop',
          'activationStatus': 'ACTIVE',
          'isActive': true,
          'settings': <String, dynamic>{},
        },
        'branch': {
          'id': 'branch-1',
          'name': 'Main branch',
          'code': 'MAIN',
          'isActive': true,
          'isPrimary': true,
        },
        'user': {
          ...cloudUser(),
          'authMode': 'local',
          'hasPinSet': true,
        },
        'localDataNotice': {
          'version': 'local-data-v1',
          'acceptedAt': '2026-10-30T00:00:00Z',
        },
      });
      await storage.setLocalPin('123456');
    });

    test('does NOT demand adoption — the workspace can be reopened', () async {
      expect(auth.requiresLocalWorkspaceAdoption, isFalse,
          reason: 'a saved workspace must never trap the user in migration');
    });

    test('owner PIN signs into the local workspace without any network call',
        () async {
      await auth.loginWithPin('123456');

      expect(auth.isLocalWorkspace, isTrue);
      expect(auth.currentUser?['authMode'], 'local');
      expect(await storage.getAccessToken(), isNull);
      expect(api.loginCalls, 0);
    });

    test('wrong PIN is rejected', () async {
      await expectLater(auth.loginWithPin('999999'), throwsStateError);
      expect(auth.currentUser?['authMode'], isNot('local'),
          reason: 'a wrong PIN must not activate the workspace');
    });

    test('unlockWithPin restores the local owner profile', () async {
      final ok = await auth.unlockWithPin('123456');
      expect(ok, isTrue);
      expect(auth.isLocalWorkspace, isTrue);
    });
  });

  group('local workspace sign-out then sign back in', () {
    setUp(() async {
      await seedCloudSession();
      await auth.adoptCurrentWorkspaceLocally(
        ownerPin: '123456',
        acceptedLocalDataNotice: true,
      );
    });

    test('logout keeps the workspace and PIN for the next sign-in', () async {
      await auth.logout();

      expect(storage.hasLocalWorkspace(), isTrue);
      expect(await storage.hasLocalPinSet(), isTrue);
      expect(auth.isAuthenticated, isFalse);

      await auth.loginWithPin('123456');
      expect(auth.isLocalWorkspace, isTrue);
      expect(auth.currentUser?['name'], 'Test Owner');
    });
  });
}
