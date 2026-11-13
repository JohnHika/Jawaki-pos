import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart' show DesktopStatusChip;
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/partner_models.dart';

/// Width of the partner list and of the info pane.
const double desktopPartnersPaneWidth = 320;

/// Below this page width the info pane floats over the conversation instead of
/// squeezing it.
const double desktopPartnersOverlayBelow = 1100;

/// The Trade partners page on a computer: partners on the left, the open
/// conversation in the middle and, when asked for, the partner's details on
/// the right.
///
/// Plain data in, callbacks out. The routed page owns the provider, the
/// selected partner and every API call; the conversation itself (messages,
/// polling, sending) is handed in through [conversationBuilder].
class DesktopPartnersView extends StatefulWidget {
  const DesktopPartnersView({
    super.key,
    required this.partners,
    required this.loadedOnce,
    required this.slug,
    required this.selectedId,
    required this.onSelect,
    required this.onConnect,
    required this.onCopyCode,
    required this.onRetry,
    required this.onAccept,
    required this.onDecline,
    required this.onCancelRequest,
    required this.onRemove,
    required this.conversationBuilder,
    this.error,
    this.title = 'Trade partners',
  });

  final List<TradePartner> partners;
  final bool loadedOnce;
  final String? error;
  final String title;

  /// This shop's own company code, shown so a partner can be given it.
  final String slug;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onConnect;
  final VoidCallback onCopyCode;
  final VoidCallback onRetry;
  final ValueChanged<TradePartner> onAccept;
  final ValueChanged<TradePartner> onDecline;
  final ValueChanged<TradePartner> onCancelRequest;

  /// Called after the person confirmed removing the partner.
  final ValueChanged<TradePartner> onRemove;
  final Widget Function(BuildContext context, TradePartner partner)
      conversationBuilder;

  @override
  State<DesktopPartnersView> createState() => _DesktopPartnersViewState();
}

class _DesktopPartnersViewState extends State<DesktopPartnersView> {
  final _search = TextEditingController();
  String _query = '';

  /// null follows the window: open when there is room, closed when it would
  /// have to float over the conversation.
  bool? _infoOpen;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TradePartner> get _connected {
    final rows = widget.partners.where((p) => p.isAccepted).toList();
    rows.sort((a, b) {
      final at = a.lastMessageAt;
      final bt = b.lastMessageAt;
      if (at == null && bt == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return rows;
  }

  void _setQuery(String value) => setState(() => _query = value.trim());

  bool _matches(TradePartner p) =>
      _query.isEmpty || p.name.toLowerCase().contains(_query.toLowerCase());

  void _move(int delta, List<TradePartner> rows) {
    if (rows.isEmpty) return;
    final index = rows.indexWhere((p) => p.id == widget.selectedId);
    final next = index < 0
        ? (delta > 0 ? 0 : rows.length - 1)
        : (index + delta).clamp(0, rows.length - 1);
    widget.onSelect(rows[next].id);
  }

  Future<void> _confirmRemove(TradePartner partner) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${partner.name}?'),
        content: const Text(
          'You will stop seeing each other’s messages. You can connect again later with a new request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep partner'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) widget.onRemove(partner);
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final connected = _connected;
    final unread = connected.fold<int>(0, (sum, e) => sum + e.unreadCount);
    final selected =
        connected.where((e) => e.id == widget.selectedId).firstOrNull;
    final nothingYet = widget.loadedOnce && widget.partners.isEmpty;

    final subtitle = widget.partners.isEmpty
        ? 'Suppliers, wholesalers and other shops you trade with'
        : '${connected.length} ${connected.length == 1 ? 'partner' : 'partners'}'
            '${unread > 0 ? ', $unread unread' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: widget.title,
          subtitle: subtitle,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            if (widget.slug.isNotEmpty)
              Tooltip(
                message: 'Copy your company code',
                child: OutlinedButton.icon(
                  style: desktopSecondaryButton(context),
                  onPressed: widget.onCopyCode,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text('Your code: ${widget.slug}'),
                ),
              ),
            FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: widget.onConnect,
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text('Connect'),
            ),
          ],
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: nothingYet
              ? (widget.error != null
                  ? _ListError(message: widget.error, onRetry: widget.onRetry)
                  : _FirstRun(
                      slug: widget.slug,
                      onConnect: widget.onConnect,
                      onCopyCode: widget.onCopyCode,
                    ))
              : _body(context, p, connected, selected),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    DesktopPalette p,
    List<TradePartner> connected,
    TradePartner? selected,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= desktopPartnersOverlayBelow;
        final infoOpen = _infoOpen ?? wide;
        final inspector = selected != null && infoOpen
            ? DesktopInspector(
                title: selected.name,
                subtitle: 'Trade partner',
                onClose: () => setState(() => _infoOpen = false),
                footer: OutlinedButton.icon(
                  style: desktopSecondaryButton(context).copyWith(
                    foregroundColor:
                        const WidgetStatePropertyAll(DesignColors.error),
                  ),
                  onPressed: () => _confirmRemove(selected),
                  icon: const Icon(Icons.link_off_rounded, size: 17),
                  label: const Text('Remove partner'),
                ),
                child: _PartnerInfo(partner: selected),
              )
            : null;

        return Row(
          children: [
            SizedBox(
              width: desktopPartnersPaneWidth,
              child: _ListPane(
                state: this,
                palette: p,
                connected: connected,
              ),
            ),
            VerticalDivider(width: 1, color: p.border),
            Expanded(
              child: DesktopInspectorLayout(
                inspectorWidth: desktopPartnersPaneWidth,
                // The list is already beside this pane, so the page-wide
                // breakpoint is applied here instead of the layout's own.
                overlayBelow: wide ? 0 : double.infinity,
                onClose: () => setState(() => _infoOpen = false),
                inspector: inspector,
                main: selected == null
                    ? _NoSelection(
                        hasPartners: connected.isNotEmpty,
                        onConnect: widget.onConnect,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ConversationHeader(
                            partner: selected,
                            infoOpen: infoOpen,
                            onToggleInfo: () =>
                                setState(() => _infoOpen = !infoOpen),
                          ),
                          Divider(height: 1, color: p.border),
                          Expanded(
                            child: widget.conversationBuilder(
                              context,
                              selected,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The left column: search, then requests, partners and sent requests.
class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.state,
    required this.palette,
    required this.connected,
  });

  final _DesktopPartnersViewState state;
  final DesktopPalette palette;
  final List<TradePartner> connected;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final p = palette;
    final incoming = w.partners
        .where((e) => e.isIncomingRequest && state._matches(e))
        .toList();
    final outgoing = w.partners
        .where((e) => e.isOutgoingRequest && state._matches(e))
        .toList();
    final rows = connected.where(state._matches).toList();
    final nothingMatches = state._query.isNotEmpty &&
        incoming.isEmpty &&
        outgoing.isEmpty &&
        rows.isEmpty;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          state._move(1, rows);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          state._move(-1, rows);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: DesktopSearchField(
              controller: state._search,
              hint: 'Search partners',
              onChanged: state._setQuery,
            ),
          ),
          if (w.error != null && w.partners.isNotEmpty)
            _RefreshNotice(message: w.error!, onRetry: w.onRetry),
          Expanded(
            child: !w.loadedOnce && w.partners.isEmpty
                ? const _ListSkeleton()
                : w.partners.isEmpty
                    ? _ListError(message: w.error, onRetry: w.onRetry)
                    : nothingMatches
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No partner called "${state._query}"',
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
                              if (incoming.isNotEmpty) ...[
                                _SectionLabel('Requests for you',
                                    count: incoming.length),
                                for (final r in incoming)
                                  _RequestRow(
                                    partner: r,
                                    onAccept: () => w.onAccept(r),
                                    onDecline: () => w.onDecline(r),
                                  ),
                              ],
                              if (rows.isNotEmpty) ...[
                                _SectionLabel('Partners', count: rows.length),
                                for (final r in rows)
                                  _PartnerRow(
                                    partner: r,
                                    selected: r.id == w.selectedId,
                                    onTap: () => w.onSelect(r.id),
                                  ),
                              ],
                              if (outgoing.isNotEmpty) ...[
                                _SectionLabel('Waiting for a reply',
                                    count: outgoing.length),
                                for (final r in outgoing)
                                  _OutgoingRow(
                                    partner: r,
                                    onCancel: () => w.onCancelRequest(r),
                                  ),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        '$text  $count',
        style: GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _shortTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  if (diff == 1) return 'Yesterday';
  return '${time.day}/${time.month}/${time.year % 100}';
}

/// A partner's initial in a soft tile, or their logo when they have one.
class PartnerAvatar extends StatelessWidget {
  const PartnerAvatar({super.key, required this.partner, this.size = 36});

  final TradePartner partner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final logo = partner.logo;
    final letter = Text(
      partner.initial,
      style: GoogleFonts.sora(
        color: p.dark ? DesignColors.accent : p.accent,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.selected,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: logo != null && logo.startsWith('http')
          ? Image.network(
              logo,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => letter,
            )
          : letter,
    );
  }
}

class _PartnerRow extends StatefulWidget {
  const _PartnerRow({
    required this.partner,
    required this.selected,
    required this.onTap,
  });

  final TradePartner partner;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PartnerRow> createState() => _PartnerRowState();
}

class _PartnerRowState extends State<_PartnerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final partner = widget.partner;
    final unread = partner.unreadCount > 0;
    final preview = partner.lastMessageBody == null
        ? 'No messages yet'
        : '${partner.lastMessageFromMe ? 'You: ' : ''}${partner.lastMessageBody}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 60,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.selected
                : _hover
                    ? p.hover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              PartnerAvatar(partner: partner),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 13.5,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: unread ? p.text : p.textMuted,
                        fontSize: 12.5,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (partner.lastMessageAt != null)
                    Text(
                      _shortTime(partner.lastMessageAt!),
                      style: GoogleFonts.plusJakartaSans(
                        color: unread ? p.text : p.textFaint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (unread) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: DesignColors.accent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${partner.unreadCount}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: DesignColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.partner,
    required this.onAccept,
    required this.onDecline,
  });

  final TradePartner partner;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final note = partner.message?.trim() ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PartnerAvatar(partner: partner),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Wants to connect with you',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 46),
              child: Text(
                '“$note”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 46),
            child: Row(
              children: [
                FilledButton(
                  style: desktopPrimaryButton(context).copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
                    padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 14)),
                  ),
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
                const SizedBox(width: 6),
                TextButton(
                  style: desktopLinkButton(context).copyWith(
                    foregroundColor: WidgetStatePropertyAll(p.textMuted),
                  ),
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutgoingRow extends StatelessWidget {
  const _OutgoingRow({required this.partner, required this.onCancel});

  final TradePartner partner;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          PartnerAvatar(partner: partner),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Request sent, waiting for them',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: desktopLinkButton(context),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
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
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: p.hover,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(110, 11),
                    const SizedBox(height: 7),
                    bar(170, 9),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ListError extends StatelessWidget {
  const _ListError({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DesktopEmptyState(
      icon: message != null ? Icons.cloud_off_rounded : Icons.groups_2_rounded,
      title: message != null
          ? "Couldn't load your partners"
          : 'No partners yet',
      message: message ?? 'Partners you connect with will be listed here.',
      action: message == null
          ? null
          : OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Try again'),
            ),
    );
  }
}

class _RefreshNotice extends StatelessWidget {
  const _RefreshNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            style: desktopLinkButton(context),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.partner,
    required this.infoOpen,
    required this.onToggleInfo,
  });

  final TradePartner partner;
  final bool infoOpen;
  final VoidCallback onToggleInfo;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(
          children: [
            PartnerAvatar(partner: partner, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    partner.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(
                      color: p.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (partner.slug.isNotEmpty)
                    Text(
                      partner.slug,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: infoOpen ? 'Hide details (Esc)' : 'Partner details',
              onPressed: onToggleInfo,
              isSelected: infoOpen,
              icon: const Icon(Icons.info_outline_rounded, size: 20),
              selectedIcon: Icon(
                Icons.info_rounded,
                size: 20,
                color: p.dark ? DesignColors.accent : p.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The details pane: what the app knows about this partner.
class _PartnerInfo extends StatelessWidget {
  const _PartnerInfo({required this.partner});

  final TradePartner partner;

  String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
    final note = partner.message?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PartnerAvatar(partner: partner, size: 48),
            const SizedBox(width: 12),
            const DesktopStatusChip(label: 'Connected', color: DesignColors.success),
          ],
        ),
        const SizedBox(height: 20),
        if (partner.slug.isNotEmpty) row('Company code', partner.slug),
        row('Connected since', _date(partner.createdAt)),
        row(
          'Last message',
          partner.lastMessageAt == null
              ? 'No messages yet'
              : '${_date(partner.lastMessageAt!)}, ${_shortTime(partner.lastMessageAt!)}',
        ),
        if (partner.unreadCount > 0)
          row('Unread', '${partner.unreadCount}'),
        if (note.isNotEmpty) row('Their note when connecting', '“$note”'),
      ],
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection({required this.hasPartners, required this.onConnect});

  final bool hasPartners;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return DesktopEmptyState(
      icon: Icons.forum_outlined,
      title: hasPartners ? 'Pick a partner to message' : 'No partners to message yet',
      message: hasPartners
          ? 'Choose a partner on the left to read and send messages about orders, prices and deliveries.'
          : 'Once a business accepts your request, you can message each other here.',
      action: hasPartners
          ? null
          : OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: onConnect,
              icon: const Icon(Icons.add_link_rounded, size: 17),
              label: const Text('Connect with a business'),
            ),
    );
  }
}

/// The page before any partner exists: says what the page is for and how to
/// start.
class _FirstRun extends StatelessWidget {
  const _FirstRun({
    required this.slug,
    required this.onConnect,
    required this.onCopyCode,
  });

  final String slug;
  final VoidCallback onConnect;
  final VoidCallback onCopyCode;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return DesktopEmptyState(
      icon: Icons.handshake_outlined,
      title: 'Connect with the businesses you trade with',
      message:
          'Add a supplier, wholesaler or another shop with their company code. Once they accept, you can message each other right here.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            style: desktopPrimaryButton(context),
            onPressed: onConnect,
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text('Connect with a business'),
          ),
          if (slug.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Or give them your code',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              style: desktopLinkButton(context),
              onPressed: onCopyCode,
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: Text(slug),
            ),
          ],
        ],
      ),
    );
  }
}
