import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      values[key] = value;

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
  }) async =>
      values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      values.clear();
}

/// Plays the shop server: it keeps its own settings, answers the refresh that
/// runs every time the app is opened again, and can be switched offline.
class _ShopServerApi extends ApiClient {
  _ShopServerApi() : super(Dio());

  Map<String, dynamic> serverSettings = {};
  bool offline = false;
  bool locked = false;
  int uploads = 0;

  @override
  Future<Map<String, dynamic>> getCurrentTenant() async {
    if (offline) throw DioException(requestOptions: RequestOptions());
    return {
      'id': 'tenant-1',
      'name': 'My Shop',
      'slug': 'shop',
      'settings': Map<String, dynamic>.from(serverSettings),
      'isActive': true,
    };
  }

  @override
  Future<Map<String, dynamic>> updateCurrentTenant({
    String? name,
    String? logo,
    String? logoPublicId,
    double? taxRatePercent,
    bool? showTaxOnReceipt,
    Map<String, dynamic>? settings,
  }) async {
    if (offline) throw DioException(requestOptions: RequestOptions());
    if (locked) {
      throw DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 403),
      );
    }
    uploads += 1;
    serverSettings = {...serverSettings, ...?settings};
    return {'id': 'tenant-1', 'settings': Map<String, dynamic>.from(serverSettings)};
  }

  @override
  Future<Map<String, dynamic>> registerDevice({
    required String branchId,
    required String deviceUuid,
    required String name,
    String? appVersion,
  }) async =>
      {};
}

class _StubLocalAuth extends LocalAuthentication {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late AppDatabase database;
  late _ShopServerApi api;
  late AuthService auth;

  const layout = {
    'version': 12,
    'profileId': 'kamukunji_counter',
    'priorityPaths': ['/pos'],
  };

  Map<String, dynamic> owner() => {
        'id': 'user-1',
        'email': 'owner@shop.co',
        'name': 'Test Owner',
        'role': 'ADMIN',
        'permissions': ['*'],
        'tenantId': 'tenant-1',
        'tenantSlug': 'shop',
        'branchId': 'branch-1',
        'tenant': {
          'id': 'tenant-1',
          'name': 'My Shop',
          'slug': 'shop',
          'settings': <String, dynamic>{'currency': 'KES'},
          'isActive': true,
        },
      };

  Map<String, dynamic>? savedLayout() {
    final tenant = auth.currentUser?['tenant'] as Map?;
    final settings = tenant?['settings'] as Map?;
    final saved = settings?['businessLayout'];
    return saved is Map ? Map<String, dynamic>.from(saved) : null;
  }

  setUp(() async {
    FlutterSecureStoragePlatform.instance = _MemorySecureStorage();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialize();
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    api = _ShopServerApi();
    auth = AuthService(
      storage: storage,
      apiClient: api,
      database: database,
      localAuth: _StubLocalAuth(),
    );
    await storage.saveUser(owner());
    await storage.saveTenantId('tenant-1');
    await storage.saveTenantSlug('shop');
    auth.setSessionForTesting(owner(), 'token');
  });

  tearDown(() async => database.close());

  test('a saved layout is still there after the app is opened again', () async {
    final synced = await auth.saveBusinessLayout(Map.of(layout));
    expect(synced, isTrue);
    expect(api.serverSettings['businessLayout'], layout);

    await auth.refreshTenantSettings();

    expect(savedLayout(), layout);
  });

  test('a layout the shop never received survives the resume refresh and is sent up',
      () async {
    // Saved by an older build: on the phone only, nothing on the server.
    await auth.updateTenantSession({
      'settings': {'currency': 'KES', 'businessLayout': layout},
    });
    expect(api.serverSettings, isEmpty);

    await auth.refreshTenantSettings();
    await Future<void>.delayed(Duration.zero);

    expect(savedLayout(), layout);
    expect(api.serverSettings['businessLayout'], layout);
  });

  test('a layout saved offline is kept, then uploaded when the phone is back',
      () async {
    api.offline = true;
    final synced = await auth.saveBusinessLayout(Map.of(layout));
    expect(synced, isFalse);
    expect(savedLayout(), layout);

    api.offline = false;
    await auth.refreshTenantSettings();
    await Future<void>.delayed(Duration.zero);

    expect(savedLayout(), layout);
    expect(api.serverSettings['businessLayout'], layout);
  });

  test('a layout the shop refuses (business type locked) is dropped, not retried forever',
      () async {
    final shopLayout = {...layout, 'profileId': 'bookshop'};
    api.serverSettings = {'currency': 'KES', 'businessLayout': shopLayout};
    api.locked = true;

    final synced = await auth.saveBusinessLayout(Map.of(layout));

    expect(synced, isFalse);
    expect(savedLayout(), shopLayout);
    final tenant = auth.currentUser!['tenant'] as Map;
    expect((tenant['settings'] as Map).containsKey('businessLayoutPendingSync'), isFalse);
  });

  test('settings that replace the whole block cannot drop the layout', () async {
    await auth.saveBusinessLayout(Map.of(layout));

    await auth.updateTenantSession({
      'settings': {'currency': 'USD'},
    });

    expect(savedLayout(), layout);
  });

  test('the shop copy wins when the shop already has a layout and nothing is waiting',
      () async {
    // Already uploaded earlier, so nothing is waiting on this phone.
    final uploaded = owner();
    (uploaded['tenant'] as Map)['settings'] = {
      'currency': 'KES',
      'businessLayout': layout,
    };
    auth.setSessionForTesting(uploaded, 'token');
    api.serverSettings = {
      'currency': 'KES',
      'businessLayout': {...layout, 'profileId': 'bookshop'},
    };

    await auth.refreshTenantSettings();

    expect(savedLayout()?['profileId'], 'bookshop');
  });
}
