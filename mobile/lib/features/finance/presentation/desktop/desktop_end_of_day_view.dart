import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'desktop_cash_flow_view.dart';
import 'desktop_figures_row.dart';

/// One line of a sales or till-close ledger: a label and an already formatted
/// amount. A value that starts with "-" is drawn in the loss colour.
class DesktopEodRow {
  const DesktopEodRow(
    this.label,
    this.value, {
    this.strong = false,
    this.note,
  });

  final String label;
  final String value;
  final bool strong;
  final String? note;
}

/// A short message above the figures (an unverified total, a late payment).
class DesktopEodNotice {
  const DesktopEodNotice(this.text, {this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;
}

/// A quiet button under the close details (add an expense, match a statement).
class DesktopEodAction {
  const DesktopEodAction(this.label, this.icon, this.onPressed);

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// The End of day page on a computer: the day's takings in one strip, a
/// ledger of how they were paid, and a side panel with the close status and
/// the one filled "Close end of day" button.
///
/// Plain data in. The routed screen reads the providers and keeps the close
/// sheets; nothing here touches a database.
class DesktopEndOfDayView extends StatelessWidget {
  const DesktopEndOfDayView({
    super.key,
    this.title = 'End of day',
    this.dateLabel,
    this.closed = false,
    this.statusLabel = '',
    this.notices = const [],
    this.figures = const [],
    this.salesRows = const [],
    this.closeTitle = 'Close details',
    this.closeRows = const [],
    this.closeNote,
    this.actions = const [],
    this.primaryLabel = 'Close end of day',
    this.onPrimary,
    this.onBack,
    this.onRefresh,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.emptyTitle,
    this.emptyMessage,
    this.restricted = false,
  });

  final String title;
  final String? dateLabel;
  final bool closed;

  /// "Today is still open", "Day closed at 18:42".
  final String statusLabel;
  final List<DesktopEodNotice> notices;
  final List<DesktopFigure> figures;
  final List<DesktopEodRow> salesRows;
  final String closeTitle;
  final List<DesktopEodRow> closeRows;
  final String? closeNote;
  final List<DesktopEodAction> actions;
  final String primaryLabel;

  /// null greys the primary button out.
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String? emptyTitle;
  final String? emptyMessage;

  /// The role may not close the day.
  final bool restricted;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              onRefresh!,
        if (onPrimary != null)
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              onPrimary!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: title,
              subtitle: dateLabel,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              leading: onBack == null
                  ? null
                  : IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
              actions: [
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                if (!restricted &&
                    errorMessage == null &&
                    emptyTitle == null &&
                    !loading)
                  Tooltip(
                    message: 'Ctrl+Enter',
                    child: FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: onPrimary,
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: Text(primaryLabel),
                    ),
                  ),
              ],
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (restricted) {
      return const DesktopEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'End of day is restricted',
        message:
            'You do not have permission to close the end of day. Ask an admin to grant it.',
      );
    }
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (errorMessage != null) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load today's figures",
        message: errorMessage,
        action: onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (emptyTitle != null) {
      return DesktopEmptyState(
        icon: Icons.store_mall_directory_outlined,
        title: emptyTitle!,
        message: emptyMessage,
      );
    }
    return SingleChildScrollView(
      child: DesktopContent(
        maxWidth: 1100 + 2 * DesktopTokens.gutter,
        padding: const EdgeInsets.fromLTRB(
          DesktopTokens.gutter,
          6,
          DesktopTokens.gutter,
          DesktopTokens.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final n in notices) ...[
              _Notice(notice: n),
              const SizedBox(height: 10),
            ],
            if (figures.isNotEmpty) ...[
              DesktopFiguresRow(figures: figures),
              const SizedBox(height: 16),
            ],
            LayoutBuilder(
              builder: (context, box) {
                final ledger = _Ledger(title: "Today's sales", rows: salesRows);
                final side = _closePanel(context);
                if (box.maxWidth < 860) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [ledger, const SizedBox(height: 16), side],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ledger),
                    const SizedBox(width: 16),
                    SizedBox(width: 340, child: side),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _closePanel(BuildContext context) {
    final p = context.desktop;
    return DesktopSidePanel(
      title: closeTitle,
      trailing: DesktopStatusChip(
        label: closed ? 'Closed' : 'Open',
        color: closed ? DesignColors.success : DesignColors.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            statusLabel,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (closeRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final r in closeRows) _kv(context, r),
            Divider(height: 1, color: p.border),
          ],
          if (closeNote != null) ...[
            const SizedBox(height: 10),
            Text(
              closeNote!,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
          for (final a in actions) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: a.onPressed,
              icon: Icon(a.icon, size: 18),
              label: Text(a.label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, DesktopEodRow r) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              r.label,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            r.value,
            style: DesignType.numeric(
              fontSize: 13.5,
              color: _tone(p, r.value) ?? p.text,
            ),
          ),
        ],
      ),
    );
  }
}

Color? _tone(DesktopPalette p, String value) =>
    value.startsWith('-') ? negativeAmountColor(p) : null;

class _Notice extends StatelessWidget {
  const _Notice({required this.notice});

  final DesktopEodNotice notice;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(notice.icon, size: 18, color: DesignColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.text,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.title, required this.rows});

  final String title;
  final List<DesktopEodRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final head = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: head)),
                Text('Amount', style: head),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            Container(
              color: rows[i].strong ? (p.dark ? p.hover : p.panelAlt) : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].label,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 13.5,
                            fontWeight: rows[i].strong
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (rows[i].note != null)
                          Text(
                            rows[i].note!,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.textFaint,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    rows[i].value,
                    style: DesignType.numeric(
                      fontSize: rows[i].strong ? 15 : 13.5,
                      fontWeight:
                          rows[i].strong ? FontWeight.w800 : FontWeight.w700,
                      color: _tone(p, rows[i].value) ?? p.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
