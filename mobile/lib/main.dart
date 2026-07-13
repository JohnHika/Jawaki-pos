import 'dart:async';
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
import 'core/services/auth_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/update_check_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/print_queue_service.dart';
import 'core/widgets/forced_update_gate.dart';
import 'core/widgets/optional_update_prompt_host.dart';

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

    debugPrint('[main] Initializing notifications (non-blocking)...');
    try {
      final notificationService = getIt<NotificationService>();
      await notificationService.initialize();
      // Re-register the token on every cold start if the user already
      // granted permission previously — FCM tokens can rotate, and this
      // keeps the backend's copy fresh without asking again.
      if (await notificationService.hasPermission()) {
        await notificationService.registerToken();
      }
      debugPrint('[main] Notifications initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[main] Notification init failed (non-critical): $e');
      debugPrint('[main] Stack trace: $stackTrace');
    }

    // Non-blocking and best-effort: if this device isn't logged in yet, or
    // the check fails offline, printing simply stays local-only until the
    // user opens the app and it's confirmed — never worth delaying launch.
    unawaited(() async {
      try {
        if (await getIt<PrintQueueService>().isDesignatedPrinter()) {
          getIt<PrintQueueService>().startDraining();
          debugPrint('[main] This device is the designated printer — draining queue');
        }
      } catch (e) {
        debugPrint('[main] Print queue check failed (non-critical): $e');
      }
    }());

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

    return MaterialApp.router(
      title: 'Axon POS',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      checkerboardRasterCacheImages: false,
      checkerboardOffscreenLayers: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final updateService = getIt<UpdateCheckService>();
        return AnimatedBuilder(
          animation: updateService,
          builder: (context, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: OptionalUpdatePromptHost(
              updateService: updateService,
              child: Stack(
                children: [
                  child!,
                  if (updateService.isForceUpdateRequired ||
                      updateService.isPostLoginUpdateRequired)
                    Positioned.fill(
                      child: ForcedUpdateGate(updateService: updateService),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _POSAppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final authService = getIt<AuthService>();

    // Only `paused`/`detached` mean the user actually left the app.
    // `inactive` also fires for transient system UI (notification shade,
    // app-switcher preview, permission dialogs) and would otherwise trigger
    // an unwanted re-lock moments later on `resumed`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      authService.markAppBackgrounded();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      await authService.lockIfRequiredAfterResume();
      getIt<UpdateCheckService>().checkForUpdates(force: true);
      unawaited(authService.refreshPermissions());
    }
  }
}
