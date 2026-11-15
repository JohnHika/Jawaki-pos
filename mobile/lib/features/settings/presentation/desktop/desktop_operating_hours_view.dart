import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'desktop_sub_page.dart';
import 'settings_desktop_widgets.dart';

/// One weekday in the operating hours editor, as plain values.
class DesktopHoursDay {
  const DesktopHoursDay({
    required this.key,
    required this.label,
    required this.closed,
    required this.open,
    required this.close,
    required this.hasBreak,
    required this.breakStart,
    required this.breakEnd,
  });

  final String key;
  final String label;
  final bool closed;
  final String open;
  final String close;
  final bool hasBreak;
  final String breakStart;
  final String breakEnd;
}

/// Which time of a day is being changed.
enum DesktopHoursField { open, close, breakStart, breakEnd }

/// Operating hours on a computer: the week as one table (day, open switch,
/// opens, closes, midday break) with Save in the header and on Ctrl+S.
///
/// Takes plain data; the routed screen owns loading, saving and the picker.
class DesktopOperatingHoursView extends StatelessWidget {
  const DesktopOperatingHoursView({
    super.key,
    required this.days,
    required this.weekStartDay,
    required this.weekStartOptions,
    required this.saving,
    required this.onWeekStart,
    required this.onOpenChanged,
    required this.onBreakChanged,
    required this.onPickTime,
    required this.onSave,
    this.onBack,
  });

  final List<DesktopHoursDay> days;
  final String weekStartDay;

  /// (key, short label) for each weekday, in display order.
  final List<(String, String)> weekStartOptions;
  final bool saving;
  final ValueChanged<String> onWeekStart;
  final void Function(String dayKey, bool open) onOpenChanged;
  final void Function(String dayKey, bool hasBreak) onBreakChanged;
  final void Function(String dayKey, DesktopHoursField field) onPickTime;
  final VoidCallback onSave;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!saving) onSave();
        },
      },
      child: Focus(
        autofocus: true,
        child: DesktopSubPage(
          title: 'Operating hours',
          subtitle:
              'When this branch is open. The assistant uses these hours to know your trading window.',
          maxWidth: 860,
          onBack: onBack,
          actions: [
            FilledButton(
              key: const ValueKey('hours-save'),
              style: desktopPrimaryButton(context),
              onPressed: saving ? null : onSave,
              child: Text(saving ? 'Saving...' : 'Save hours'),
            ),
          ],
          scroll: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopSettingGroup(
                title: 'Week starts on',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'First day of your business week',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Weekly reports count from this day.',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DesktopSegmented<String>(
                          value: weekStartDay,
                          options: weekStartOptions,
                          onChanged: onWeekStart,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _headerLabel(p, 'Daily hours'),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: Column(
                  children: [
                    _HeaderRow(p: p),
                    for (final day in days) ...[
                      Divider(height: 1, color: p.border),
                      _DayRow(
                        day: day,
                        onOpenChanged: (v) => onOpenChanged(day.key, v),
                        onBreakChanged: (v) => onBreakChanged(day.key, v),
                        onPickTime: (f) => onPickTime(day.key, f),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerLabel(DesktopPalette p, String text) => Text(
        text,
        style: GoogleFonts.sora(
          color: p.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      );
}

const double _dayCol = 120;
const double _openCol = 140;
const double _timeCol = 104;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.p});
  final DesktopPalette p;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: _dayCol, child: Text('Day', style: style)),
          SizedBox(width: _openCol, child: Text('Open', style: style)),
          SizedBox(width: _timeCol, child: Text('Opens', style: style)),
          SizedBox(width: _timeCol, child: Text('Closes', style: style)),
          Expanded(child: Text('Midday break', style: style)),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.onOpenChanged,
    required this.onBreakChanged,
    required this.onPickTime,
  });

  final DesktopHoursDay day;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<bool> onBreakChanged;
  final ValueChanged<DesktopHoursField> onPickTime;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final open = !day.closed;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: _dayCol,
              child: Text(
                day.label,
                style: GoogleFonts.plusJakartaSans(
                  color: open ? p.text : p.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: _openCol,
              child: Row(
                children: [
                  DesktopSwitch(
                    semanticLabel: '${day.label} open',
                    value: open,
                    onChanged: onOpenChanged,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    open ? 'Open' : 'Closed',
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (!open)
              const Expanded(child: SizedBox.shrink())
            else ...[
              SizedBox(
                width: _timeCol,
                child: _TimeButton(
                  key: ValueKey('hours-${day.key}-open'),
                  value: day.open,
                  tooltip: 'Opening time for ${day.label}',
                  onTap: () => onPickTime(DesktopHoursField.open),
                ),
              ),
              SizedBox(
                width: _timeCol,
                child: _TimeButton(
                  key: ValueKey('hours-${day.key}-close'),
                  value: day.close,
                  tooltip: 'Closing time for ${day.label}',
                  onTap: () => onPickTime(DesktopHoursField.close),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        key: ValueKey('hours-${day.key}-break'),
                        value: day.hasBreak,
                        onChanged: (v) => onBreakChanged(v ?? false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!day.hasBreak)
                      Text(
                        'No break',
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12.5,
                        ),
                      )
                    else ...[
                      _TimeButton(
                        key: ValueKey('hours-${day.key}-breakStart'),
                        value: day.breakStart,
                        compact: true,
                        tooltip: 'Break starts, ${day.label}',
                        onTap: () => onPickTime(DesktopHoursField.breakStart),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          'to',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      _TimeButton(
                        key: ValueKey('hours-${day.key}-breakEnd'),
                        value: day.breakEnd,
                        compact: true,
                        tooltip: 'Break ends, ${day.label}',
                        onTap: () => onPickTime(DesktopHoursField.breakEnd),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    super.key,
    required this.value,
    required this.onTap,
    required this.tooltip,
    this.compact = false,
  });

  final String value;
  final VoidCallback onTap;
  final String tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: compact ? 72 : 86,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.borderStrong),
              ),
              child: Text(
                value,
                style: GoogleFonts.jetBrainsMono(
                  color: p.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
