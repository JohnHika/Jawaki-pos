import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/auth_interceptor.dart';
import '../services/connectivity_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Core Services
  getIt.registerSingleton<StorageService>(StorageService());
  await getIt<StorageService>().initialize();
  
  getIt.registerSingleton<ConnectivityService>(ConnectivityService());
  
  // Database
  final database = AppDatabase();
  getIt.registerSingleton<AppDatabase>(database);
  
  // Seed demo products on first launch
  await database.seedDemoData();
  
  // Network
  getIt.registerSingleton<Dio>(_createDio());
  getIt.registerSingleton<ApiClient>(ApiClient(getIt<Dio>()));
  
  // Auth
  getIt.registerSingleton<AuthService>(AuthService(
    storage: getIt<StorageService>(),
    apiClient: getIt<ApiClient>(),
  ));
  
  // Add auth interceptor after auth service is registered
  getIt<Dio>().interceptors.add(AuthInterceptor(getIt<AuthService>()));
  
  // Sync Service
  getIt.registerSingleton<SyncService>(SyncService(
    database: getIt<AppDatabase>(),
    apiClient: getIt<ApiClient>(),
    connectivity: getIt<ConnectivityService>(),
  ));
}

Dio _createDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://10.30.168.100:3000/api/v1',
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
  ));
  
  return dio;
}
