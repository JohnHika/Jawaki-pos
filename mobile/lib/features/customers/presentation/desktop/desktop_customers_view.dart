import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// The Customers page on a computer: a searchable list on the left, the
/// selected customer's profile on the right. Picking a row swaps the right
/// side in place, with no page change.
///
/// Plain data in, callbacks out, so a test can feed it sample customers.
class DesktopCustomersView extends StatefulWidget {
  const DesktopCustomersView({
    super.key,
    required this.title,
    required this.singular,
    required this.plural,
    required this.customers,
    required this.searchController,
    required this.onSearchChanged,
    required this.owesOnly,
    required this.onOwesOnly,
    required this.selectedId,
    required this.onSelect,
    this.detail,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.overdueCount = 0,
    this.onShowOverdue,
    this.onAdd,
  });

  /// "Customers", or the shop type's own word.
  final String title;

  /// "Customer" and "customers", for button labels and empty states.
  final String singular;
  final String plural;

  /// Rows to show, already narrowed by search and the owes filter. Each is the
  /// customer map the database returns: id, name, phone, balance, totalSpent.
  final List<Map<String, dynamic>> customers;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool owesOnly;
  final ValueChanged<bool> onOwesOnly;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// The profile for [selectedId]. null shows a hint instead.
  final Widget? detail;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final int overdueCount;
  final VoidCallback? onShowOverdue;

  /// null hides the button (the role may not add customers).
  final VoidCallback? onAdd;

  @override
  State<DesktopCustomersView> createState() => _DesktopCustomersViewState();
}

class _DesktopCustomersViewState extends State<DesktopCustomersView> {
  final FocusNode _searchFocus = FocusNode(debugLabel: 'CustomersSearch');
  final FocusNode _listFocus = FocusNode(debugLabel: 'CustomersList');
  final ScrollController _scroll = ScrollController();

  static const double _rowHeight = 56;

  @override
  void dispose() {
    _searchFocus.dispose();
    _listFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _id(Map<String, dynamic> c) => c['id']?.toString() ?? '';

  KeyEventResult _onListKey(KeyEvent event) {
    if (event is KeyUpEvent || widget.customers.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final index =
        widget.customers.indexWhere((c) => _id(c) == widget.selectedId);
    int? next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = index < 0 ? 0 : (index + 1).clamp(0, widget.customers.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = index < 0 ? 0 : (index - 1).clamp(0, widget.customers.length - 1);
    }
    if (next == null) return KeyEventResult.ignored;
    widget.onSelect(_id(widget.customers[next]));
    if (_scroll.hasClients) {
      final top = next * _rowHeight;
      final bottom = top + _rowHeight;
      final viewport = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (bottom > _scroll.offset + viewport) {
        _scroll.jumpTo(bottom - viewport);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    final addLabel = 'Add ${w.singular.toLowerCase()}';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocus.requestFocus(),
        if (w.onAdd != null)
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              w.onAdd!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: w.title,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                if (w.onAdd != null)
                  Tooltip(
                    message: '$addLabel (Ctrl+N)',
                    child: FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: w.onAdd,
                      icon:
                          const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text(addLabel),
                    ),
                  ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: DesktopListDetail(
                listWidth: 340,
                list: _listPane(context),
                detail: w.detail ??
                    DesktopEmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'Pick a ${w.singular.toLowerCase()}',
                      message:
                          'See what they bought and what they owe, then start a sale or send a statement.',
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listPane(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    final owed = w.customers.fold<double>(
      0,
      (sum, c) =>
          sum +
          (((c['balance'] as num?) ?? 0) > 0
              ? (c['balance'] as num).toDouble()
              : 0),
    );
    final owing =
        w.customers.where((c) => ((c['balance'] as num?) ?? 0) > 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: DesktopSearchField(
            controller: w.searchController,
            focusNode: _searchFocus,
            hint: 'Search name or phone',
            onChanged: w.onSearchChanged,
            onSubmitted: (_) {
              // Enter jumps to the first match, like a launcher.
              if (w.customers.isNotEmpty) w.onSelect(_id(w.customers.first));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopFilterChip(
                label: 'All',
                count: w.owesOnly ? null : w.customers.length,
                selected: !w.owesOnly,
                onTap: () => w.onOwesOnly(false),
              ),
              DesktopFilterChip(
                label: 'Owes money',
                count: w.owesOnly ? w.customers.length : null,
                selected: w.owesOnly,
                onTap: () => w.onOwesOnly(true),
              ),
            ],
          ),
        ),
        if (w.overdueCount > 0 && w.onShowOverdue != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Material(
              color: DesignColors.error.withValues(alpha: p.dark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: w.onShowOverdue,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 17, color: p.text),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${w.overdueCount} overdue payment${w.overdueCount == 1 ? '' : 's'}. Follow up today.',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Divider(height: 1, color: p.border),
        Expanded(child: _rows(context)),
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Text(
                '${formatMoney(w.customers.length, symbol: '')} '
                '${w.customers.length == 1 ? w.singular.toLowerCase() : w.plural.toLowerCase()}',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: Text(
                  owing > 0 ? 'Owed ${formatMoney(owed)}' : '',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignType.numeric(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rows(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    if (w.loading && w.customers.isEmpty) {
      return Column(
        children: [
          for (var i = 0; i < 7; i++)
            SizedBox(
              height: _rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration:
                          BoxDecoration(color: p.hover, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FractionallySizedBox(
                        widthFactor: 0.4 + (i % 3) * 0.15,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: p.hover,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (w.errorMessage != null && w.customers.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load ${w.plural.toLowerCase()}",
        message: w.errorMessage,
        action: w.onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: w.onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (w.customers.isEmpty) {
      final query = w.searchController.text.trim();
      if (query.isNotEmpty) {
        return DesktopEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No ${w.singular.toLowerCase()} called "$query"',
          message: 'Check the spelling, or try a phone number.',
        );
      }
      if (w.owesOnly) {
        return const DesktopEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'No one owes money',
          message: 'Everyone is paid up.',
        );
      }
      return DesktopEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No ${w.plural.toLowerCase()} yet',
        message:
            'Add the people who buy from you. You can then sell on credit, see what each owes and send a statement.',
        action: w.onAdd == null
            ? null
            : FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: w.onAdd,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text('Add ${w.singular.toLowerCase()}'),
              ),
      );
    }

    return Focus(
      focusNode: _listFocus,
      onKeyEvent: (_, event) => _onListKey(event),
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _rowHeight,
        itemCount: w.customers.length,
        itemBuilder: (context, i) {
          final c = w.customers[i];
          final id = _id(c);
          return _CustomerRow(
            customer: c,
            selected: id == w.selectedId,
            onTap: () {
              _listFocus.requestFocus();
              w.onSelect(id);
            },
          );
        },
      ),
    );
  }
}

class _CustomerRow extends StatefulWidget {
  const _CustomerRow({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CustomerRow> createState() => _CustomerRowState();
}

class _CustomerRowState extends State<_CustomerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final c = widget.customer;
    final name = c['name']?.toString().trim() ?? '';
    final phone = c['phone']?.toString().trim() ?? '';
    final balance = (c['balance'] as num?)?.toDouble() ?? 0;
    final initial = name.isEmpty ? '?' : String.fromCharCode(name.runes.first);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.selected
                : _hover
                    ? p.hover
                    : Colors.transparent,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.dark ? p.panelAlt : p.frame,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial.toUpperCase(),
                  style: GoogleFonts.sora(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Unnamed' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      phone.isEmpty ? 'No phone' : phone,
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
              const SizedBox(width: 8),
              if (balance > 0)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(balance),
                      style: DesignType.numeric(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: p.dark
                            ? DesignColors.error
                            : const Color(0xFFB3261E),
                      ),
                    ),
                    Text(
                      'owes',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '—',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textFaint,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
