import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../domain/app_notification.dart';
import '../providers/notifications_provider.dart';

/// The notification inbox: everything the app told the user (partner
/// requests and messages, stock decisions, reminders), newest first, with
/// unread highlighted. Tapping an item marks it read and opens the screen
/// it is about.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationInboxProvider);
    final controller = ref.read(notificationInboxProvider.notifier);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Notifications',
        actions: [
          if (inbox.unreadCount > 0)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: _body(context, ref, inbox, controller),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, NotificationInboxState inbox,
      NotificationInboxController controller) {
    if (!inbox.loadedOnce && inbox.items.isEmpty) {
      return const _InboxSkeleton();
    }
    if (inbox.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.notifications_none_rounded,
              size: 56, color: context.themed(DesignColors.darkTextTertiary)),
          const SizedBox(height: DesignSpacing.lg),
          Center(
            child: Text(
              "You're all caught up",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.themed(DesignColors.darkTextPrimary),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: DesignSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xxl),
            child: Text(
              inbox.error ??
                  'Partner requests, stock decisions and reminders will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.themed(DesignColors.darkTextSecondary),
                  ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
          DesignSpacing.lg, DesignSpacing.xxxl),
      itemCount: inbox.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: DesignSpacing.sm),
      itemBuilder: (context, index) {
        final item = inbox.items[index];
        return SoftEntrance(
          delay: Duration(milliseconds: 40 * index.clamp(0, 8)),
          child: _NotificationTile(
            notification: item,
            onTap: () {
              controller.markRead(item);
              final route = routeForNotification(item.type, item.data);
              if (route != '/notifications') context.push(route);
            },
          ),
        );
      },
    );
  }
}

/// Placeholder rows shown while the inbox loads for the first time.
class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    final fill = context.themed(DesignColors.darkSurfaceElevated);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DesignSpacing.lg),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
            child: ShimmerSweep(
              delay: Duration(milliseconds: 150 * i),
              child: Container(
                padding: const EdgeInsets.all(DesignSpacing.lg),
                decoration: BoxDecoration(
                  color: context.themed(DesignColors.darkSurface),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  border:
                      Border.all(color: context.themed(DesignColors.darkBorder)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration:
                          BoxDecoration(color: fill, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(140, 12),
                          const SizedBox(height: 8),
                          bar(double.infinity, 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  static IconData _icon(String type) => switch (type) {
        'partner_request' => Icons.person_add_alt_1_rounded,
        'partner_accepted' => Icons.handshake_rounded,
        'partner_message' => Icons.chat_bubble_rounded,
        'stock_request_resolved' => Icons.inventory_2_rounded,
        'low_stock_alert' => Icons.warning_amber_rounded,
        'restock_suggestion' => Icons.shopping_cart_checkout_rounded,
        'eod_reminder' => Icons.event_available_rounded,
        _ => Icons.notifications_rounded,
      };

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = notification.isUnread;
    return Material(
      color: unread
          ? DesignColors.accent.withValues(alpha: 0.08)
          : context.themed(DesignColors.darkSurface),
      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(DesignSpacing.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(
              color: unread
                  ? DesignColors.accent.withValues(alpha: 0.28)
                  : context.themed(DesignColors.darkBorder),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                ),
                child: Icon(_icon(notification.type),
                    size: 20, color: DesignColors.accentDark),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: context.themed(DesignColors.darkTextPrimary),
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: DesignSpacing.sm),
                            decoration: const BoxDecoration(
                              color: DesignColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.themed(DesignColors.darkTextSecondary),
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: DesignSpacing.xs),
                    Text(
                      _ago(notification.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: context.themed(DesignColors.darkTextTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
