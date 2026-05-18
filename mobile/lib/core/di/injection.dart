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

final getIt = GetIt.instance;

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

    // ============================================
    // STEP 4: Auth Service (depends on StorageService, ApiClient)
    // ============================================
    debugPrint('[DI] Registering AuthService...');
    final authService = AuthService(
      storage: getIt<StorageService>(),
      apiClient: getIt<ApiClient>(),
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
        defaultValue: 'http://192.168.100.47:3000/api/v1',
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
