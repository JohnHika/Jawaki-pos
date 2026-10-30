import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import 'app_icon_service.dart';
import 'storage_service.dart';

/// Handles push notification setup: Firebase init, permission request, FCM
/// token lifecycle (register with the backend on login, drop it on logout),
/// and presenting a system notification when a push arrives while the app
/// is in the foreground (FCM only auto-shows a tray notification when the
/// app is backgrounded/terminated — foreground delivery has to be done
/// manually via flutter_local_notifications).
class NotificationService {
  NotificationService({
    required ApiClient apiClient,
    required StorageService storage,
  })  : _apiClient = apiClient,
        _storage = storage;

  final ApiClient _apiClient;
  final StorageService _storage;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Category preference keys — settings_screen.dart's _SettingsKeys class
  // references these directly (single source of truth) so both agree on
  // where these live.
  static const String keyNotifySales = 'setting_notify_sales';
  static const String keyNotifyInventory = 'setting_notify_inventory';
  static const String keyNotifySync = 'setting_notify_sync';

  static const _defaultChannel = AndroidNotificationChannel(
    'axon_pos_default_channel',
    'Counterbase Alerts',
    description: 'Shop activity, app identity, sales and sync alerts',
    importance: Importance.high,
  );

  bool _initialized = false;
  bool _localInitialized = false;
  String? _registeredToken;

  // Tapping a notification (system tray, or the local one shown while the
  // app is open) emits its `data` map here so the app can deep-link — e.g.
  // a partner message opens that chat. Broadcast + a one-slot buffer so a
  // tap that cold-started the app isn't lost before anyone is listening.
  final StreamController<Map<String, dynamic>> _opens =
      StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? _pendingOpen;

  /// Taps on notifications, as the push's `data` payload.
  Stream<Map<String, dynamic>> get opens => _opens.stream;

  /// A tap that arrived before the app UI was listening (cold start from a
  /// notification). Returns it once, then clears it.
  Map<String, dynamic>? takePendingOpen() {
    final pending = _pendingOpen;
    _pendingOpen = null;
    return pending;
  }

  /// Bumps every time a push arrives while the app is open, so the inbox
  /// badge can refresh immediately instead of waiting for its next poll.
  final ValueNotifier<int> pushArrived = ValueNotifier<int>(0);

  static const String _promptedKey = 'notif_permission_prompted_v1';

  /// Whether the app has already shown its own "turn on alerts" explainer.
  Future<bool> hasBeenPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptedKey) ?? false;
  }

  Future<void> markPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey, true);
  }

  void _emitOpen(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    if (_opens.hasListener) {
      _opens.add(data);
    } else {
      _pendingOpen = data;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _initializeLocalNotifications();
    } catch (e) {
      debugPrint('[NotificationService] Local notification init failed: $e');
    }
    // The downloadable edition uses on-device notifications only. Push
    // registration depends on an online POS backend and is intentionally off.
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localInitialized) return;
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) _emitOpen(Map<String, dynamic>.from(decoded));
        } catch (_) {}
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_defaultChannel);
    _localInitialized = true;
  }

  /// Shows the reason the launcher identity changed. This remains independent
  /// from Firebase so a local icon update can still be explained offline.
  Future<void> showAppIconChangedNotification({
    required AppIconVariant variant,
    required bool automaticEnabled,
  }) async {
    try {
      await _initializeLocalNotifications();
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'Counterbase icon updated',
        appIconChangeReason(variant, automaticEnabled: automaticEnabled),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _defaultChannel.id,
            _defaultChannel.name,
            channelDescription: _defaultChannel.description,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationService] App icon notice failed: $e');
    }
  }

  /// A desktop computer is asking to pair (QR / approval sign-in). Shown
  /// locally by the phone server when the request arrives, so it surfaces
  /// even while the app is in the foreground.
  Future<void> showDesktopLinkRequestNotification({
    required String code,
    required String desktopName,
  }) async {
    try {
      await _initializeLocalNotifications();
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'Sign-in request: $desktopName',
        'A computer wants to open Counterbase. Review code $code in the app.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _defaultChannel.id,
            _defaultChannel.name,
            channelDescription: _defaultChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: 'desktop-link',
      );
    } catch (e) {
      debugPrint('[NotificationService] Desktop link notice failed: $e');
    }
  }

  /// True if the OS has actually granted notification permission — separate
  /// from the in-app "Inventory Alerts"/"Sales Alerts" preference toggles,
  /// which only control which categories of push this user wants, not
  /// whether the OS allows notifications at all.
  Future<bool> hasPermission() async {
    if (!_initialized) await initialize();
    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? true;
    }
    return _localInitialized;
  }

  /// Requests OS notification permission (a real system prompt on Android
  /// 13+; a no-op returning true on older Android, which never gates
  /// notifications behind runtime permission). Call this from an explicit
  /// user action (e.g. enabling a notification toggle in Settings), not
  /// silently on app start — a cold permission prompt with no context is
  /// far more likely to be denied.
  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _localNotifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final macos = _localNotifications.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) {
      return await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  /// Fetches the device's current FCM token and sends it to the backend so
  /// pushes can reach this device. Safe to call repeatedly (e.g. once per
  /// login) — re-registering the same token is a no-op server-side.
  Future<void> registerToken() async {
    if (!_initialized) await initialize();

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      _registeredToken = token;
      await _apiClient.registerPushToken(
        token: token,
        deviceUuid: _storage.getDeviceId(),
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } catch (e) {
      debugPrint('[NotificationService] Token registration failed: $e');
    }
  }

  /// Unregisters this device's token — called on logout so a signed-out
  /// device stops receiving pushes meant for the account that just left it.
  Future<void> unregisterToken() async {
    final token = _registeredToken;
    if (token == null) return;

    try {
      await _apiClient.unregisterPushToken(token);
    } catch (e) {
      debugPrint('[NotificationService] Token unregistration failed: $e');
    } finally {
      _registeredToken = null;
    }
  }
}
