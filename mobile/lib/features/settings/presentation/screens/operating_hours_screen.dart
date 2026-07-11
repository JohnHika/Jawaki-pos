import 'package:flutter/material.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';

/// Per-branch operating hours editor. The user controls, for each day of the
/// week, whether the shop is open, its open/close times, and an optional
/// midday break — plus which day their business week starts on. Saved into
/// the branch's `settings.operatingHours` (backend merges, so tax/other
/// settings are preserved). The AI reads this to reason over trading windows.
class OperatingHoursScreen extends StatefulWidget {
  const OperatingHoursScreen({super.key});

  @override
  State<OperatingHoursScreen> createState() => _OperatingHoursScreenState();
}

const _dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const _dayLabels = {
  'mon': 'Monday',
  'tue': 'Tuesday',
  'wed': 'Wednesday',
  'thu': 'Thursday',
  'fri': 'Friday',
  'sat': 'Saturday',
  'sun': 'Sunday',
};

class _DayHours {
  bool closed;
  String open;
  String close;
  bool hasBreak;
  String breakStart;
  String breakEnd;

  _DayHours({
    required this.closed,
    required this.open,
    required this.close,
    required this.hasBreak,
    required this.breakStart,
    required this.breakEnd,
  });

  factory _DayHours.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    final hasBreak = j['breakStart'] != null && j['breakEnd'] != null;
    return _DayHours(
      closed: j['closed'] == true,
      open: (j['open'] ?? '08:00').toString(),
      close: (j['close'] ?? '18:00').toString(),
      hasBreak: hasBreak,
      breakStart: (j['breakStart'] ?? '13:00').toString(),
      breakEnd: (j['breakEnd'] ?? '14:00').toString(),
    );
  }

  factory _DayHours.defaults() => _DayHours(
        closed: false,
        open: '08:00',
        close: '18:00',
        hasBreak: false,
        breakStart: '13:00',
        breakEnd: '14:00',
      );

  Map<String, dynamic> toJson() => {
        'closed': closed,
        'open': open,
        'close': close,
        if (hasBreak) 'breakStart': breakStart,
        if (hasBreak) 'breakEnd': breakEnd,
      };
}

class _OperatingHoursScreenState extends State<OperatingHoursScreen> {
  final _api = getIt<ApiClient>();
  final _storage = getIt<StorageService>();

  bool _loading = true;
  bool _saving = false;
  String _weekStartDay = 'mon';
  final Map<String, _DayHours> _days = {};

  String get _branchId => _storage.getBranchId() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_branchId.isEmpty) {
        throw Exception('No branch selected');
      }
      final branch = await _api.getBranch(_branchId);
      final settings = (branch['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      final hours = (settings['operatingHours'] as Map?)?.cast<String, dynamic>();
      final daysJson = (hours?['days'] as Map?)?.cast<String, dynamic>() ?? {};

      _weekStartDay = _dayKeys.contains(hours?['weekStartDay'])
          ? hours!['weekStartDay'] as String
          : 'mon';
      for (final key in _dayKeys) {
        _days[key] = hours != null
            ? _DayHours.fromJson((daysJson[key] as Map?)?.cast<String, dynamic>())
            : _DayHours.defaults();
      }
    } catch (e) {
      // First-time / offline: start from sensible defaults so the user can
      // still configure and save.
      for (final key in _dayKeys) {
        _days.putIfAbsent(key, () => _DayHours.defaults());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'weekStartDay': _weekStartDay,
        'days': {for (final key in _dayKeys) key: _days[key]!.toJson()},
      };
      await _api.updateBranch(_branchId, settings: {'operatingHours': payload});
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Operating hours saved',
        icon: Icons.check_circle_outline_rounded,
        color: DesignColors.success,
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Could not save hours. Check your connection and try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      onPicked('$hh:$mm');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Operating Hours'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Set when this branch is open. The assistant uses these hours '
                  'to know your trading window each day.',
                  style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                const SettingsGroupLabel('Week starts on'),
                GroupedCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _dayKeys.map((key) {
                          final selected = _weekStartDay == key;
                          return ChoiceChip(
                            label: Text(_dayLabels[key]!.substring(0, 3)),
                            selected: selected,
                            onSelected: (_) => setState(() => _weekStartDay = key),
                            selectedColor:
                                DesignColors.accent.withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              color: selected
                                  ? DesignColors.accent
                                  : (isDark
                                      ? DesignColors.darkTextPrimary
                                      : DesignColors.textPrimary),
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SettingsGroupLabel('Daily hours'),
                GroupedCard(
                  children: [
                    for (final key in _dayKeys) _buildDayRow(key, isDark, secondary),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsPrimaryButton(
                  label: 'Save hours',
                  isLoading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
    );
  }

  Widget _buildDayRow(String key, bool isDark, Color secondary) {
    final day = _days[key]!;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _dayLabels[key]!,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                day.closed ? 'Closed' : 'Open',
                style: TextStyle(color: secondary, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Switch(
                value: !day.closed,
                activeThumbColor: DesignColors.accent,
                onChanged: (open) => setState(() => day.closed = !open),
              ),
            ],
          ),
          if (!day.closed) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                _timeChip('Opens', day.open, () => _pickTime(day.open, (v) => setState(() => day.open = v)), isDark),
                const SizedBox(width: 8),
                _timeChip('Closes', day.close, () => _pickTime(day.close, (v) => setState(() => day.close = v)), isDark),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: day.hasBreak,
                  activeColor: DesignColors.accent,
                  onChanged: (v) => setState(() => day.hasBreak = v ?? false),
                ),
                Text('Midday break', style: TextStyle(color: secondary, fontSize: 13)),
              ],
            ),
            if (day.hasBreak)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    _timeChip('Break from', day.breakStart, () => _pickTime(day.breakStart, (v) => setState(() => day.breakStart = v)), isDark),
                    const SizedBox(width: 8),
                    _timeChip('to', day.breakEnd, () => _pickTime(day.breakEnd, (v) => setState(() => day.breakEnd = v)), isDark),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _timeChip(String label, String value, VoidCallback onTap, bool isDark) {
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: secondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value,
                style: DesignType.numeric(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
