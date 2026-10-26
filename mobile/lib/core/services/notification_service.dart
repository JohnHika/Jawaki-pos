import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
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

  /// Maps a push's `data.type` (set server-side — see
  /// backend NotificationsService/PushNotificationPayload callers) to the
  /// local category preference that gates it. Unrecognized/missing types
  /// are never silently dropped — they fall through to "always show".
  static const Map<String, String> _categoryByType = {
    'stock_request_resolved': keyNotifyInventory,
    'low_stock_alert': keyNotifyInventory,
    'restock_suggestion': keyNotifyInventory,
    'eod_reminder': keyNotifySync,
    'sync_failed': keyNotifySync,
    'sale_completed': keyNotifySales,
  };

  static const _defaultChannel = AndroidNotificationChannel(
    'axon_pos_default_channel',
    'Counterbase Alerts',
    description: 'Stock requests, inventory, sales and sync alerts',
    importance: Importance.high,
  );

  bool _initialized = false;
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
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[NotificationService] Firebase init failed: $e');
      return;
    }

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

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    // Tapped while the app was in the background...
    FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _emitOpen(Map<String, dynamic>.from(message.data)));
    // ...or tapped to launch the app from a fully closed state.
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // Initialization now runs after the first frame. Emit directly when
        // the app is already listening, or preserve the event for the cold
        // start listener when initialization happened earlier.
        _emitOpen(Map<String, dynamic>.from(initial.data));
      }
    } catch (_) {}
  }

  /// True if the OS has actually granted notification permission — separate
  /// from the in-app "Inventory Alerts"/"Sales Alerts" preference toggles,
  /// which only control which categories of push this user wants, not
  /// whether the OS allows notifications at all.
  Future<bool> hasPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Requests OS notification permission (a real system prompt on Android
  /// 13+; a no-op returning true on older Android, which never gates
  /// notifications behind runtime permission). Call this from an explicit
  /// user action (e.g. enabling a notification toggle in Settings), not
  /// silently on app start — a cold permission prompt with no context is
  /// far more likely to be denied.
  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) {
      await registerToken();
    }
    return granted;
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

  void _showForegroundNotification(RemoteMessage message) async {
    // Always refresh the in-app inbox/badge, even if the user muted this
    // category's system alerts — it is still in their notification list.
    pushArrived.value++;

    final notification = message.notification;
    if (notification == null) return;

    if (!await _isCategoryEnabled(message.data['type'])) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Whether the user's in-app category preference allows this push to be
  /// shown. An unmapped/missing `type` always returns true (fail-open —
  /// only explicitly categorized pushes can be muted). Defaults to enabled
  /// when no preference has been saved yet, matching the Settings screen's
  /// own `?? true` defaults.
  Future<bool> _isCategoryEnabled(String? type) async {
    final prefKey = _categoryByType[type];
    if (prefKey == null) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKey) ?? true;
  }
}
