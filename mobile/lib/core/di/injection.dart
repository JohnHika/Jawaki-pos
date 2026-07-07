import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/auth_interceptor.dart';
import '../services/connectivity_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../services/haptic_service.dart';
import '../services/local_server_service.dart';
import '../services/update_check_service.dart';
import '../../features/ai-billing/presentation/services/ai_billing_service.dart';

final getIt = GetIt.instance;
const _defaultApiUrl = 'https://arche-axon-pos-api.onrender.com/api/v1';

/// Configure all dependencies for the app
/// This must be called after WidgetsFlutterBinding.ensureInitialized()
Future<void> configureDependencies() async {
  debugPrint('[DI] Starting dependency injection configuration...');

  try {
    // ============================================
    // STEP 1: Core Services (no dependencies)
    // ============================================
    debugPrint('[DI] Registering StorageService...');
    final storageService = StorageService();
    getIt.registerSingleton<StorageService>(storageService);

    // Initialize storage FIRST (required by all other services)
    debugPrint('[DI] Initializing StorageService...');
    await storageService.initialize();
    await storageService.ensureDeviceId();
    debugPrint('[DI] StorageService initialized');

    debugPrint('[DI] Registering ConnectivityService...');
    final connectivityService = ConnectivityService();
    getIt.registerSingleton<ConnectivityService>(connectivityService);

    // Register Haptic Service (singleton, no initialization needed)
    debugPrint('[DI] Registering HapticService...');
    getIt.registerSingleton<HapticService>(HapticService());

    // ============================================
    // STEP 2: Database (depends on StorageService)
    // ============================================
    debugPrint('[DI] Registering AppDatabase...');
    final database = AppDatabase(getIt<StorageService>());
    getIt.registerSingleton<AppDatabase>(database);
    debugPrint('[DI] AppDatabase registered');

    // ============================================
    // STEP 3: Network Layer
    // ============================================
    debugPrint('[DI] Creating Dio HTTP client...');
    final dio = _createDio();
    getIt.registerSingleton<Dio>(dio);

    debugPrint('[DI] Registering ApiClient...');
    final apiClient = ApiClient(dio);
    getIt.registerSingleton<ApiClient>(apiClient);
    debugPrint('[DI] ApiClient registered');

    // Apply saved server URL (overrides compile-time default)
    final savedUrl = storageService.getServerBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      final isLegacyLocalUrl = savedUrl.contains('192.168.100.47') ||
          savedUrl.contains('10.30.168.100');
      final effectiveUrl = isLegacyLocalUrl ? _defaultApiUrl : savedUrl;
      if (isLegacyLocalUrl) {
        await storageService.setServerBaseUrl(effectiveUrl);
      }
      apiClient.setBaseUrl(effectiveUrl);
      debugPrint('[DI] ApiClient base URL from storage: $effectiveUrl');
    } else {
      debugPrint('[DI] Using default ApiClient base URL');
    }

    // ============================================
    // STEP 4: Auth Service (depends on StorageService, ApiClient)
    // ============================================
    debugPrint('[DI] Registering AuthService...');
    final authService = AuthService(
      storage: getIt<StorageService>(),
      apiClient: getIt<ApiClient>(),
      database: getIt<AppDatabase>(),
    );
    getIt.registerSingleton<AuthService>(authService);

    // Initialize auth service (explicit initialization pattern)
    debugPrint('[DI] Initializing AuthService...');
    await authService.initialize();
    debugPrint('[DI] AuthService initialized');

    // ============================================
    // STEP 5: Add Auth Interceptor (after AuthService)
    // ============================================
    debugPrint('[DI] Adding AuthInterceptor to Dio...');
    dio.interceptors.add(AuthInterceptor(getIt<AuthService>()));
    debugPrint('[DI] AuthInterceptor added');

    // ============================================
    // STEP 6: Sync Service (depends on Database, ApiClient, Connectivity)
    // ============================================
    debugPrint('[DI] Registering SyncService...');
    final syncService = SyncService(
      database: getIt<AppDatabase>(),
      apiClient: getIt<ApiClient>(),
      connectivity: getIt<ConnectivityService>(),
    );
    getIt.registerSingleton<SyncService>(syncService);
    debugPrint('[DI] SyncService registered');

    // ============================================
    // STEP 7: Local Server Service (phone server mode)
    // ============================================
    debugPrint('[DI] Registering LocalServerService...');
    final localServerService = LocalServerService();
    getIt.registerSingleton<LocalServerService>(localServerService);
    debugPrint('[DI] LocalServerService registered');

    // ============================================
    // STEP 8: Update Check Service (backend manifest)
    // ============================================
    debugPrint('[DI] Registering UpdateCheckService...');
    getIt.registerSingleton<UpdateCheckService>(
      UpdateCheckService(apiClient: getIt<ApiClient>()),
    );
    debugPrint('[DI] UpdateCheckService registered');

    // ============================================
    // STEP 9: AI Billing Service
    // ============================================
    debugPrint('[DI] Registering AiBillingService...');
    getIt.registerSingleton<AiBillingService>(AiBillingService());
    debugPrint('[DI] AiBillingService registered');

    debugPrint('[DI] Dependency injection configuration complete!');
  } catch (e, stackTrace) {
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║ DI CONFIGURATION ERROR                                    ║');
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('Error: $e');
    debugPrint('Stack trace:');
    debugPrint('$stackTrace');
    debugPrint('═══════════════════════════════════════════════════════════');
    rethrow;
  }
}

Dio _createDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_URL',
        defaultValue: _defaultApiUrl,
      ),
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
    logPrint: (obj) => debugPrint('[Dio] $obj'),
  ));

  return dio;
}
