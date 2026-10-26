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
import 'core/services/lifecycle_lock_controller.dart';
import 'core/services/auth_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/update_check_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/print_queue_service.dart';
import 'core/services/feature_announcement_service.dart';
import 'core/widgets/forced_update_gate.dart';
import 'core/widgets/optional_update_prompt_host.dart';
import 'core/widgets/feature_announcement_host.dart';
import 'core/widgets/tap_tracker.dart';
import 'core/services/app_icon_service.dart';
import 'features/notifications/domain/app_notification.dart';

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
    await configureDependencies().timeout(const Duration(seconds: 30));
    debugPrint('[main] Dependency injection initialized successfully');

    debugPrint('[main] Initializing connectivity service...');
    await getIt<ConnectivityService>().initialize();
    debugPrint('[main] Connectivity service initialized');

    getIt<LocalServerService>().enableAutoStart(
      connectivity: getIt<ConnectivityService>(),
      storage: getIt<StorageService>(),
    );
    debugPrint('[main] Local server auto-start armed');

    // Non-blocking and best-effort: if this device isn't logged in yet, or
    // the check fails offline, printing simply stays local-only until the
    // user opens the app and it's confirmed — never worth delaying launch.
    unawaited(() async {
      try {
        if (await getIt<PrintQueueService>().isDesignatedPrinter()) {
          getIt<PrintQueueService>().startDraining();
          debugPrint(
              '[main] This device is the designated printer — draining queue');
        }
      } catch (e) {
        debugPrint('[main] Print queue check failed (non-critical): $e');
      }
    }());

    // A build that was just installed starts signed out. Settle that before
    // the first frame so the dashboard never flashes up and then vanishes.
    await getIt<UpdateCheckService>().prepareLaunch(
      endSession: () => getIt<AuthService>().logout(allDevices: true),
    );

    debugPrint('[main] All initializations complete, launching app...');

    runApp(
      const ProviderScope(
        child: POSApp(),
      ),
    );
    // Workmanager and Firebase plugin setup are useful after launch, but
    // neither is needed to render the first screen. Start them after the
    // first frame so a slow platform channel cannot hold the user on splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeDeferredServices());
    });
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

Future<void> _initializeDeferredServices() async {
  await Future.wait([
    _initializeBackgroundSync(),
    _initializeNotifications(),
  ]);
}

Future<void> _initializeBackgroundSync() async {
  debugPrint('[main] Initializing background sync after first frame...');
  try {
    await BackgroundSyncService.initialize()
        .timeout(const Duration(seconds: 15));
    debugPrint('[main] Background sync initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('[main] Background sync init failed (non-critical): $e');
    debugPrint('[main] Stack trace: $stackTrace');
  }
}

Future<void> _initializeNotifications() async {
  debugPrint('[main] Initializing notifications after first frame...');
  try {
    final notificationService = getIt<NotificationService>();
    await notificationService.initialize().timeout(const Duration(seconds: 15));
    // Re-register the token on every cold start if the user already
    // granted permission previously — FCM tokens can rotate, and this
    // keeps the backend's copy fresh without asking again.
    if (await notificationService.hasPermission()) {
      await notificationService
          .registerToken()
          .timeout(const Duration(seconds: 10));
    }
    debugPrint('[main] Notifications initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('[main] Notification init failed (non-critical): $e');
    debugPrint('[main] Stack trace: $stackTrace');
  }
}

/// Shown for a moment right after sign-in while the app finds out whether a
/// newer build is waiting, so the dashboard is not shown and then covered.
class _LoginSettlingSplash extends StatelessWidget {
  const _LoginSettlingSplash();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class POSApp extends ConsumerStatefulWidget {
  const POSApp({super.key});

  @override
  ConsumerState<POSApp> createState() => _POSAppState();
}

class _POSAppState extends ConsumerState<POSApp> with WidgetsBindingObserver {
  bool _checkedForUpdates = false;

  late final LifecycleLockController _lifecycleController;
  StreamSubscription<Map<String, dynamic>>? _notificationOpens;

  @override
  void initState() {
    super.initState();
    _lifecycleController = LifecycleLockController(
      authService: getIt<AuthService>(),
      storageService: getIt<StorageService>(),
    );
    WidgetsBinding.instance.addObserver(_lifecycleController);
    WidgetsBinding.instance.addObserver(this);

    _attachNotificationOpens();
  }

  /// Tapping a notification deep-links to what it is about (a partner chat,
  /// the inventory screen, ...). A tap that cold-started the app was
  /// buffered by the service until now. On a very slow start the service
  /// may not be registered yet (dependency setup is still finishing), so
  /// retry briefly instead of crashing the first frame.
  void _attachNotificationOpens([int attempt = 0]) {
    if (!getIt.isRegistered<NotificationService>()) {
      if (attempt < 30 && mounted) {
        Future<void>.delayed(const Duration(seconds: 1),
            () => _attachNotificationOpens(attempt + 1));
      }
      return;
    }
    final notifications = getIt<NotificationService>();
    _notificationOpens = notifications.opens.listen(_openFromNotification);
    final pending = notifications.takePendingOpen();
    if (pending != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openFromNotification(pending));
    }
  }

  void _openFromNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    final route = routeForNotification((data['type'] ?? '').toString(), data);
    try {
      ref.read(appRouterProvider).push(route);
    } catch (e) {
      debugPrint('[main] Could not open notification route $route: $e');
    }
  }

  @override
  void dispose() {
    _notificationOpens?.cancel();
    WidgetsBinding.instance.removeObserver(_lifecycleController);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The living app icon only changes as the app goes to the background, so the
  /// launcher never redraws it under the user's thumb. It is enabled by
  /// default and can be turned off in Settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!getIt.isRegistered<AppIconService>()) return;
      unawaited(getIt<AppIconService>().refresh().then<void>(
            (_) {},
            onError: (Object e) => debugPrint('[AppIcon] refresh failed: $e'),
          ));
      return;
    }

    if (state == AppLifecycleState.resumed) {
      // POS devices can stay open for days. Recheck the public release
      // manifest when the app returns to the foreground so a build published
      // during a long shift appears without requiring a manual Settings visit.
      unawaited(getIt<UpdateCheckService>().checkForUpdates(force: false));

      // Let the lifecycle lock settle first. Refreshing tenant configuration
      // while a session is being locked would waste a request and could delay
      // the unlock route.
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted || !getIt.isRegistered<AuthService>()) return;
        final authService = getIt<AuthService>();
        if (authService.isAuthenticated) {
          unawaited(authService.refreshTenantSettings());
        }
      });
    }
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

    return TapTracker(
      router: router,
      child: MaterialApp.router(
        title: 'Counterbase',
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
          final featureService = getIt<FeatureAnnouncementService>();
          // Status and navigation bars melt into the app and their icons stay
          // readable in both themes, like a native app rather than a web view.
          final dark = Theme.of(context).brightness == Brightness.dark;
          final icons = dark ? Brightness.light : Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: icons,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: icons,
              systemNavigationBarContrastEnforced: false,
            ),
            child: AnimatedBuilder(
              animation: updateService,
              builder: (context, _) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.noScaling),
                child: FeatureAnnouncementHost(
                  service: featureService,
                  child: OptionalUpdatePromptHost(
                    updateService: updateService,
                    child: Stack(
                      children: [
                        child!,
                        if (updateService.isSettlingAfterLogin &&
                            !updateService.isForceUpdateRequired &&
                            !updateService.isPostLoginUpdateRequired)
                          const Positioned.fill(child: _LoginSettlingSplash()),
                        if (updateService.isForceUpdateRequired ||
                            updateService.isPostLoginUpdateRequired)
                          Positioned.fill(
                            child:
                                ForcedUpdateGate(updateService: updateService),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
