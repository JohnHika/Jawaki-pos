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
import 'core/services/update_check_service.dart';
import 'core/widgets/forced_update_gate.dart';

/// Global error handler for uncaught Flutter errors
void _setupFlutterErrorHandling() {
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
  };

  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║ PLATFORM ERROR (Isolate/Platform)                         ║');
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('Error: $error');
    debugPrint('Stack trace:');
    debugPrint('$stack');
    debugPrint('═══════════════════════════════════════════════════════════');
    return true;
  };
}

void main() async {
  _setupFlutterErrorHandling();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    debugPrint('[main] Screen orientation locked to portrait');

    debugPrint('[main] Initializing dependency injection...');
    await configureDependencies();
    debugPrint('[main] Dependency injection initialized successfully');

    debugPrint('[main] Initializing connectivity service...');
    await getIt<ConnectivityService>().initialize();
    debugPrint('[main] Connectivity service initialized');

    getIt<LocalServerService>().enableAutoStart(
      connectivity: getIt<ConnectivityService>(),
      storage: getIt<StorageService>(),
    );
    debugPrint('[main] Local server auto-start armed');

    debugPrint('[main] Initializing background sync (non-blocking)...');
    try {
      await BackgroundSyncService.initialize();
      debugPrint('[main] Background sync initialized successfully');
    } catch (e, stackTrace) {
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
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║ CRITICAL INITIALIZATION ERROR                             ║');
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('Error: $e');
    debugPrint('Stack trace:');
    debugPrint('$stackTrace');
    debugPrint('═══════════════════════════════════════════════════════════');

    runApp(
      const ProviderScope(
        child: POSApp(),
      ),
    );
  }
}

class POSApp extends ConsumerStatefulWidget {
  const POSApp({super.key});

  @override
  ConsumerState<POSApp> createState() => _POSAppState();
}

class _POSAppState extends ConsumerState<POSApp> {
  bool _checkedForUpdates = false;

  late final _POSAppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = _POSAppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-check for updates once after the first frame so the app can
    // enforce backend-managed remote updates immediately when required.
    if (!_checkedForUpdates) {
      _checkedForUpdates = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        getIt<UpdateCheckService>().checkForUpdates(
          force: false, // don't force; uses cache interval
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeColors = ref.watch(themeColorsProvider);

    return MaterialApp.router(
      title: 'POS System',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      checkerboardRasterCacheImages: false,
      checkerboardOffscreenLayers: false,
      theme: AppTheme.dynamicLight(themeColors.primary, themeColors.secondary),
      darkTheme: AppTheme.dynamicDark(themeColors.primary, themeColors.secondary),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final updateService = getIt<UpdateCheckService>();
        return AnimatedBuilder(
          animation: updateService,
          builder: (context, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: Stack(
              children: [
                child!,
                if (updateService.isForceUpdateRequired)
                  Positioned.fill(
                    child: ForcedUpdateGate(updateService: updateService),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _POSAppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      getIt<UpdateCheckService>().checkForUpdates(force: true);
    }
  }
}
