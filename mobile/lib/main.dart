import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/background_sync_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/local_server_service.dart';
import 'core/services/storage_service.dart';

/// Global error handler for uncaught Flutter errors
void _setupFlutterErrorHandling() {
  // Handle Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║ FLUTTER ERROR (Uncaught)                                  ║');
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('Error: ${details.exception}');
    debugPrint('Library: ${details.library}');
    debugPrint('Context: ${details.context}');
    debugPrint('Stack trace:');
    debugPrint('${details.stack}');
    debugPrint('═══════════════════════════════════════════════════════════');

    // In production, you would send this to your crash reporting service
    // e.g., Firebase Crashlytics, Sentry, etc.
  };

  // Handle platform-level errors (isolates, etc.)
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║ PLATFORM ERROR (Isolate/Platform)                         ║');
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('Error: $error');
    debugPrint('Stack trace:');
    debugPrint('$stack');
    debugPrint('═══════════════════════════════════════════════════════════');

    // In production, send to crash reporting service
    // FirebaseCrashlytics.instance.recordError(error, stack);

    // Return true to indicate we handled it (prevents app crash)
    return true;
  };
}

void main() async {
  // Setup error handling BEFORE anything else
  _setupFlutterErrorHandling();

  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Lock orientation to portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    debugPrint('[main] Screen orientation locked to portrait');

    // Initialize dependency injection (CRITICAL - must succeed)
    debugPrint('[main] Initializing dependency injection...');
    await configureDependencies();
    debugPrint('[main] Dependency injection initialized successfully');

    // Initialize connectivity monitoring (CRITICAL for offline-first app)
    debugPrint('[main] Initializing connectivity service...');
    await getIt<ConnectivityService>().initialize();
    debugPrint('[main] Connectivity service initialized');

    getIt<LocalServerService>().enableAutoStart(
      connectivity: getIt<ConnectivityService>(),
      storage: getIt<StorageService>(),
    );
    debugPrint('[main] Local server auto-start armed');

    // Initialize background sync worker (OPTIONAL - can fail without crashing)
    debugPrint('[main] Initializing background sync (non-blocking)...');
    try {
      await BackgroundSyncService.initialize();
      debugPrint('[main] Background sync initialized successfully');
    } catch (e, stackTrace) {
      // Background sync is OPTIONAL - app can work without it
      debugPrint('[main] Background sync init failed (non-critical): $e');
      debugPrint('[main] Stack trace: $stackTrace');
    }

    debugPrint('[main] All initializations complete, launching app...');

    runApp(
      const ProviderScope(
        child: POSApp(),
      ),
    );
  } catch (e, stackTrace) {
    // CRITICAL initialization failed - log everything and try to run app anyway
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║ CRITICAL INITIALIZATION ERROR                             ║');
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('Error: $e');
    debugPrint('Stack trace:');
    debugPrint('$stackTrace');
    debugPrint('═══════════════════════════════════════════════════════════');

    // Try to run the app anyway - some features may not work
    // but the app should still be usable
    runApp(
      const ProviderScope(
        child: POSApp(),
      ),
    );
  }
}

class POSApp extends ConsumerWidget {
  const POSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Levisa Adventures POS',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      checkerboardRasterCacheImages: false,
      checkerboardOffscreenLayers: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
    );
  }
}
