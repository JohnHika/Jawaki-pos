import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../partners/presentation/providers/partners_provider.dart';
import '../../domain/app_notification.dart';
import '../providers/notifications_provider.dart';
import 'desktop_notifications_view.dart';

/// The routed notification inbox inside the desktop shell. Same provider as
/// the phone page; only "which notification is open" is kept locally.
///
/// Opening a notification marks it read, like a tap does on the phone. A
/// partner request that is still waiting can be accepted or declined here,
/// through the same partners controller the Trade partners page uses.
class DesktopNotificationsPage extends ConsumerStatefulWidget {
  const DesktopNotificationsPage({super.key});

  @override
  ConsumerState<DesktopNotificationsPage> createState() =>
      _DesktopNotificationsPageState();
}

class _DesktopNotificationsPageState
    extends ConsumerState<DesktopNotificationsPage> {
  String? _selected;

  String? _partnershipId(AppNotification n) {
    final id = n.data['partnershipId']?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  bool _canAct(AppNotification n) {
    if (n.type != 'partner_request') return false;
    final id = _partnershipId(n);
    if (id == null) return false;
    return ref.read(partnersProvider).byId(id)?.isIncomingRequest ?? false;
  }

  Future<void> _answer(AppNotification n, {required bool accept}) async {
    final id = _partnershipId(n);
    if (id == null) return;
    final controller = ref.read(partnersProvider.notifier);
    final partner = ref.read(partnersProvider).byId(id);
    final name = partner?.name ?? 'This business';
    try {
      if (accept) {
        await controller.accept(id);
      } else {
        await controller.decline(id);
      }
      ref.read(notificationInboxProvider.notifier).markRead(n);
      if (mounted) {
        showGlassSnackBar(
          context,
          accept ? 'You are now connected with $name' : 'Request declined',
          icon: Icons.check_circle_rounded,
          color: DesignColors.success,
        );
      }
    } on PartnerActionException catch (e) {
      if (mounted) {
        showGlassSnackBar(context, e.message,
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider);
    // Rebuild when partner requests change, so Accept disappears once used.
    ref.watch(partnersProvider);
    final controller = ref.read(notificationInboxProvider.notifier);

    return Scaffold(
      body: DesktopNotificationsView(
        items: inbox.items,
        unreadCount: inbox.unreadCount,
        loadedOnce: inbox.loadedOnce,
        error: inbox.error,
        selectedId: _selected,
        onSelect: (n) {
          setState(() => _selected = n?.id);
          if (n != null) controller.markRead(n);
        },
        onOpen: (n) {
          controller.markRead(n);
          final route = routeForNotification(n.type, n.data);
          if (route != '/notifications') context.push(route);
        },
        onMarkAllRead: controller.markAllRead,
        onRetry: controller.refresh,
        canAct: _canAct,
        onAccept: (n) => _answer(n, accept: true),
        onDecline: (n) => _answer(n, accept: false),
      ),
    );
  }
}
