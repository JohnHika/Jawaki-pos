import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/app_notification.dart';

/// Width of the list column. The detail takes the rest.
const double desktopInboxListWidth = 400;

/// The kind of thing a notification is about, used to group the list.
enum InboxGroup {
  partners('Partners'),
  stock('Stock'),
  alerts('Shop alerts'),
  reminders('Reminders'),
  news('News'),
  money('Money'),
  devices('Devices'),
  other('Other');

  const InboxGroup(this.label);
  final String label;
}

InboxGroup inboxGroupOf(String type) => switch (type) {
      'partner_request' || 'partner_accepted' || 'partner_message' =>
        InboxGroup.partners,
      'stock_request_resolved' ||
      'low_stock_alert' ||
      'restock_suggestion' =>
        InboxGroup.stock,
      'accountability_alert' => InboxGroup.alerts,
      'eod_reminder' || 'daily_summary' => InboxGroup.reminders,
      'business_news' => InboxGroup.news,
      'statement_claim' ||
      'statement_viewed' ||
      'referral_reward' =>
        InboxGroup.money,
      'desktop_link_request' ||
      'desktop_link_claimed' ||
      'desktop_link_denied' =>
        InboxGroup.devices,
      _ => InboxGroup.other,
    };

IconData inboxIconOf(String type) => switch (type) {
      'partner_request' => Icons.person_add_alt_1_rounded,
      'partner_accepted' => Icons.handshake_rounded,
      'partner_message' => Icons.chat_bubble_outline_rounded,
      'stock_request_resolved' => Icons.inventory_2_outlined,
      'low_stock_alert' => Icons.warning_amber_rounded,
      'restock_suggestion' => Icons.shopping_cart_checkout_rounded,
      'eod_reminder' => Icons.event_available_rounded,
      'daily_summary' => Icons.summarize_outlined,
      'accountability_alert' => Icons.flag_outlined,
      'business_news' => Icons.newspaper_rounded,
      'statement_claim' || 'statement_viewed' => Icons.receipt_long_outlined,
      'referral_reward' => Icons.card_giftcard_rounded,
      'desktop_link_request' ||
      'desktop_link_claimed' ||
      'desktop_link_denied' =>
        Icons.desktop_windows_outlined,
      _ => Icons.notifications_none_rounded,
    };

/// The label of the button that opens the screen a notification is about.
String? inboxOpenLabel(AppNotification n) {
  final route = routeForNotification(n.type, n.data);
  return switch (route) {
    '/notifications' => null,
    '/partners' => 'Open trade partners',
    '/inventory' => 'Open stock',
    '/cash-flow/end-of-day' => 'Open end of day',
    '/shop-alerts' => 'Open shop alerts',
    '/news' => 'Open business news',
    '/statements/replies' => 'Open statement replies',
    '/settings/desktop-approvals' => 'Open device approvals',
    '/referrals' => 'Open referrals',
    _ when route.startsWith('/partners/') => 'Open conversation',
    _ => 'Open',
  };
}

String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${time.day}/${time.month}/${time.year}';
}

String _fullDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// The notification inbox on a computer: a grouped list on the left, the
/// selected notification on the right, with its action ready to press.
///
/// Plain data in, callbacks out: the routed page owns the provider and decides
/// what "open", "accept" and "mark read" do.
class DesktopNotificationsView extends StatefulWidget {
  const DesktopNotificationsView({
    super.key,
    required this.items,
    required this.unreadCount,
    required this.loadedOnce,
    required this.selectedId,
    required this.onSelect,
    required this.onOpen,
    required this.onMarkAllRead,
    required this.onRetry,
    required this.canAct,
    required this.onAccept,
    required this.onDecline,
    this.error,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final bool loadedOnce;
  final String? error;
  final String? selectedId;
  final ValueChanged<AppNotification?> onSelect;

  /// Go to the screen the notification is about.
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onMarkAllRead;
  final VoidCallback onRetry;

  /// True when Accept and Decline can be pressed right here (a partner
  /// request that is still waiting).
  final bool Function(AppNotification n) canAct;
  final ValueChanged<AppNotification> onAccept;
  final ValueChanged<AppNotification> onDecline;

  @override
  State<DesktopNotificationsView> createState() =>
      _DesktopNotificationsViewState();
}

class _DesktopNotificationsViewState extends State<DesktopNotificationsView> {
  bool _unreadOnly = false;

  void _setUnreadOnly(bool value) => setState(() => _unreadOnly = value);

  List<AppNotification> get _visible {
    final rows = widget.items
        .where((n) => !_unreadOnly || n.isUnread || n.id == widget.selectedId)
        .toList();
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  /// Rows in the order they are drawn: grouped, newest first inside a group.
  List<AppNotification> get _ordered {
    final rows = _visible;
    return [
      for (final g in InboxGroup.values)
        ...rows.where((n) => inboxGroupOf(n.type) == g),
    ];
  }

  void _move(int delta) {
    final rows = _ordered;
    if (rows.isEmpty) return;
    final index = rows.indexWhere((n) => n.id == widget.selectedId);
    final next = index < 0
        ? (delta > 0 ? 0 : rows.length - 1)
        : (index + delta).clamp(0, rows.length - 1);
    widget.onSelect(rows[next]);
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final selected =
        widget.items.where((n) => n.id == widget.selectedId).firstOrNull;
    final empty = widget.loadedOnce && widget.items.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'Notifications',
          subtitle: widget.unreadCount > 0
              ? '${widget.unreadCount} unread'
              : 'You are all caught up',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            if (widget.unreadCount > 0)
              OutlinedButton.icon(
                style: desktopSecondaryButton(context),
                onPressed: widget.onMarkAllRead,
                icon: const Icon(Icons.done_all_rounded, size: 17),
                label: const Text('Mark all read'),
              ),
          ],
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: empty
              ? (widget.error != null
                  ? DesktopEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: "Couldn't load notifications",
                      message: widget.error,
                      action: OutlinedButton.icon(
                        style: desktopSecondaryButton(context),
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text('Try again'),
                      ),
                    )
                  : const DesktopEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: "You're all caught up",
                      message:
                          'Partner requests, stock decisions and reminders will show up here, and you can act on them without leaving this page.',
                    ))
              : Row(
                  children: [
                    SizedBox(
                      width: desktopInboxListWidth,
                      child: _ListPane(state: this),
                    ),
                    VerticalDivider(width: 1, color: p.border),
                    Expanded(
                      child: selected == null
                          ? const DesktopEmptyState(
                              icon: Icons.mark_email_unread_outlined,
                              title: 'Select a notification',
                              message:
                                  'Pick one on the left to read it and act on it here.',
                            )
                          : _Detail(
                              notification: selected,
                              canAct: widget.canAct(selected),
                              onOpen: () => widget.onOpen(selected),
                              onAccept: () => widget.onAccept(selected),
                              onDecline: () => widget.onDecline(selected),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ListPane extends StatelessWidget {
  const _ListPane({required this.state});

  final _DesktopNotificationsViewState state;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final p = DesktopPalette.of(context);
    final rows = state._visible;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          state._move(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          state._move(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                DesktopFilterChip(
                  label: 'All',
                  count: w.items.length,
                  selected: !state._unreadOnly,
                  onTap: () => state._setUnreadOnly(false),
                ),
                const SizedBox(width: 8),
                DesktopFilterChip(
                  label: 'Unread',
                  count: w.unreadCount,
                  selected: state._unreadOnly,
                  onTap: () => state._setUnreadOnly(true),
                ),
              ],
            ),
          ),
          if (w.error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color:
                    DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      w.error!,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  TextButton(
                    style: desktopLinkButton(context),
                    onPressed: w.onRetry,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: !w.loadedOnce && w.items.isEmpty
                ? const _ListSkeleton()
                : rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nothing unread.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          for (final g in InboxGroup.values)
                            ..._group(context, g, rows),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  List<Widget> _group(
    BuildContext context,
    InboxGroup group,
    List<AppNotification> all,
  ) {
    final w = state.widget;
    final p = DesktopPalette.of(context);
    final rows = all.where((n) => inboxGroupOf(n.type) == group).toList();
    if (rows.isEmpty) return const [];
    final unread = rows.where((n) => n.isUnread).length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Text(
              group.label,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$unread new',
                style: GoogleFonts.plusJakartaSans(
                  color: p.dark ? DesignColors.accent : p.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      for (final n in rows)
        _Row(
          notification: n,
          selected: n.id == w.selectedId,
          canAct: w.canAct(n),
          onTap: () => w.onSelect(n),
          onAccept: () => w.onAccept(n),
          onDecline: () => w.onDecline(n),
        ),
    ];
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.notification,
    required this.selected,
    required this.canAct,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
  });

  final AppNotification notification;
  final bool selected;
  final bool canAct;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final n = widget.notification;
    final unread = n.isUnread;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.selected
                : _hover
                    ? p.hover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: p.selected,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  inboxIconOf(n.type),
                  size: 17,
                  color: p.dark ? DesignColors.accent : p.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 13.5,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(n.createdAt),
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textFaint,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: DesignColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (n.body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    if (widget.canAct)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            FilledButton(
                              style: desktopPrimaryButton(context).copyWith(
                                minimumSize:
                                    const WidgetStatePropertyAll(Size(0, 28)),
                                padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(horizontal: 12)),
                              ),
                              onPressed: widget.onAccept,
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              style: desktopLinkButton(context).copyWith(
                                foregroundColor:
                                    WidgetStatePropertyAll(p.textMuted),
                              ),
                              onPressed: widget.onDecline,
                              child: const Text('Decline'),
                            ),
                          ],
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

class _Detail extends StatelessWidget {
  const _Detail({
    required this.notification,
    required this.canAct,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  final AppNotification notification;
  final bool canAct;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final n = notification;
    final openLabel = inboxOpenLabel(n);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(inboxIconOf(n.type), size: 17, color: p.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    inboxGroupOf(n.type).label,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _fullDate(n.createdAt),
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textFaint,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                n.title,
                style: GoogleFonts.sora(
                  color: p.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.3,
                ),
              ),
              if (n.body.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  n.body,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              if (canAct)
                Row(
                  children: [
                    FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: onAccept,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accept request'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      style: desktopSecondaryButton(context),
                      onPressed: onDecline,
                      child: const Text('Decline'),
                    ),
                    if (openLabel != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        style: desktopLinkButton(context),
                        onPressed: onOpen,
                        child: Text(openLabel),
                      ),
                    ],
                  ],
                )
              else if (openLabel != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: desktopPrimaryButton(context),
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(openLabel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: p.hover,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: p.hover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(150, 11),
                    const SizedBox(height: 7),
                    bar(230, 9),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
