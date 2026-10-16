import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/notification_service.dart';
import '../../domain/app_notification.dart';

class NotificationInboxState {
  const NotificationInboxState({
    this.items = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.loadedOnce = false,
    this.error,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final bool isLoading;
  final bool loadedOnce;
  final String? error;

  NotificationInboxState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    bool? isLoading,
    bool? loadedOnce,
    String? error,
    bool clearError = false,
  }) =>
      NotificationInboxState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        isLoading: isLoading ?? this.isLoading,
        loadedOnce: loadedOnce ?? this.loadedOnce,
        error: clearError ? null : (error ?? this.error),
      );
}

/// The signed-in user's notification inbox. Refreshes on open, every minute
/// while the app is running, and instantly when a push arrives in the
/// foreground — so the bell badge stays honest without the user pulling.
class NotificationInboxController extends StateNotifier<NotificationInboxState> {
  NotificationInboxController() : super(const NotificationInboxState()) {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    try {
      getIt<NotificationService>().pushArrived.addListener(_onPush);
    } catch (_) {}
    refresh();
  }

  Timer? _timer;

  void _onPush() => refresh();

  Future<void> refresh() async {
    if (state.isLoading) return;
    // Keep an earlier error showing during a retry (the 30-second poll would
    // otherwise keep flipping the page back to "all caught up").
    state = state.copyWith(isLoading: true);
    try {
      final data = await getIt<ApiClient>().getNotifications();
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      state = state.copyWith(
        items: items,
        unreadCount: (data['unreadCount'] as num?)?.toInt() ??
            items.where((n) => n.isUnread).length,
        isLoading: false,
        loadedOnce: true,
        clearError: true,
      );
    } catch (e) {
      // Offline / signed out / server hiccup: keep what we had.
      if (!kReleaseMode) debugPrint('[Inbox] refresh failed: $e');
      state = state.copyWith(
        isLoading: false,
        loadedOnce: true,
        error: 'Could not refresh notifications.',
      );
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (!notification.isUnread) return;
    state = state.copyWith(
      items: [
        for (final n in state.items)
          if (n.id == notification.id) n.markedRead() else n,
      ],
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );
    try {
      await getIt<ApiClient>().markNotificationRead(notification.id);
    } catch (_) {
      // Next refresh reconciles with the server.
    }
  }

  Future<void> markAllRead() async {
    state = state.copyWith(
      items: [for (final n in state.items) n.markedRead()],
      unreadCount: 0,
    );
    try {
      await getIt<ApiClient>().markAllNotificationsRead();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      getIt<NotificationService>().pushArrived.removeListener(_onPush);
    } catch (_) {}
    super.dispose();
  }
}

final notificationInboxProvider = StateNotifierProvider<
    NotificationInboxController, NotificationInboxState>(
  (ref) => NotificationInboxController(),
);
